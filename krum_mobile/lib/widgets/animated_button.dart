import 'package:flutter/material.dart';

class AnimatedButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final bool isLoading;
  final Color? color;
  final double width;

  const AnimatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.color,
    this.width = double.infinity,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (!widget.isLoading) _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (!widget.isLoading) {
      _controller.reverse();
      widget.onPressed();
    }
  }

  void _onTapCancel() {
    if (!widget.isLoading) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: widget.isLoading ? 56 : widget.width,
          height: 56,
          decoration: BoxDecoration(
            color: widget.color ?? Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(widget.isLoading ? 28 : 12),
            boxShadow: [
              BoxShadow(
                color: (widget.color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    child: widget.child,
                  ),
          ),
        ),
      ),
    );
  }
}
