import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/sound_service.dart';
import '../screens/magazine_reader_screen.dart';

const String _aranyakFrontCoverAsset =
    'assets/images/banglar_ubhochar_front.png';
const String _aranyakBackCoverAsset = 'assets/images/banglar_ubhochar_back.png';
const String _aranyakPreviewPdfAsset =
    'assets/books/banglar_ubhochar_preview_enhanced.pdf';

class AranyakHardboundBookCard extends StatefulWidget {
  const AranyakHardboundBookCard({super.key});

  @override
  State<AranyakHardboundBookCard> createState() =>
      _AranyakHardboundBookCardState();
}

class _BookPart {
  final double z;
  final Widget child;
  _BookPart({required this.z, required this.child});
}

class _AranyakHardboundBookCardState extends State<AranyakHardboundBookCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _autoRotateCtrl;
  double _rotationY = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _autoRotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..addListener(() {
        if (!_isDragging) {
          setState(() {
            _rotationY += 0.005;
            if (_rotationY > math.pi) _rotationY -= 2 * math.pi;
          });
        }
      });
    _autoRotateCtrl.repeat();
  }

  @override
  void dispose() {
    _autoRotateCtrl.dispose();
    super.dispose();
  }

  void _updateRotation(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    setState(() {
      _rotationY += (details.primaryDelta ?? 0.0) / width * math.pi;
      if (_rotationY > math.pi) _rotationY -= 2 * math.pi;
      if (_rotationY < -math.pi) _rotationY += 2 * math.pi;
    });
  }

  void _resetRotation() {
    setState(() {
      _rotationY = 0.0;
    });
  }

  void _openInside() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AranyakPdfReaderScreen(
          assetPath: _aranyakPreviewPdfAsset,
          title: 'বাংলার উভচর',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final double width = math.min(
              210.0,
              math.max(170.0, constraints.maxWidth - 48.0),
            );
            const double bookHeight = 280.0;

            return GestureDetector(
              onHorizontalDragStart: (_) {
                _isDragging = true;
              },
              onHorizontalDragUpdate: (details) {
                _updateRotation(details, width);
              },
              onHorizontalDragEnd: (_) {
                _isDragging = false;
              },
              onDoubleTap: _resetRotation,
              child: SizedBox(
                width: width + 40,
                height: bookHeight + 20,
                child: Center(
                  child: _buildThreeDimensionalBook(
                    width: width,
                    height: bookHeight,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 2),
        Text(
          _isDragging
              ? 'Drag to rotate • ঘুরিয়ে দেখুন'
              : 'Swipe / drag to rotate • সামনে ও পিছন দেখুন',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 9),
        ElevatedButton.icon(
          onPressed: () {
            SoundService.playButtonSound();
            _openInside();
          },
          icon: Image.asset('assets/images/look_inside.png',
              width: 30,
              height: 30,
              filterQuality: FilterQuality.medium),
          label: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Look Inside',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '(বইটি দেখুন)',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 9,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            elevation: 5,
          ),
        ),
      ],
    );
  }

  Widget _buildThreeDimensionalBook({
    required double width,
    required double height,
  }) {
    const double bookThickness = 22.0;
    const double spineThickness = 27.0;
    const double pageThickness = 19.0;

    final double angle = _rotationY;

    final double cosA = math.cos(angle);
    final double sinA = math.sin(angle);

    double computeZ(double localX, double localZ) {
      return -localX * sinA + localZ * cosA;
    }

    final List<_BookPart> parts = [];

    parts.add(
      _BookPart(
        z: computeZ(0, -bookThickness / 2),
        child: Opacity(
          opacity: (-cosA).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setTranslationRaw(
                0.0,
                0.0,
                -bookThickness / 2,
              ),
            child: _coverFace(
              _aranyakBackCoverAsset,
              width,
              height,
              isFront: false,
            ),
          ),
        ),
      ),
    );

    parts.add(
      _BookPart(
        z: computeZ(0, bookThickness / 2),
        child: Opacity(
          opacity: cosA.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setTranslationRaw(
                0.0,
                0.0,
                bookThickness / 2,
              ),
            child: _coverFace(
              _aranyakFrontCoverAsset,
              width,
              height,
              isFront: true,
            ),
          ),
        ),
      ),
    );

    final double spineZFront = computeZ(-width / 2, bookThickness / 2);
    final double spineZBack = computeZ(-width / 2, -bookThickness / 2);

    parts.add(
      _BookPart(
        z: math.max(spineZFront, spineZBack) + 3.0,
        child: Opacity(
          opacity: (sinA.abs() * 3.2).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setTranslationRaw(
                -width / 2,
                0.0,
                0.0,
              )
              ..rotateY((math.pi / 2) - 0.025),
            child: Image.asset(
              'assets/images/spine.png',
              width: spineThickness,
              height: height,
              fit: BoxFit.fill,
            ),
          ),
        ),
      ),
    );

    final double pageZFront = computeZ(width / 2, bookThickness / 2);
    final double pageZBack = computeZ(width / 2, -bookThickness / 2);

    parts.add(
      _BookPart(
        z: math.max(pageZFront, pageZBack) + 0.8,
        child: Opacity(
          opacity: (sinA.abs() * 2.2).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setTranslationRaw(
                width / 2,
                0.0,
                0.0,
              )
              ..rotateY((math.pi / 2) - 0.025),
            child: SizedBox(
              width: pageThickness,
              height: height - 7,
              child: Image.asset(
                'assets/images/page_block.png',
                width: pageThickness,
                height: height - 7,
                fit: BoxFit.fill,
              ),
            ),
          ),
        ),
      ),
    );

    parts.sort((a, b) => a.z.compareTo(b.z));

    return Center(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(angle),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: parts.map((part) => part.child).toList(),
          ),
        ),
      ),
    );
  }

  Widget _coverFace(
      String asset,
      double width,
      double height, {
        required bool isFront,
      }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 18,
            spreadRadius: 1,
            offset: Offset(7, 9),
          ),
          BoxShadow(
            color: Colors.black38,
            blurRadius: 5,
            offset: Offset(-2, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.fill,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFF536B2F),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    isFront
                        ? 'বাংলার উভচর\nCover image missing'
                        : 'Back cover\nimage missing',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.14),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
