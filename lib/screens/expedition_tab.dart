import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/keyboard_press_effect.dart';

class ExpeditionTab extends StatefulWidget {
  final VoidCallback onActivated;
  final bool expanded;

  const ExpeditionTab({
    super.key,
    required this.onActivated,
    this.expanded = false,
  });

  @override
  State<ExpeditionTab> createState() => _ExpeditionTabState();
}

class _ExpeditionTabState extends State<ExpeditionTab>
    with TickerProviderStateMixin {
  late final AnimationController _walkController;
  late final AnimationController _rippleController;
  late final AnimationController _accentController;
  bool _surfacePressed = false;

  static const double _pugAspect = 1024 / 1536;
  static const String _pugAsset = 'assets/images/pug_mark.png';
  static const double _walkCycleSeconds = 34.0;
  static const double _pugWindow = 4.0;
  static const double _fadeIn = 1.4;
  static const double _fadeOut = 1.4;

  @override
  void initState() {
    super.initState();
    _walkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 34000),
    )..repeat();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _accentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  @override
  void dispose() {
    _walkController.dispose();
    _rippleController.dispose();
    _accentController.dispose();
    super.dispose();
  }

  double _pugOpacity(double t, int index) {
    final double local = t - index * _pugWindow;
    if (local <= 0 || local >= _pugWindow) return 0;
    if (local < _fadeIn) {
      return Curves.easeOutCubic.transform(local / _fadeIn);
    }
    final double fromEnd = _pugWindow - local;
    if (fromEnd < _fadeOut) {
      return Curves.easeInCubic.transform(fromEnd / _fadeOut);
    }
    return 1.0;
  }

  double _pugEmergeScale(double t, int index) {
    final double local = t - index * _pugWindow;
    if (local <= 0) return 0.92;
    if (local >= _fadeIn) return 1.0;
    return 0.92 + 0.08 * Curves.easeOutCubic.transform(local / _fadeIn);
  }

  void _handlePressChanged(bool pressed) {
    _surfacePressed = pressed;
    if (pressed) _accentController.forward(from: 0);
  }

  void _handleActivated() {
    _rippleController.forward(from: 0);
    _accentController.forward(from: 0);
    widget.onActivated();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardPressEffect(
      onTap: _handleActivated,
      onPressStateChanged: _handlePressChanged,
      depth: 5.5,
      child: _buildSurface(),
    );
  }

  Widget _buildSurface() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF121D12),
            Color(0xFF0A120B),
            Color(0xFF0F1B10),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: const Color(0xFF2A4A30).withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: const Color(0xFF1E3A22).withValues(alpha: 0.12),
            blurRadius: 34,
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.75, -1.35),
                    radius: 1.4,
                    colors: [
                      const Color(0xFF2E5A38).withValues(alpha: 0.30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.95, 1.5),
                    radius: 1.3,
                    colors: [
                      const Color(0xFF24462C).withValues(alpha: 0.20),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.4],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation:
                    Listenable.merge([_walkController, _accentController]),
                builder: (context, _) => _buildPugmarkTrail(),
              ),
            ),
            Positioned(
              top: 0,
              left: 28,
              right: 28,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      const Color(0xFF6FAE7C).withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🐾',
                    style: TextStyle(
                      fontSize: 26,
                      shadows: [
                        Shadow(color: Color(0xFF3E7A4A), blurRadius: 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Flexible(
                        child: Text(
                          'Travel with এখন আরণ্যক',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            height: 1.25,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF16281B).withValues(alpha: 0.7),
                          border: Border.all(
                            color:
                                const Color(0xFF3E7A4A).withValues(alpha: 0.55),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'click here..',
                          style: TextStyle(
                            color: Color(0xFF8FBE93),
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'EXPLORE  •  STAY  •  DISCOVER',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8FBE93),
                      fontSize: 10.5,
                      letterSpacing: 3.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: AnimatedRotation(
                    turns: widget.expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white38,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _rippleController,
                  builder: (context, _) => CustomPaint(
                    painter: ExpeditionRipplePainter(_rippleController.value),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPugmarkTrail() {
    final double t = _walkController.value * _walkCycleSeconds;
    final double accent = _surfacePressed
        ? 1.0
        : math.sin(math.pi * _accentController.value);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double pugW =
            (constraints.maxWidth * 0.145).clamp(52.0, 92.0).toDouble();
        final double pugH = pugW / _pugAspect;

        const tilt = 0.08;
        const trail = <(Offset, double)>[
          (Offset(0.35, 0.12), -tilt),
          (Offset(0.52, -0.18), tilt),
          (Offset(0.70, 0.12), -tilt),
          (Offset(0.86, -0.18), tilt),
          (Offset(0.82, 0.12), math.pi - tilt),
          (Offset(0.66, -0.18), math.pi + tilt),
          (Offset(0.48, 0.12), math.pi - tilt),
          (Offset(0.30, -0.18), math.pi + tilt),
        ];
        return Stack(
          children: [
            for (int i = 0; i < trail.length; i++)
              _buildSinglePugmark(
                position: trail[i].$1,
                index: i,
                t: t,
                accent: accent,
                width: pugW,
                height: pugH,
                rotation: trail[i].$2,
              ),
          ],
        );
      },
    );
  }

  Widget _buildSinglePugmark({
    required Offset position,
    required int index,
    required double t,
    required double accent,
    required double width,
    required double height,
    double rotation = 0.0,
  }) {
    final double base = _pugOpacity(t, index);
    if (base <= 0.001) return const SizedBox.shrink();

    final double opacity =
        (base * 0.9 * (1.0 + 0.55 * accent)).clamp(0.0, 0.95);
    final double scale = _pugEmergeScale(t, index) * (1.0 - 0.035 * accent);

    return Align(
      alignment: Alignment(position.dx, position.dy),
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, 3 * accent),
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: width * 2.4,
              height: height * 2.4,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF3E7A4A).withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    height: height,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateZ(rotation),
                      child: Image.asset(
                        _pugAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExpeditionRipplePainter extends CustomPainter {
  final double progress;
  ExpeditionRipplePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001 || progress >= 0.999) return;
    final double t = Curves.easeOutCubic.transform(progress);
    final double fade = 1.0 - t;
    final Offset center = Offset(size.width * 0.5, size.height * 0.55);
    final double radius =
        math.max(size.width, size.height) * 0.85 * (0.15 + 0.85 * t);

    final Paint glow = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF4CAF50).withValues(alpha: 0.13 * fade),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glow);

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * fade + 0.4
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.38 * fade);
    canvas.drawCircle(center, radius, ring);
  }

  @override
  bool shouldRepaint(covariant ExpeditionRipplePainter old) =>
      old.progress != progress;
}
