import 'package:flutter/material.dart';
import '../services/sound_service.dart';

class KeyboardPressEffect extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double depth;

  final ValueChanged<bool>? onPressStateChanged;

  const KeyboardPressEffect({
    super.key,
    required this.child,
    this.onTap,
    this.depth = 4.5,
    this.onPressStateChanged,
  });

  @override
  State<KeyboardPressEffect> createState() => _KeyboardPressEffectState();
}

class _KeyboardPressEffectState extends State<KeyboardPressEffect> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null && mounted) {
      setState(() => _isPressed = true);
      widget.onPressStateChanged?.call(true);
      SoundService.playButtonSound();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (mounted) setState(() => _isPressed = false);
    widget.onPressStateChanged?.call(false);
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    if (mounted) setState(() => _isPressed = false);
    widget.onPressStateChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          _isPressed ? widget.depth : 0,
          0,
        ),
        child: widget.child,
      ),
    );
  }
}
