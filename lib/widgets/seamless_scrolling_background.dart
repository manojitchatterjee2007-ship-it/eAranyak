import 'package:flutter/material.dart';

class SeamlessScrollingBackground extends StatefulWidget {
  final String imagePath;
  final Duration duration;

  const SeamlessScrollingBackground({
    super.key,
    required this.imagePath,
    this.duration = const Duration(seconds: 25),
  });

  @override
  State<SeamlessScrollingBackground> createState() =>
      _SeamlessScrollingBackgroundState();
}

class _SeamlessScrollingBackgroundState
    extends State<SeamlessScrollingBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final alignX = -1.0 + (_animation.value * 2.0);
        return Image.asset(
          widget.imagePath,
          fit: BoxFit.fitHeight,
          alignment: Alignment(alignX, 0.0),
          filterQuality: FilterQuality.medium,
          errorBuilder: (c, e, s) => const SizedBox.shrink(),
        );
      },
    );
  }
}
