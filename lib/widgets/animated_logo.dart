import 'package:flutter/material.dart';

class SchematicGridPainter extends CustomPainter {
  final Color accentColor;
  const SchematicGridPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 16) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 16) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    final circlePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 34, circlePaint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 22, circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class AnimatedEAranyakLogo extends StatefulWidget {
  final double size;
  const AnimatedEAranyakLogo({super.key, this.size = 140});

  @override
  State<AnimatedEAranyakLogo> createState() => _AnimatedEAranyakLogoState();
}

class _AnimatedEAranyakLogoState extends State<AnimatedEAranyakLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );

    _glow = Tween<double>(begin: 12.0, end: 28.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF141F17),
            border: Border.all(color: const Color(0xFF00E676), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.35),
                blurRadius: _glow.value,
                spreadRadius: _glow.value / 6,
              ),
            ],
          ),
          child: Transform.scale(
            scale: _scale.value,
            child: ClipOval(
              child: Image.asset(
                'assets/icon/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.eco,
                    size: 80, color: Color(0xFF00E676)),
              ),
            ),
          ),
        );
      },
    );
  }
}
