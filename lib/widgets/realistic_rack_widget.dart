import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps the final rack tail below the viewport while still allowing the
/// ListView to have a finite, normal scroll extent.
class _StopShortScrollPhysics extends ClampingScrollPhysics {
  final double stopShortBy;

  const _StopShortScrollPhysics({
    required this.stopShortBy,
    super.parent,
  });

  @override
  _StopShortScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _StopShortScrollPhysics(
      stopShortBy: stopShortBy,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyBoundaryConditions(
    ScrollMetrics position,
    double value,
  ) {
    final maxAllowed =
        math.max(0.0, position.maxScrollExtent - stopShortBy);

    if (value > maxAllowed) {
      return value - maxAllowed;
    }

    return super.applyBoundaryConditions(position, value);
  }
}

/// Responsive realistic magazine rack.
///
/// Rendering order for every shelf bay:
///   1. repeatable rack background/posts
///   2. magazine contact shadow
///   3. windswept magazine
///   4. foreground shelf lip
///
/// The widget owns the vertical ListView. Do not wrap it in another vertical
/// scroll view from Library or My Bookshelf.
class RealisticRackWidget extends StatelessWidget {
  final List<Widget> children;
  final bool isWooden;
  final double cardWidth;
  final double cardHeight;

  const RealisticRackWidget({
    super.key,
    required this.children,
    required this.isWooden,
    this.cardWidth = 170.0,
    this.cardHeight = 235.0,
  });

  static const double _topClearance = 12.0;

  // IMPORTANT:
  // There is deliberately NO row gap. Each shelf bay starts exactly where
  // the previous bay ends so the rack reads as one continuous ladder.
  static const double _rowGap = 0.0;

  // Horizontal distance between magazines on the same shelf.
  static const double _magazineGap = 18.0;

  // The lip is deliberately kept above the next bay's top edge.
  static const double _lipHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.80),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF00E676).withValues(alpha: 0.40),
            ),
          ),
          child: const Text(
            'কোনো ম্যাগাজিন পাওয়া যায়নি\n(No magazines available)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    final backgroundAsset = isWooden
        ? 'assets/images/wooden_rack_background_posts.png'
        : 'assets/images/metal_rack_background_posts.png';

    final foregroundAsset = isWooden
        ? 'assets/images/wooden_rack_foreground_lip.png'
        : 'assets/images/metal_rack_foreground_lip.png';

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1000.0;

        // Keep a substantial rack while leaving the forest clearly visible.
        final rackWidth = math.min(
          math.max(availableWidth * 0.62, 560.0),
          920.0,
        );

        // The current visual target is at least two magazines per shelf.
        // Use three only when they still remain comfortably readable.
        final itemsPerShelf =
            rackWidth >= 820.0 && cardWidth <= 170.0 ? 3 : 2;

        // The magazine area is deliberately inside the posts.
        final usableShelfWidth = rackWidth * 0.72;

        final aspectRatio = cardWidth > 0
            ? cardHeight / cardWidth
            : 235.0 / 170.0;

        final maximumCardWidth =
            (usableShelfWidth -
                    ((itemsPerShelf - 1) * _magazineGap)) /
                itemsPerShelf;

        final actualCardWidth = math.max(
          120.0,
          math.min(cardWidth, maximumCardWidth),
        );

        final actualCardHeight = actualCardWidth * aspectRatio;

        // The shelf lip begins immediately after the magazine's bottom.
        // No artificial space is inserted between bays.
        final shelfSurfaceY =
            _topClearance + actualCardHeight;

        final rowHeight = shelfSurfaceY + _lipHeight + _rowGap;

        // Always add continuation bays below the last populated bay.
        // If height is known, add enough empty bays to guarantee that the
        // rack's physical end cannot enter the viewport.
        final viewportHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 900.0;

        final populatedShelves =
            (children.length / itemsPerShelf).ceil();

        // Add enough continuation bays to keep the final visible rack section
        // extending beyond the viewport. The list remains finite, so scrolling
        // naturally stops; no decorative rack bottom is rendered by this widget.
        final continuationShelves =
            math.max(2, (viewportHeight / rowHeight).ceil());

        final shelfCount =
            populatedShelves + continuationShelves;

        return Center(
          child: SizedBox(
            width: rackWidth,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                overscroll: false,
              ),
              child: ListView.builder(
                padding: const EdgeInsets.only(
                  top: 4,
                  // No artificial bottom padding: custom physics stops the
                  // scroll before the finite rack tail reaches the viewport.
                  bottom: 0,
                ),
                physics: _StopShortScrollPhysics(
                  stopShortBy: rowHeight * 0.70,
                ),
                itemCount: shelfCount,
                itemBuilder: (context, shelfIndex) {
                  final start = shelfIndex * itemsPerShelf;

                  final shelfItems = start < children.length
                      ? children
                          .skip(start)
                          .take(itemsPerShelf)
                          .toList(growable: false)
                      : const <Widget>[];

                  return SizedBox(
                    width: rackWidth,
                    height: rowHeight,
                    child: _ShelfBay(
                      isWooden: isWooden,
                      backgroundAsset: backgroundAsset,
                      foregroundAsset: foregroundAsset,
                      children: shelfItems,
                      rackWidth: rackWidth,
                      cardWidth: actualCardWidth,
                      cardHeight: actualCardHeight,
                      itemsPerShelf: itemsPerShelf,
                      magazineGap: _magazineGap,
                      topClearance: _topClearance,
                      shelfSurfaceY: shelfSurfaceY,
                      lipHeight: _lipHeight,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShelfBay extends StatelessWidget {
  final bool isWooden;
  final String backgroundAsset;
  final String foregroundAsset;
  final List<Widget> children;
  final double rackWidth;
  final double cardWidth;
  final double cardHeight;
  final int itemsPerShelf;
  final double magazineGap;
  final double topClearance;
  final double shelfSurfaceY;
  final double lipHeight;

  const _ShelfBay({
    required this.isWooden,
    required this.backgroundAsset,
    required this.foregroundAsset,
    required this.children,
    required this.rackWidth,
    required this.cardWidth,
    required this.cardHeight,
    required this.itemsPerShelf,
    required this.magazineGap,
    required this.topClearance,
    required this.shelfSurfaceY,
    required this.lipHeight,
  });

  @override
  Widget build(BuildContext context) {
    final usableWidth = rackWidth * 0.72;
    final shelfLeft = (rackWidth - usableWidth) / 2;

    final totalCardsWidth =
        children.length * cardWidth +
        math.max(0, children.length - 1) * magazineGap;

    final cardsLeft =
        shelfLeft +
        math.max(0, (usableWidth - totalCardsWidth) / 2);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ================================================================
        // BACKGROUND / POSTS
        // ================================================================
        Positioned.fill(
          child: IgnorePointer(
            child: Image.asset(
              backgroundAsset,
              fit: BoxFit.fill,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),

        // ================================================================
        // MAGAZINES
        // ================================================================
        for (var i = 0; i < children.length; i++)
          Positioned(
            left: cardsLeft + i * (cardWidth + magazineGap),
            top: topClearance,
            width: cardWidth,
            height: cardHeight,
            child: _PhysicalMagazine(
              child: children[i],
              width: cardWidth,
              height: cardHeight,
            ),
          ),

        // ================================================================
        // FOREGROUND SHELF LIP
        //
        // It is rendered LAST so the lower edge of the magazine disappears
        // naturally behind the shelf lip.
        // ================================================================
        Positioned(
          left: 0,
          right: 0,
          top: shelfSurfaceY,
          height: lipHeight,
          child: IgnorePointer(
            child: Image.asset(
              foregroundAsset,
              fit: BoxFit.fill,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ],
    );
  }
}

/// A magazine with:
/// - physical page-block thickness
/// - realistic contact/cast shadow
/// - pronounced but controlled backward lean
/// - continuously moving wind wave
/// - moving highlight following the paper deformation
///
/// The wind animation is deliberately localized to the outer/right portion
/// of the cover. The binding edge stays stable so the magazine still reads as
/// a physical printed object resting on a shelf while its loose pages sweep
/// and curl in the wind.
class _PhysicalMagazine extends StatefulWidget {
  final Widget child;
  final double width;
  final double height;

  const _PhysicalMagazine({
    required this.child,
    required this.width,
    required this.height,
  });

  @override
  State<_PhysicalMagazine> createState() => _PhysicalMagazineState();
}

class _PhysicalMagazineState extends State<_PhysicalMagazine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _windController;

  @override
  void initState() {
    super.initState();

    _windController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _windController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _windController,
      child: widget.child,
      builder: (context, child) {
        final progress = _windController.value;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ------------------------------------------------------------
            // FLAT CONTACT SHADOW
            // ------------------------------------------------------------
            Positioned(
              left: 9,
              right: 9,
              bottom: -2,
              height: 14,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(
                      Radius.elliptical(100, 12),
                    ),
                    color: Colors.black.withValues(alpha: 0.25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 9,
                        spreadRadius: 0,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ------------------------------------------------------------
            // BACKWARD LEAN
            //
            // X rotation = leaning backward.
            // There is deliberately NO Z rotation, so the magazine does not
            // become diagonally tilted sideways.
            // ------------------------------------------------------------
            Positioned.fill(
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0021)
                  ..rotateX(-0.19),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ------------------------------------------------------
                    // PAGE-BLOCK THICKNESS
                    // ------------------------------------------------------
                    Positioned(
                      left: 1.2,
                      top: 1.0,
                      right: -5.0,
                      bottom: 1.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFEBE9),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.14),
                            width: 0.6,
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      left: 0.6,
                      top: 0.5,
                      right: -2.5,
                      bottom: 0.5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.16),
                            width: 0.55,
                          ),
                        ),
                      ),
                    ),

                    // ------------------------------------------------------
                    // FRONT COVER + WIND DEFORMATION
                    // ------------------------------------------------------
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.46),
                              blurRadius: 11,
                              spreadRadius: -1,
                              offset: const Offset(2, 6),
                            ),
                          ],
                        ),
                        child: ClipPath(
                          clipper: WindWaveClipper(progress: progress),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              child ?? const SizedBox.shrink(),

                              // ------------------------------------------------
                              // MOVING LIGHT / PAPER HIGHLIGHT
                              // ------------------------------------------------
                              IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment(
                                        -1.2 + progress * 2.4,
                                        -0.7,
                                      ),
                                      end: Alignment(
                                        -0.2 + progress * 2.4,
                                        0.7,
                                      ),
                                      colors: const [
                                        Colors.transparent,
                                        Color.fromRGBO(255, 255, 255, 0.0),
                                        Color.fromRGBO(255, 255, 255, 0.12),
                                        Color.fromRGBO(255, 255, 255, 0.0),
                                        Colors.transparent,
                                      ],
                                      stops: [
                                        0.0,
                                        0.34,
                                        0.52,
                                        0.68,
                                        1.0,
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // A narrow moving curl band makes the bent paper
                              // edge readable even when the cover artwork is dark.
                              Positioned(
                                left: widget.width * 0.70,
                                top: 0,
                                bottom: 0,
                                width: widget.width * 0.34,
                                child: IgnorePointer(
                                  child: ClipPath(
                                    clipper: WindCurlHighlightClipper(
                                      progress: progress,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Colors.transparent,
                                            Colors.white.withValues(alpha: 0.18),
                                            Colors.black.withValues(alpha: 0.15),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              Positioned(
                                right: -10 + (math.sin(progress * 2 * math.pi) * 10),
                                top: 0,
                                bottom: 0,
                                width: widget.width * 0.24,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          Colors.transparent,
                                          Colors.white.withValues(alpha: 0.16),
                                          Colors.black.withValues(alpha: 0.12),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Clips the moving highlight into a curved strip. This gives the eye a
/// concrete visual cue that the outer paper is bending rather than merely
/// changing its rectangular boundary.
class WindCurlHighlightClipper extends CustomClipper<Path> {
  final double progress;

  const WindCurlHighlightClipper({
    required this.progress,
  });

  @override
  Path getClip(Size size) {
    final t = progress * 2 * math.pi;

    final top = math.sin(t) * 8.0;
    final mid = math.sin(t + 1.4) * 15.0;
    final bottom = math.cos(t + 0.4) * 12.0;

    final path = Path()
      ..moveTo(size.width * 0.15, 0)
      ..cubicTo(
        size.width * 0.48,
        top,
        size.width * 0.68,
        mid,
        size.width,
        mid * 0.75,
      )
      ..lineTo(
        size.width,
        size.height + bottom * 0.5,
      )
      ..cubicTo(
        size.width * 0.70,
        size.height + bottom,
        size.width * 0.42,
        size.height + mid * 0.25,
        size.width * 0.12,
        size.height,
      )
      ..close();

    return path;
  }

  @override
  bool shouldReclip(covariant WindCurlHighlightClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}

/// Deforms the outer/right edge of the magazine with a stronger S-shaped
/// sweep. The left/binding edge remains stable while the outer page edge
/// lifts, curls and returns through an out-of-phase wave.
class WindWaveClipper extends CustomClipper<Path> {
  final double progress;

  const WindWaveClipper({
    required this.progress,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    final t = progress * 2 * math.pi;

    // The cover is fixed at the binding edge. The outer paper sweeps through
    // a pronounced curl so the movement is visible at normal card size.
    final topCurl = math.sin(t) * 13.0;
    final upperCurl = math.sin(t + 1.25) * 22.0;
    final middleCurl = math.sin(t + 2.65) * 18.0;
    final lowerCurl = math.cos(t + 0.55) * 20.0;
    final bottomCurl = math.cos(t + 0.15) * 13.0;

    path.moveTo(0, 0);

    // Stable binding/top-left area.
    path.lineTo(size.width * 0.32, 0);

    // Top edge rises into the first page curl.
    path.cubicTo(
      size.width * 0.52,
      topCurl * 0.18,
      size.width * 0.76,
      upperCurl * 0.46,
      size.width,
      topCurl,
    );

    // Strong S-wave along the loose outer page.
    path.cubicTo(
      size.width + upperCurl * 0.70,
      size.height * 0.16,
      size.width - middleCurl * 0.82,
      size.height * 0.38,
      size.width + middleCurl * 0.72,
      size.height * 0.57,
    );

    path.cubicTo(
      size.width - lowerCurl * 0.62,
      size.height * 0.72,
      size.width + lowerCurl * 0.70,
      size.height * 0.88,
      size.width + bottomCurl * 0.60,
      size.height + bottomCurl * 0.35,
    );

    // Bottom returns to the fixed binding edge.
    path.cubicTo(
      size.width * 0.70,
      size.height + bottomCurl * 0.12,
      size.width * 0.49,
      size.height,
      size.width * 0.32,
      size.height,
    );

    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(covariant WindWaveClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
