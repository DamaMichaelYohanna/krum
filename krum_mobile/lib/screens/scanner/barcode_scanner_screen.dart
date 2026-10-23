import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../theme/app_colors.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final String title;
  final String hint;

  const BarcodeScannerScreen({
    super.key,
    this.title = 'Scan Barcode',
    this.hint = 'Align barcode inside the frame to scan',
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _animController;
  bool _isScanned = false;
  final TextEditingController _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    _manualController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? barcode.displayValue;
      if (raw != null) {
        final code = raw.replaceAll(RegExp(r'[\r\n\t\u200B-\u200D\uFEFF]'), '').trim();
        if (code.isNotEmpty) {
          _isScanned = true;
          try {
            HapticFeedback.vibrate();
          } catch (_) {}
          try {
            SystemSound.play(SystemSoundType.click);
          } catch (_) {}
          Navigator.pop(context, code);
          break;
        }
      }
    }
  }

  void _showManualInputDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Enter Barcode Manually',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manualController,
              autofocus: true,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Barcode Number / Code',
                hintText: 'e.g. 6151234567890',
                prefixIcon: const Icon(Icons.barcode_reader),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _manualController.clear(),
                ),
              ),
              onSubmitted: (val) {
                final trimmed = val.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.pop(ctx);
                  Navigator.pop(context, trimmed);
                }
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final trimmed = _manualController.text.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.pop(ctx);
                  Navigator.pop(context, trimmed);
                }
              },
              child: const Text('Use Barcode', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const scanAreaSize = 260.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          // Torch toggle
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final isOn = state.torchState == TorchState.on;
              return IconButton(
                tooltip: isOn ? 'Turn flash off' : 'Turn flash on',
                icon: Icon(
                  isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: isOn ? Colors.amber : Colors.white70,
                ),
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
          // Flip camera
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white70),
            onPressed: () => _controller.switchCamera(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Mobile Scanner Camera View
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Container(
                color: const Color(0xFF1E1E1E),
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Camera Not Available',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Camera permission is required or camera device is inactive on this emulator.\nYou can enter the barcode manually below:',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _showManualInputDialog,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      label: const Text('Enter Barcode Manually', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
          ),

          // Scanning Reticle & Dim Overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Viewfinder Box
                  Container(
                    width: scanAreaSize,
                    height: scanAreaSize,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),

                  // Animated laser scanning line
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      final topOffset = (_animController.value * (scanAreaSize - 40)) - (scanAreaSize / 2 - 20);
                      return Transform.translate(
                        offset: Offset(0, topOffset),
                        child: Container(
                          width: scanAreaSize - 20,
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.0),
                                AppColors.primary,
                                Colors.greenAccent.shade100,
                                AppColors.primary,
                                AppColors.primary.withValues(alpha: 0.0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.8),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Viewfinder Corner Brackets
                  SizedBox(
                    width: scanAreaSize,
                    height: scanAreaSize,
                    child: CustomPaint(
                      painter: CornerBracketPainter(color: AppColors.primary, cornerLength: 28, strokeWidth: 4),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Controls & Manual Entry
          Positioned(
            left: 20,
            right: 20,
            bottom: 36,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showManualInputDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.keyboard_alt_outlined),
                    label: const Text(
                      'Enter Barcode Manually',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CornerBracketPainter extends CustomPainter {
  final Color color;
  final double cornerLength;
  final double strokeWidth;

  CornerBracketPainter({
    required this.color,
    required this.cornerLength,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    const r = 16.0;

    // Top-left
    final pathTL = Path()
      ..moveTo(0, cornerLength)
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..lineTo(cornerLength, 0);
    canvas.drawPath(pathTL, paint);

    // Top-right
    final pathTR = Path()
      ..moveTo(w - cornerLength, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, cornerLength);
    canvas.drawPath(pathTR, paint);

    // Bottom-left
    final pathBL = Path()
      ..moveTo(0, h - cornerLength)
      ..lineTo(0, h - r)
      ..arcToPoint(Offset(r, h), radius: const Radius.circular(r))
      ..lineTo(cornerLength, h);
    canvas.drawPath(pathBL, paint);

    // Bottom-right
    final pathBR = Path()
      ..moveTo(w - cornerLength, h)
      ..lineTo(w - r, h)
      ..arcToPoint(Offset(w, h - r), radius: const Radius.circular(r))
      ..lineTo(w, h - cornerLength);
    canvas.drawPath(pathBR, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
