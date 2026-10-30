import 'dart:async';
import '../../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../utils/formatters.dart';
import '../scanner/barcode_scanner_screen.dart';
import '../inventory/product_form_screen.dart';
import '../sales/sales_history_screen.dart';
import '../../utils/pdf_receipt_helper.dart';
import '../../widgets/app_search_bar.dart';
import '../cash_drawer/cash_drawer_screen.dart';

class PosScreen extends StatefulWidget {
  final VoidCallback onOpenProductCreate;
  const PosScreen({super.key, required this.onOpenProductCreate});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Split-Screen Continuous Scanner state
  bool _isLiveScannerOpen = false;
  MobileScannerController? _scannerController;
  late final AnimationController _animController;
  String? _lastScannedCode;
  DateTime? _lastScannedTime;
  String? _lastScannedBanner;
  Color _bannerColor = AppColors.primary;
  bool _isTorchOn = false;
  Timer? _bannerDismissTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bannerDismissTimer?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    _scannerController?.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _showBannerNotification(String message, Color color) {
    _bannerDismissTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _lastScannedBanner = message;
      _bannerColor = color;
    });

    _bannerDismissTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) {
        setState(() {
          _lastScannedBanner = null;
        });
      }
    });
  }

  Future<void> _playScanFeedback() async {
    // 1. Vibrate device (robust vibration)
    try {
      HapticFeedback.vibrate();
    } catch (_) {}

    // 2. Play supermarket cashier beep sound
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/beep.wav'), volume: 1.0);
    } catch (_) {
      try {
        SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  void _toggleLiveScanner() {
    setState(() {
      _isLiveScannerOpen = !_isLiveScannerOpen;
      _bannerDismissTimer?.cancel();
      if (_isLiveScannerOpen) {
        _scannerController = MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
          torchEnabled: false,
        );
      } else {
        _scannerController?.dispose();
        _scannerController = null;
        _lastScannedCode = null;
        _lastScannedBanner = null;
        _isTorchOn = false;
      }
    });
  }

  Future<void> _onLiveBarcodeDetected(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? barcode.displayValue;
      if (raw == null) continue;
      final code = raw.replaceAll(RegExp(r'[\r\n\t\u200B-\u200D\uFEFF]'), '').trim();
      if (code.isEmpty) continue;

      // Smart debounce: prevent scanning the same barcode within 1.4s
      final now = DateTime.now();
      if (_lastScannedCode == code &&
          _lastScannedTime != null &&
          now.difference(_lastScannedTime!).inMilliseconds < 1400) {
        return;
      }

      _lastScannedCode = code;
      _lastScannedTime = now;

      final provider = context.read<StoreProvider>();
      final product = await provider.findProductOrLookup(code);

      if (!mounted) return;

      if (product != null) {
        if (!product.active) {
          _playScanFeedback();
          _showBannerNotification('${product.name} is marked inactive', Colors.amber.shade800);
          return;
        }

        _playScanFeedback();
        provider.addToCart(product);
        _showBannerNotification('Added ${product.name} (+1)', AppColors.primary);
      } else {
        _playScanFeedback();
        _showBannerNotification('Code "$code" not found', Colors.red.shade700);

        // Prompt to create product
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Product Not Found'),
            content: Text('Item with code "$code" is not registered in your store yet. Would you like to add it?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductFormScreen(initialBarcode: code),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Create Product'),
              ),
            ],
          ),
        );
      }
      break;
    }
  }

  void _showManualBarcodeInput() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Barcode Manually'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode or Item Code',
            hintText: 'e.g. 615110001234',
            prefixIcon: Icon(Icons.barcode_reader),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              Navigator.pop(ctx);
              _processScannedBarcode(val.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final val = textController.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx);
                _processScannedBarcode(val);
              }
            },
            child: const Text('Add to Cart'),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveScannerView(BuildContext context, StoreProvider provider, String currency) {
    const scanWidth = 260.0;
    const scanHeight = 120.0;

    return Container(
      height: 240,
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Stream
          if (_scannerController != null)
            MobileScanner(
              controller: _scannerController!,
              onDetect: _onLiveBarcodeDetected,
              errorBuilder: (context, error) {
                return Container(
                  color: const Color(0xFF1E1E1E),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 36),
                      const SizedBox(height: 8),
                      const Text(
                        'Camera Inactive / Permission Needed',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _showManualBarcodeInput,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        icon: const Icon(Icons.keyboard, size: 16),
                        label: const Text('Enter Code Manually', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Viewfinder Target Reticle
          Center(
            child: SizedBox(
              width: scanWidth,
              height: scanHeight,
              child: Stack(
                children: [
                  // Corner brackets
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CornerBracketPainter(
                        color: Colors.greenAccent.shade400,
                        cornerLength: 22,
                        strokeWidth: 3.5,
                      ),
                    ),
                  ),

                  // Animated laser scanning line
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, _) {
                      final topOffset = (_animController.value * (scanHeight - 20)) - (scanHeight / 2 - 10);
                      return Center(
                        child: Transform.translate(
                          offset: Offset(0, topOffset),
                          child: Container(
                            width: scanWidth - 24,
                            height: 2.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.greenAccent.withValues(alpha: 0.0),
                                  Colors.greenAccent,
                                  Colors.white,
                                  Colors.greenAccent,
                                  Colors.greenAccent.withValues(alpha: 0.0),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent.withValues(alpha: 0.8),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Top control bar
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                // Live status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Live Scanner',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Torch toggle
                IconButton(
                  tooltip: _isTorchOn ? 'Turn Flash Off' : 'Turn Flash On',
                  icon: Icon(
                    _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _isTorchOn ? Colors.amber : Colors.white70,
                    size: 22,
                  ),
                  onPressed: () {
                    _scannerController?.toggleTorch();
                    setState(() => _isTorchOn = !_isTorchOn);
                  },
                ),

                // Switch Camera
                IconButton(
                  tooltip: 'Switch Camera',
                  icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white70, size: 22),
                  onPressed: () => _scannerController?.switchCamera(),
                ),

                // Manual Input
                IconButton(
                  tooltip: 'Type Barcode',
                  icon: const Icon(Icons.keyboard_outlined, color: Colors.white70, size: 22),
                  onPressed: _showManualBarcodeInput,
                ),

                // Close / Switch back to Catalog View
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _toggleLiveScanner,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.grid_view_rounded, size: 16),
                      SizedBox(width: 4),
                      Text('Catalog', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom feedback banner
          Positioned(
            bottom: 8,
            left: 16,
            right: 16,
            child: Center(
              child: _lastScannedBanner != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _bannerColor.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _bannerColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _bannerColor == AppColors.primary ? Icons.check_circle : Icons.info_outline,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _lastScannedBanner!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Align barcode in frame · Scans continuously',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }



  Future<void> _processScannedBarcode(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return;

    final provider = context.read<StoreProvider>();
    final product = await provider.findProductOrLookup(cleanCode);

    if (!mounted) return;

    if (product != null) {
      if (!product.active) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Product Inactive'),
            content: Text('"${product.name}" is marked as inactive. Please enable it in Inventory before selling.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      _playScanFeedback();
      provider.addToCart(product);
      _showBannerNotification('Added ${product.name} (+1)', AppColors.primary);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${product.name} to cart'),
          duration: const Duration(milliseconds: 1400),
          backgroundColor: AppColors.primary,
        ),
      );
    } else {
      // Barcode / item code not found: Prompt to create product with code pre-filled
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Product Not Found'),
          content: Text('Item with code "$cleanCode" is not registered in your store yet. Would you like to add it?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductFormScreen(initialBarcode: cleanCode),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Product'),
            ),
          ],
        ),
      );
    }
  }

  void _showCheckoutSheet() {
    final provider = context.read<StoreProvider>();
    final total = provider.cartTotal;
    final currency = provider.business?.currency ?? 'NGN';
    final amountPaidController = TextEditingController(text: total.toStringAsFixed(0));
    final discountController = TextEditingController(
      text: provider.cartDiscount > 0 ? provider.cartDiscount.toStringAsFixed(0) : '',
    );
    String selectedMethod = provider.paymentMethod;
    Customer? customer = provider.selectedCustomer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final paid = double.tryParse(amountPaidController.text) ?? 0.0;
          final balance = total - paid;
          final isCredit = balance > 0;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Complete Sale',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 10),

                  // Total Summary
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Payable:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          CurrencyFormatter.format(total, currency: currency),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Customer selection (Walk-in vs Debtor)
                  Row(
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final uniqueCustomers = <int, Customer>{};
                            for (final c in provider.customers) {
                              uniqueCustomers[c.id] = c;
                            }
                            final customerList = uniqueCustomers.values.toList();
                            final effectiveCustomerId = customerList.any((c) => c.id == customer?.id) ? customer?.id : null;

                            return DropdownButtonFormField<int?>(
                              value: effectiveCustomerId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Customer',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Walk-in Customer (Instant)', overflow: TextOverflow.ellipsis),
                                ),
                                ...customerList.map(
                                  (c) => DropdownMenuItem<int?>(
                                    value: c.id,
                                    child: Text(
                                      '${c.name} (Owes ${CurrencyFormatter.format(c.outstanding, currency: currency)})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setSheetState(() {
                                  customer = val == null
                                      ? null
                                      : customerList.firstWhere((c) => c.id == val);
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Add new customer',
                        icon: const Icon(Icons.person_add_alt_1),
                        onPressed: () async {
                          final nameCtrl = TextEditingController();
                          final phoneCtrl = TextEditingController();
                          final newCust = await showDialog<Customer?>(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              title: const Text('Quick Add Customer'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: nameCtrl,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Customer Name *',
                                      hintText: 'e.g. Mary Adamu',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: phoneCtrl,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: 'Phone Number (Optional)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                                  onPressed: () async {
                                    final name = nameCtrl.text.trim();
                                    if (name.isNotEmpty) {
                                      final created = await provider.createCustomer(name, phone: phoneCtrl.text.trim());
                                      if (dialogCtx.mounted) Navigator.pop(dialogCtx, created);
                                    }
                                  },
                                  child: const Text('Add'),
                                ),
                              ],
                            ),
                          );
                          if (newCust != null) {
                            setSheetState(() {
                              customer = newCust;
                            });
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Payment Method (Section 16: Cash, Bank transfer, POS, Other)
                  Row(
                    children: [
                      Expanded(
                        child: _paymentMethodRadio(
                          label: 'Cash',
                          value: 'cash',
                          selected: selectedMethod,
                          onSelect: (m) => setSheetState(() => selectedMethod = m),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _paymentMethodRadio(
                          label: 'Transfer',
                          value: 'transfer',
                          selected: selectedMethod,
                          onSelect: (m) => setSheetState(() => selectedMethod = m),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _paymentMethodRadio(
                          label: 'POS',
                          value: 'pos',
                          selected: selectedMethod,
                          onSelect: (m) => setSheetState(() => selectedMethod = m),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Discount Input
                  TextField(
                    controller: discountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Discount (₦)',
                      prefixIcon: Icon(Icons.discount_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      final disc = double.tryParse(val) ?? 0.0;
                      provider.setCartDiscount(disc);
                      setSheetState(() {
                        amountPaidController.text = provider.cartTotal.toStringAsFixed(0);
                      });
                    },
                  ),

                  const SizedBox(height: 14),

                  // Amount Paid Input (Handles Full or Credit Sales)
                  TextField(
                    controller: amountPaidController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Amount Paid (₦)',
                      prefixIcon: const Icon(Icons.paid_outlined),
                      border: const OutlineInputBorder(),
                      helperText: isCredit
                          ? 'Customer owes ${CurrencyFormatter.format(balance, currency: currency)}'
                          : 'Full payment received',
                      helperStyle: TextStyle(
                        color: isCredit ? Colors.orange.shade900 : Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),

                  if (isCredit && customer == null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Select a registered customer to track this debt.',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  FilledButton(
                    onPressed: (isCredit && customer == null)
                        ? null
                        : () async {
                            final paidAmount = double.tryParse(amountPaidController.text) ?? 0.0;
                            provider.setSelectedCustomer(customer);
                            provider.setPaymentMethod(selectedMethod);

                            try {
                              await provider.checkoutSale(amountPaid: paidAmount);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted && provider.sales.isNotEmpty) {
                                _showSaleSuccessReceiptModal(context, provider, provider.sales.first);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      isCredit
                          ? 'Record Credit Sale (${CurrencyFormatter.format(paidAmountFor(amountPaidController), currency: currency)})'
                          : 'Complete Sale (${CurrencyFormatter.format(total, currency: currency)})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSaleSuccessReceiptModal(BuildContext context, StoreProvider provider, Map<String, dynamic> sale) {
    final currency = provider.business?.currency ?? 'NGN';
    final total = (sale['total_amount'] as num?)?.toDouble() ?? (sale['total'] as num?)?.toDouble() ?? 0.0;
    final amountPaid = (sale['amount_paid'] as num?)?.toDouble() ?? total;
    final balance = (total - amountPaid) > 0 ? (total - amountPaid) : 0.0;
    final isCredit = balance > 0;
    final customerName = (sale['customer_name'] ?? 'Walk-in Customer').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 36),
              ),
              const SizedBox(height: 12),
              Text(
                isCredit ? 'Credit Sale Recorded!' : 'Sale Completed Successfully!',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '${CurrencyFormatter.format(total, currency: currency)} · $customerName',
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              if (isCredit) ...[
                const SizedBox(height: 6),
                Text(
                  'Amount Paid: ${CurrencyFormatter.format(amountPaid, currency: currency)} · Owed: ${CurrencyFormatter.format(balance, currency: currency)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.print_outlined, size: 20),
                      label: const Text('Print / PDF'),
                      onPressed: () async {
                        await PdfReceiptHelper.printOrSavePdf(sale: sale, business: provider.business);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.share_outlined, size: 20),
                      label: const Text('Share PDF'),
                      onPressed: () async {
                        await PdfReceiptHelper.shareReceiptPdf(sale: sale, business: provider.business);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const Text('Copy WhatsApp / SMS Text'),
                      onPressed: () {
                        final text = PdfReceiptHelper.generateReceiptText(sale: sale, business: provider.business);
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Receipt text copied! Ready to paste into WhatsApp.'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      },
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('New Sale'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  double paidAmountFor(TextEditingController controller) {
    return double.tryParse(controller.text) ?? 0.0;
  }

  Widget _paymentMethodRadio({
    required String label,
    required String value,
    required String selected,
    required Function(String) onSelect,
  }) {
    final isSelected = selected == value;
    return InkWell(
      onTap: () => onSelect(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.primary : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  void _addProductToCart(Product product) {
    if (!product.active) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} is marked inactive.'),
          backgroundColor: Colors.amber.shade800,
          duration: const Duration(milliseconds: 1400),
        ),
      );
      return;
    }

    final provider = context.read<StoreProvider>();
    provider.addToCart(product);

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    final inCartItems = provider.cart.where((c) => c.product.id == product.id);
    final inCartQty = inCartItems.fold<double>(0.0, (sum, c) => sum + c.quantity);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Added ${product.name} (${CurrencyFormatter.formatQty(inCartQty)} in cart)',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        action: SnackBarAction(
          label: 'View Cart',
          textColor: Colors.tealAccent,
          onPressed: () {
            final currency = provider.business?.currency ?? 'NGN';
            _showCartModal(context, provider, currency);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final currency = provider.business?.currency ?? 'NGN';

    final cleanQuery = _searchQuery.toLowerCase();
    final noZerosQuery = cleanQuery.replaceFirst(RegExp(r'^0+'), '');

    final filteredProducts = provider.products.where((p) {
      if (!p.active) return false;
      if (_searchQuery.isEmpty) return true;
      final pBarcode = p.barcode.toLowerCase();
      final pSku = p.sku.toLowerCase();
      final pName = p.name.toLowerCase();
      final pId = p.id.toString();

      if (pName.contains(cleanQuery) ||
          pBarcode.contains(cleanQuery) ||
          pSku.contains(cleanQuery) ||
          pId == cleanQuery) {
        return true;
      }

      if (noZerosQuery.isNotEmpty) {
        final bNoZero = pBarcode.replaceFirst(RegExp(r'^0+'), '');
        final sNoZero = pSku.replaceFirst(RegExp(r'^0+'), '');
        if (bNoZero.contains(noZerosQuery) || sNoZero.contains(noZerosQuery)) {
          return true;
        }
      }

      return false;
    }).toList();

    if (_isLiveScannerOpen) {
      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Half: Live Continuous Camera Viewfinder
            _buildLiveScannerView(context, provider, currency),

            // Bottom Half: Live Cart Panel with Realtime Quantity Steppers
            Expanded(
              child: Container(
                color: Colors.white,
                child: _buildCartPanel(context, provider, currency),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Top Search & Barcode Scan Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: AppSearchBar(
                    controller: _searchController,
                    hintText: 'Search product, SKU, or barcode...',
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _processScannedBarcode(val.trim());
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Live Scanner Button
                Tooltip(
                  message: 'Open Split-Screen Live Scanner',
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _toggleLiveScanner,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text(
                                'Scan',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Past Sales & Receipts Button
                Tooltip(
                  message: 'View Past Sales & Receipts',
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primaryBorder),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
                          );
                        },
                        child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cash Drawer & Shift Handover Till Bar
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CashDrawerScreen()),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: provider.isShiftActive
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: provider.isShiftActive
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFFDE68A),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: provider.isShiftActive
                          ? const Color(0xFF059669)
                          : const Color(0xFFD97706),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    provider.isShiftActive ? 'Cash Drawer Active' : 'No Active Shift',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: provider.isShiftActive
                          ? const Color(0xFF065F46)
                          : const Color(0xFF92400E),
                    ),
                  ),
                  const Spacer(),
                  if (provider.isShiftActive) ...[
                    Text(
                      'Expected: ',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(
                        provider.currentDrawerMetrics['expectedCash'] ?? 0.0,
                        currency: currency,
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Tap to Open Till',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: provider.isShiftActive
                        ? const Color(0xFF059669)
                        : const Color(0xFFD97706),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),

        // Middle Section: Product Selector List & Active Cart
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Quick-Tap List
              Expanded(
                flex: 3,
                child: filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty ? 'No products in store' : 'No matching product',
                              style: const TextStyle(fontSize: 15, color: Colors.black54),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: widget.onOpenProductCreate,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Product'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = filteredProducts[index];
                          final basePrice = product.baseUnit.sellingPrice;
                          final isOutOfStock = product.isOutOfStock;
                          final inCartItems = provider.cart.where((c) => c.product.id == product.id);
                          final inCartQty = inCartItems.fold<double>(0.0, (sum, c) => sum + c.quantity);
                          final isInCart = inCartQty > 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            color: isInCart ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: isInCart ? AppColors.primary : Colors.grey.shade200,
                                width: isInCart ? 1.5 : 1.0,
                              ),
                            ),
                            child: ListTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      product.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: isInCart ? AppColors.primaryDark : null,
                                      ),
                                    ),
                                  ),
                                  if (isInCart)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${CurrencyFormatter.formatQty(inCartQty)} in cart',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                '${CurrencyFormatter.format(basePrice, currency: currency)} / ${product.baseUnitName} · Stock: ${CurrencyFormatter.formatQty(product.stockBase)}',
                                style: TextStyle(
                                  color: isOutOfStock ? Colors.red : Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  isInCart ? Icons.add_circle : Icons.add_shopping_cart,
                                  color: AppColors.primary,
                                ),
                                onPressed: () => _addProductToCart(product),
                              ),
                              onTap: () => _addProductToCart(product),
                            ),
                          );
                        },
                      ),
              ),

              // Desktop/Tablet or Split View Cart Items
              if (MediaQuery.of(context).size.width > 680)
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: Colors.grey.shade200)),
                      color: Colors.white,
                    ),
                    child: _buildCartPanel(context, provider, currency),
                  ),
                ),
            ],
          ),
        ),

        // Bottom Cart Summary Bar for Mobile
        if (MediaQuery.of(context).size.width <= 680)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Cart summary tap to show items
                InkWell(
                  onTap: () => _showCartModal(context, provider, currency),
                  child: Row(
                    children: [
                      Badge(
                        isLabelVisible: provider.cartTotalUnits > 0,
                        label: Text('${provider.cartTotalUnits}'),
                        child: const Icon(Icons.shopping_cart_outlined, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cart Total', style: TextStyle(fontSize: 11, color: Colors.black54)),
                          Text(
                            CurrencyFormatter.format(provider.cartTotal, currency: currency),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: provider.cart.isEmpty ? null : _showCheckoutSheet,
                  icon: const Icon(Icons.check),
                  label: Text('Checkout (${provider.cartTotalUnits})'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPanel(BuildContext context, StoreProvider provider, String currency) {
    if (provider.cart.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.black26),
              const SizedBox(height: 12),
              Text(
                _isLiveScannerOpen ? 'Live Scanner Ready' : 'Your cart is empty',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                _isLiveScannerOpen
                    ? 'Point camera at product barcodes above.\nScanned items appear here with instant quantity controls.'
                    : 'Tap products or scan barcode to add to cart',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              if (!_isLiveScannerOpen) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _toggleLiveScanner,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Start Live Scanner'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cart (${provider.cartTotalUnits} items)',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: provider.clearCart,
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: provider.cart.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = provider.cart[index];
              return _cartItemRow(context, provider, item, index, currency);
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal:', style: TextStyle(color: Colors.black54)),
                  Text(CurrencyFormatter.format(provider.cartSubtotal, currency: currency)),
                ],
              ),
              if (provider.cartDiscount > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Discount:', style: TextStyle(color: Colors.red)),
                    Text('-${CurrencyFormatter.format(provider.cartDiscount, currency: currency)}', style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(
                    CurrencyFormatter.format(provider.cartTotal, currency: currency),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  _showCheckoutSheet();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Checkout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cartItemRow(BuildContext context, StoreProvider provider, CartItem item, int index, String currency) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.product.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Text(
                CurrencyFormatter.format(item.total, currency: currency),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Unit Selector (Section 11, 12, 13: piece vs crate vs carton)
              if (item.product.allUnits.length > 1)
                DropdownButton<ProductUnit>(
                  value: item.product.allUnits.firstWhere(
                    (u) =>
                        (u.unitId != 0 && item.selectedUnit.unitId != 0 && u.unitId == item.selectedUnit.unitId) ||
                        (u.id != 0 && item.selectedUnit.id != 0 && u.id == item.selectedUnit.id) ||
                        u.unitName.toLowerCase() == item.selectedUnit.unitName.toLowerCase(),
                    orElse: () => item.product.allUnits.first,
                  ),
                  isDense: true,
                  underline: const SizedBox(),
                  items: item.product.allUnits.map((u) {
                    return DropdownMenuItem<ProductUnit>(
                      value: u,
                      child: Text(
                        '${u.unitName} (${CurrencyFormatter.format(u.sellingPrice, currency: currency)})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }).toList(),
                  onChanged: (newUnit) {
                    if (newUnit != null) {
                      provider.updateCartItemUnit(index, newUnit);
                    }
                  },
                )
              else
                Text(
                  '${item.selectedUnit.unitName} · ${CurrencyFormatter.format(item.unitPrice, currency: currency)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),

              const Spacer(),

              // Quantity Stepper
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => provider.updateCartQuantity(index, item.quantity - 1),
              ),
              Text(
                CurrencyFormatter.formatQty(item.quantity),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.primary),
                onPressed: () => provider.updateCartQuantity(index, item.quantity + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCartModal(BuildContext context, StoreProvider provider, String currency) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer<StoreProvider>(
        builder: (modalCtx, modalProvider, _) => SizedBox(
          height: MediaQuery.of(modalCtx).size.height * 0.7,
          child: _buildCartPanel(modalCtx, modalProvider, currency),
        ),
      ),
    );
  }
}
