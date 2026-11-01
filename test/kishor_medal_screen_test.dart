import 'package:earanyak/screens/kishor_medal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    // The screen lays its content out in a ListView; use a phone-like tall
    // surface so the photo-source and export rows are inside the viewport.
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: KishorMedalScreen(level: 7),
      ),
    );
  }

  testWidgets('KishorMedalScreen renders its controls and medal preview',
      (tester) async {
    await pumpScreen(tester);

    // Title carries the server-supplied level.
    expect(find.textContaining('Level 7'), findsWidgets);

    // Photo source controls are present.
    expect(find.text('ক্যামেরা'), findsOneWidget);
    expect(find.text('গ্যালারি'), findsOneWidget);

    // Export actions are present.
    expect(find.textContaining('Save'), findsOneWidget);
    expect(find.textContaining('Share'), findsOneWidget);

    // The medal renders in a background isolate (real async work), so real time
    // must flow via runAsync; pump() alone only advances fake clock. An
    // indeterminate progress indicator also prevents pumpAndSettle.
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if (tester.widgetList(find.byType(Image)).isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });

    // The medal must render to a real image preview (no exception thrown).
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('KishorMedalScreen exposes the background toggle', (tester) async {
    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    final toggle = find.byType(SwitchListTile);
    expect(toggle, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(toggle).value,
      isTrue,
      reason: 'background composition should default to on (share-ready)',
    );
  });
}
