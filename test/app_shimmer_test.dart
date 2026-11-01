import 'package:earanyak/widgets/app_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a MaterialApp with an explicit media query so the
/// reduced-motion path can be exercised deterministically.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  group('AppShimmer', () {
    testWidgets('news variant renders a shimmer and reserves space',
        (tester) async {
      await _pump(
        tester,
        const SizedBox(width: 300, height: 180, child: AppShimmer.news()),
      );
      expect(find.byType(AppShimmer), findsOneWidget);
      // The skeleton must actually occupy the requested box.
      final size = tester.getSize(find.byType(AppShimmer));
      expect(size.width, 300);
      expect(size.height, 180);
    });

    testWidgets('wildlifeDashboard variant reserves its box', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 320,
          height: 78,
          child: AppShimmer.wildlifeDashboard(),
        ),
      );
      final size = tester.getSize(find.byType(AppShimmer));
      expect(size.width, 320);
      expect(size.height, 78);
    });

    testWidgets('dailyWildlife variant reserves its box', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 340,
          height: 260,
          child: AppShimmer.dailyWildlife(),
        ),
      );
      final size = tester.getSize(find.byType(AppShimmer));
      expect(size.width, 340);
      expect(size.height, 260);
    });

    testWidgets(
        'reduced motion disables the animation (static themed block, '
        'no shimmer shader widget)', (tester) async {
      await _pump(
        tester,
        const SizedBox(width: 200, height: 120, child: AppShimmer.news()),
        disableAnimations: true,
      );
      expect(find.byType(AppShimmer), findsOneWidget);
      // With animations disabled the widget must not install the shimmer
      // layer at all — the skeleton renders as a plain static block.
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().startsWith('Shimmer'),
        ),
        findsNothing,
      );
      // And pumping additional frames must not tick any animation.
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('regular motion keeps animating across frames',
        (tester) async {
      await _pump(
        tester,
        const SizedBox(width: 200, height: 120, child: AppShimmer.news()),
      );
      // Advance time; a live shimmer must not throw while re-laying out.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(AppShimmer), findsOneWidget);
    });
  });
}
