import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../purchases/add_purchase_screen.dart';

class LowStockScreen extends StatefulWidget {
  final int? initialSupplierId;
  const LowStockScreen({super.key, this.initialSupplierId});

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all', 'out_of_stock', 'low_stock'
  int? _selectedSupplierId;
  final Map<int, double> _orderQuantities = {};
  final Set<int> _selectedProductIds = {};

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.initialSupplierId;
  }

  double _getQuantityForProduct(Product product) {
    if (_orderQuantities.containsKey(product.id)) {
      return _orderQuantities[product.id]!;
    }
    return product.suggestedReorderQty;
  }

  void _setQuantityForProduct(Product product, double qty) {
    setState(() {
      _orderQuantities[product.id] = qty.clamp(1.0, 99999.0);
    });
  }

  List<Product> _filterProducts(List<Product> products) {
    return products.where((p) {
      if (!p.active || !p.needsRestock) return false;

      // Filter by stock level
      if (_selectedFilter == 'out_of_stock' && !p.isOutOfStock) return false;
      if (_selectedFilter == 'low_stock' && (!p.isLowStock || p.isOutOfStock)) return false;

      // Filter by supplier
      if (_selectedSupplierId != null && p.preferredSupplierId != _selectedSupplierId) {
        return false;
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatches = p.name.toLowerCase().contains(q);
        final skuMatches = p.sku.toLowerCase().contains(q);
        final barcodeMatches = p.barcode.toLowerCase().contains(q);
        final supplierMatches = (p.preferredSupplierName ?? '').toLowerCase().contains(q);
        if (!nameMatches && !skuMatches && !barcodeMatches && !supplierMatches) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _selectAll(List<Product> items) {
    setState(() {
      if (_selectedProductIds.length == items.length) {
        _selectedProductIds.clear();
      } else {
        _selectedProductIds.clear();
        for (final p in items) {
          _selectedProductIds.add(p.id);
        }
      }
    });
  }

  void _showPurchaseOrderPreviewSheet(BuildContext context, List<Product> allProducts) {
    final provider = context.read<StoreProvider>();
    final currency = provider.business?.currency ?? 'NGN';
    final suppliers = provider.suppliers;

    final selectedItems = allProducts.where((p) => _selectedProductIds.contains(p.id)).toList();
    if (selectedItems.isEmpty) return;

    // Detect if items share a common supplier
    int? defaultSupplierId;
    final firstWithSup = selectedItems.firstWhere(
      (p) => p.preferredSupplierId != null,
      orElse: () => selectedItems.first,
    );
    if (firstWithSup.preferredSupplierId != null) {
      defaultSupplierId = firstWithSup.preferredSupplierId;
    }

    int? modalSupplierId = defaultSupplierId;
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Supplier? activeSupplier;
          if (modalSupplierId != null) {
            final match = suppliers.where((s) => s.id == modalSupplierId);
            if (match.isNotEmpty) activeSupplier = match.first;
          }

          final orderPayload = selectedItems.map((p) {
            final unit = p.baseUnit;
            final qty = _getQuantityForProduct(p);
            final unitCost = unit.costPrice > 0 ? unit.costPrice : (p.averageCost > 0 ? p.averageCost : 0.0);
            return {
              'product': p,
              'unit': unit,
              'name': p.name,
              'unit_name': unit.unitName,
              'quantity': qty,
              'unit_cost': unitCost,
              'selling_price': unit.sellingPrice,
            };
          }).toList();

          final poText = provider.generatePurchaseOrderText(
            supplier: activeSupplier,
            items: orderPayload,
            notes: notesController.text,
          );

          final grandTotal = orderPayload.fold<double>(
            0.0,
            (sum, item) => sum + ((item['quantity'] as double) * (item['unit_cost'] as double)),
          );

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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.description_outlined, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Purchase Order Requisition',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(bCtx),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Supplier Picker
                  Builder(
                    builder: (context) {
                      final uniqueSuppliers = <int, Supplier>{};
                      for (final s in suppliers) {
                        uniqueSuppliers[s.id] = s;
                      }
                      final supplierList = uniqueSuppliers.values.toList();
                      final effectiveSupplierId = supplierList.any((s) => s.id == modalSupplierId) ? modalSupplierId : null;

                      return DropdownButtonFormField<int?>(
                        value: effectiveSupplierId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Select Supplier to Order From',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.local_shipping_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('General / Unassigned Supplier', overflow: TextOverflow.ellipsis),
                          ),
                          ...supplierList.map((s) => DropdownMenuItem<int?>(
                                value: s.id,
                                child: Text('${s.name} ${s.phone.isNotEmpty ? "(${s.phone})" : ""}', overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (val) {
                          setSheetState(() => modalSupplierId = val);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // Optional Order Notes
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Order Notes / Delivery instructions (Optional)',
                      hintText: 'e.g. Please deliver before Friday morning',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // Order Summary Box
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${selectedItems.length} Product Lines Requested:', style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              CurrencyFormatter.format(grandTotal, currency: currency),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 140),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: selectedItems.length,
                            separatorBuilder: (_, __) => const Divider(height: 12),
                            itemBuilder: (_, idx) {
                              final p = selectedItems[idx];
                              final qty = _getQuantityForProduct(p);
                              final cost = p.baseUnit.costPrice > 0 ? p.baseUnit.costPrice : p.averageCost;
                              return Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${CurrencyFormatter.formatQty(qty)} ${p.baseUnitName} × ${CurrencyFormatter.format(cost, currency: currency)}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons: Share via WhatsApp & Batch Receive
                  Row(
                    children: [
                      // Share / Copy Text Button
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFF25D366), width: 1.5),
                            foregroundColor: const Color(0xFF075E54),
                          ),
                          icon: const Icon(Icons.share_rounded, color: Color(0xFF25D366)),
                          label: const Text('Share / WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(bCtx);
                            Clipboard.setData(ClipboardData(text: poText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Purchase Order copied! Ready to paste into WhatsApp / SMS.'),
                                backgroundColor: Color(0xFF075E54),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),

                      // 1-Tap Receive into Stock
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Receive All Now', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            Navigator.pop(bCtx);
                            final success = await provider.batchReceiveStock(
                              supplierId: modalSupplierId,
                              items: orderPayload,
                              reference: 'Restock PO ${DateFormat('yyyyMMdd').format(DateTime.now())}',
                            );
                            if (context.mounted) {
                              if (success) {
                                setState(() {
                                  _selectedProductIds.clear();
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Successfully restocked ${selectedItems.length} products! Stock levels updated.'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to restock: ${provider.errorMessage}'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final currency = provider.business?.currency ?? 'NGN';
    final suppliers = provider.suppliers;

    final allLowStock = provider.lowStockProducts;
    final outOfStockCount = provider.outOfStockProducts.length;
    final lowStockOnlyCount = allLowStock.length - outOfStockCount;
    final totalBudget = provider.totalRestockBudget;

    final displayedProducts = _filterProducts(allLowStock);
    final areAllSelected = displayedProducts.isNotEmpty &&
        displayedProducts.every((p) => _selectedProductIds.contains(p.id));

    // Calculate budget for currently selected items
    final selectedItems = allLowStock.where((p) => _selectedProductIds.contains(p.id)).toList();
    final selectedBudget = selectedItems.fold<double>(
      0.0,
      (sum, p) => sum + (_getQuantityForProduct(p) * (p.baseUnit.costPrice > 0 ? p.baseUnit.costPrice : p.averageCost)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Low Stock & Restock Hub'),
        actions: [
          if (displayedProducts.isNotEmpty)
            TextButton.icon(
              onPressed: () => _selectAll(displayedProducts),
              icon: Icon(
                areAllSelected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: Colors.white,
              ),
              label: Text(
                areAllSelected ? 'Deselect All' : 'Select All',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // KPI Summary Cards
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  // Low Stock Card
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Low Stock',
                      count: lowStockOnlyCount,
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFD97706),
                      bgColor: const Color(0xFFFFFBEB),
                      borderColor: const Color(0xFFFDE68A),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Out of Stock Card
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Out of Stock',
                      count: outOfStockCount,
                      icon: Icons.cancel_outlined,
                      color: const Color(0xFFDC2626),
                      bgColor: const Color(0xFFFEF2F2),
                      borderColor: const Color(0xFFFECACA),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Estimated Restock Budget Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.account_balance_wallet_outlined, size: 16, color: Colors.white70),
                              SizedBox(width: 4),
                              Text('Restock Est.', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              CurrencyFormatter.format(totalBudget, currency: currency),
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar & Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search product, SKU, or supplier...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),

            // Filter Chips (All, Out of Stock, Low Stock, and Suppliers)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _buildFilterChip('All (${allLowStock.length})', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Out of Stock ($outOfStockCount)', 'out_of_stock'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Low Stock ($lowStockOnlyCount)', 'low_stock'),
                  if (suppliers.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Container(height: 20, width: 1, color: Colors.grey.shade300),
                    const SizedBox(width: 12),
                    Builder(
                      builder: (context) {
                        final uniqueSuppliers = <int, Supplier>{};
                        for (final s in suppliers) {
                          uniqueSuppliers[s.id] = s;
                        }
                        final supplierList = uniqueSuppliers.values.toList();
                        final effectiveSupplierId = supplierList.any((s) => s.id == _selectedSupplierId) ? _selectedSupplierId : null;

                        return DropdownButton<int?>(
                          value: effectiveSupplierId,
                          isDense: true,
                          underline: const SizedBox(),
                          hint: const Text('Filter by Supplier', style: TextStyle(fontSize: 12)),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('All Suppliers', style: TextStyle(fontSize: 12))),
                            ...supplierList.map((s) => DropdownMenuItem<int?>(
                                  value: s.id,
                                  child: Text(s.name, style: const TextStyle(fontSize: 12)),
                                )),
                          ],
                          onChanged: (val) => setState(() => _selectedSupplierId = val),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 16),

            // Main Product List
            Expanded(
              child: displayedProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            allLowStock.isEmpty
                                ? 'Healthy Inventory Levels!'
                                : 'No items match your filter.',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            allLowStock.isEmpty
                                ? 'All active products are above their reorder thresholds.'
                                : 'Try adjusting the search query or supplier filters.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, _selectedProductIds.isNotEmpty ? 100 : 20),
                      itemCount: displayedProducts.length,
                      itemBuilder: (ctx, index) {
                        final product = displayedProducts[index];
                        final isSelected = _selectedProductIds.contains(product.id);
                        final orderQty = _getQuantityForProduct(product);
                        final unitCost = product.baseUnit.costPrice > 0
                            ? product.baseUnit.costPrice
                            : product.averageCost;
                        final lineEstCost = orderQty * unitCost;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : (product.isOutOfStock ? const Color(0xFFFECACA) : const Color(0xFFFDE68A)),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top row: Checkbox, Name, Status Badge
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          if (isSelected) {
                                            _selectedProductIds.remove(product.id);
                                          } else {
                                            _selectedProductIds.add(product.id);
                                          }
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 10, top: 2),
                                        child: Icon(
                                          isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                          color: isSelected ? AppColors.primary : Colors.grey.shade400,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              if (product.categoryName != null && product.categoryName!.isNotEmpty) ...[
                                                Text(
                                                  product.categoryName!,
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                ),
                                                Text(' · ', style: TextStyle(color: Colors.grey.shade400)),
                                              ],
                                              Text(
                                                'SKU: ${product.sku.isNotEmpty ? product.sku : "N/A"}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Out of Stock or Low badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: product.isOutOfStock ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: product.isOutOfStock ? const Color(0xFFFCA5A5) : const Color(0xFFFDE68A),
                                        ),
                                      ),
                                      child: Text(
                                        product.isOutOfStock
                                            ? 'Out of Stock'
                                            : '${CurrencyFormatter.formatQty(product.stockBase)} left',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: product.isOutOfStock ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Stock deficit progress & target
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Reorder Threshold: ${CurrencyFormatter.formatQty(product.reorderLevel)} ${product.baseUnitName}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                      ),
                                      Text(
                                        'Target: ${CurrencyFormatter.formatQty(product.targetHealthyStock)}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Supplier info tag if available
                                if (product.preferredSupplierName != null && product.preferredSupplierName!.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      const Icon(Icons.local_shipping_outlined, size: 14, color: AppColors.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Preferred Supplier: ${product.preferredSupplierName}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                // Reorder quantity stepper & budget estimate
                                Row(
                                  children: [
                                    const Text('Order Qty:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 10),

                                    // Stepper container
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade300),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () => _setQuantityForProduct(product, orderQty - 1),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              child: Icon(Icons.remove, size: 16),
                                            ),
                                          ),
                                          Container(
                                            constraints: const BoxConstraints(minWidth: 36),
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Text(
                                              CurrencyFormatter.formatQty(orderQty),
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => _setQuantityForProduct(product, orderQty + 1),
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              child: Icon(Icons.add, size: 16),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(product.baseUnitName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                    const Spacer(),

                                    // Line total cost
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Est: ${CurrencyFormatter.format(lineEstCost, currency: currency)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                                        ),
                                        Text(
                                          '@ ${CurrencyFormatter.format(unitCost, currency: currency)}/ea',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Single-item 1-Tap Restock & Quick WhatsApp buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          foregroundColor: const Color(0xFF075E54),
                                          side: const BorderSide(color: Color(0xFF25D366)),
                                        ),
                                        icon: const Icon(Icons.share_outlined, size: 16, color: Color(0xFF25D366)),
                                        label: const Text('WhatsApp', style: TextStyle(fontSize: 12)),
                                        onPressed: () {
                                          final quickPo = provider.generatePurchaseOrderText(
                                            supplier: product.preferredSupplierId != null
                                                ? suppliers.firstWhere(
                                                    (s) => s.id == product.preferredSupplierId,
                                                    orElse: () => Supplier(id: 0, name: product.preferredSupplierName ?? ''),
                                                  )
                                                : null,
                                            items: [
                                              {
                                                'name': product.name,
                                                'unit_name': product.baseUnitName,
                                                'quantity': orderQty,
                                                'unit_cost': unitCost,
                                              }
                                            ],
                                          );
                                          Clipboard.setData(ClipboardData(text: quickPo));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Order requisition copied to clipboard for WhatsApp!'),
                                              backgroundColor: Color(0xFF075E54),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                        ),
                                        icon: const Icon(Icons.add_shopping_cart, size: 16),
                                        label: const Text('Receive Stock', style: TextStyle(fontSize: 12)),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => AddPurchaseScreen(
                                                initialProduct: product,
                                                initialQuantity: orderQty,
                                                initialSupplierId: product.preferredSupplierId,
                                                initialUnitCost: unitCost,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // Sticky Bottom Bar for Multi-Select Action
      bottomSheet: _selectedProductIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_selectedProductIds.length} items selected',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Est. ${CurrencyFormatter.format(selectedBudget, currency: currency)}',
                        style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('Generate Requisition', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _showPurchaseOrderPreviewSheet(context, allLowStock),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = value),
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppColors.primary : Colors.black87,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
