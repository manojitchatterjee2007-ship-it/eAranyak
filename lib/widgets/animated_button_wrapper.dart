import 'package:flutter/material.dart';

class AnimatedButtonWrapper extends StatefulWidget {
  final Widget child;

  const AnimatedButtonWrapper({super.key, required this.child});

  @override
  State<AnimatedButtonWrapper> createState() => _AnimatedButtonWrapperState();
}

class _AnimatedButtonWrapperState extends State<AnimatedButtonWrapper> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _isPressed = true),
      onPointerUp: (_) => setState(() => _isPressed = false),
      onPointerCancel: (_) => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeIn,
        transform: Matrix4.translationValues(0.0, _isPressed ? 4.0 : 0.0, 0.0),
        child: widget.child,
      ),
    );
  }
}
