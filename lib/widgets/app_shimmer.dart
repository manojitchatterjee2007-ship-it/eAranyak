import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// The three themed skeleton styles required across the app.
enum ShimmerSurface { news, wildlifeDashboard, dailyWildlife }

/// Shimmer loading placeholders for the three surfaces that fetch remote images.
///
/// Each variant keeps its final dimensions and aspect ratio so the layout never
/// jumps when the real content arrives, stops animating on success or failure,
/// and honours the platform reduced-motion preference.
class AppShimmer extends StatelessWidget {
  final ShimmerSurface surface;

  /// Explicit box to preserve. When omitted the layout itself supplies bounds.
  final double? width;
  final double? height;

  const AppShimmer({
    super.key,
    required this.surface,
    this.width,
    this.height,
  });

  /// News cards: cool slate/charcoal editorial skeleton.
  const AppShimmer.news({super.key, this.width, this.height})
      : surface = ShimmerSurface.news;

  /// Wildlife dashboard: subtle forest-green natural-history skeleton.
  const AppShimmer.wildlifeDashboard({super.key, this.width, this.height})
      : surface = ShimmerSurface.wildlifeDashboard;

  /// Daily Wildlife: forest-green rhomboid image block plus text skeletons.
  const AppShimmer.dailyWildlife({super.key, this.width, this.height})
      : surface = ShimmerSurface.dailyWildlife;

  /// True when the platform asked for reduced motion. The shimmer is replaced by
  /// a static themed block so nothing animates.
  static bool _reducedMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  Widget build(BuildContext context) {
    final child = _buildContent();

    if (_reducedMotion(context)) {
      // Static themed fallback: no ticker, no shader.
      return ColoredBox(color: _baseColor, child: child);
    }

    return Shimmer.fromColors(
      baseColor: _baseColor,
      highlightColor: _highlightColor,
      period: const Duration(milliseconds: 1500),
      direction: ShimmerDirection.ltr,
      child: child,
    );
  }

  Color get _baseColor {
    switch (surface) {
      case ShimmerSurface.news:
        return const Color(0xFF2A2F36); // cool slate
      case ShimmerSurface.wildlifeDashboard:
        return const Color(0xFF16241A); // deep forest green
      case ShimmerSurface.dailyWildlife:
        return const Color(0xFF172A1D); // forest green
    }
  }

  Color get _highlightColor {
    switch (surface) {
      case ShimmerSurface.news:
        return const Color(0xFF4A525D); // lighter slate band
      case ShimmerSurface.wildlifeDashboard:
        return const Color(0xFF274A2C);
      case ShimmerSurface.dailyWildlife:
        return const Color(0xFF2C5233);
    }
  }

  Widget _buildContent() {
    switch (surface) {
      case ShimmerSurface.news:
        return _buildNewsSkeleton();
      case ShimmerSurface.wildlifeDashboard:
        return _buildWildlifeDashboardSkeleton();
      case ShimmerSurface.dailyWildlife:
        return _buildDailyWildlifeSkeleton();
    }
  }

  Widget _bar(double h, {double? w}) => Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
        ),
      );


  /// Editorial slate skeleton: image block plus stacked text rules.
  Widget _buildNewsSkeleton() {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _bar(11, w: 64),
            const SizedBox(height: 8),
            _bar(13),
            const SizedBox(height: 6),
            _bar(13, w: 190),
            const SizedBox(height: 8),
            _bar(9, w: 140),
          ],
        ),
      ),
    );
  }

  /// Forest-green natural-history skeleton: round thumbnail plus text rules.
  Widget _buildWildlifeDashboardSkeleton() {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(12, w: 96),
                  const SizedBox(height: 8),
                  _bar(10, w: 150),
                  const SizedBox(height: 8),
                  _bar(8, w: 72),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Forest-green rhomboid image placeholder with simple text skeletons.
  ///
  /// The parallelogram uses a [CustomClipper] mirroring the real Daily Wildlife
  /// card shape so the reserved space matches exactly.
  Widget _buildDailyWildlifeSkeleton() {
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: ClipPath(
                clipper: const _RhomboidSkeletonClipper(),
                child: const SizedBox.expand(
                  child: ColoredBox(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _bar(13, w: 170),
            const SizedBox(height: 7),
            _bar(10, w: 120),
            const SizedBox(height: 7),
            _bar(9, w: 90),
          ],
        ),
      ),
    );
  }
}

/// Slanted parallelogram with parallel top/bottom edges, matching the card.
class _RhomboidSkeletonClipper extends CustomClipper<Path> {
  const _RhomboidSkeletonClipper();

  @override
  Path getClip(Size size) {
    const slantFraction = 0.14;
    final slant = size.width * slantFraction;
    return Path()
      ..moveTo(slant, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - slant, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

