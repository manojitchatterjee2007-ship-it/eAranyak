import 'package:earanyak/screens/citizen_science_screen.dart';
import 'package:earanyak/screens/coming_soon_screen.dart';
import 'package:earanyak/screens/kishore_earanyak_screen.dart';
import 'package:earanyak/screens/nature_games_screen.dart';
import 'package:earanyak/screens/user_bookshelf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.dummy',
      );
    } catch (_) {}
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: KishoreEaranyakScreen(),
      ),
    );

    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('KishoreEaranyakScreen renders grid menu cards with labels',
      (tester) async {
    await pumpScreen(tester);

    // Verify header and section titles
    expect(find.text('কিশোর আরণ্যক'), findsOneWidget);
    expect(find.text('অন্বেষণ এবং শেখা'), findsOneWidget);

    // Verify all 6 grid menu card items
    expect(find.text("(Today's Wildlife)"), findsOneWidget);
    expect(find.text('(Explore Species)'), findsOneWidget);
    expect(find.text('(Quiz)'), findsOneWidget);
    expect(find.text('(Nature Facts)'), findsOneWidget);
    expect(find.text('(My Collection)'), findsOneWidget);
    expect(find.text('(Achievements)'), findsOneWidget);
  });

  testWidgets('Explore Species card navigates to CitizenScienceScreen',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('(Explore Species)'));
    await tester.pumpAndSettle();

    expect(find.byType(CitizenScienceScreen), findsOneWidget);
  });

  testWidgets('Quiz card navigates to WildlifeQuizGame', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('(Quiz)'));
    await tester.pumpAndSettle();

    expect(find.byType(WildlifeQuizGame), findsOneWidget);
  });

  testWidgets('Nature Facts card navigates to ComingSoonScreen',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('(Nature Facts)'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.text('Nature Facts'), findsWidgets);
  });

  testWidgets('My Collection card navigates to UserBookshelfScreen',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('(My Collection)'));
    await tester.pumpAndSettle();

    expect(find.byType(UserBookshelfScreen), findsOneWidget);
  });
}
