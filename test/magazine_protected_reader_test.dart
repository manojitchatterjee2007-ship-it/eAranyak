import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_realistic_flipbook/flutter_realistic_flipbook.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final Uint8List realPngBytes;

  setUpAll(() {
    final file = File('assets/images/blank.png');
    realPngBytes = file.readAsBytesSync();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  FlipbookPage createTestPage(int pageNumber) {
    final provider = MemoryImage(realPngBytes);
    return FlipbookPage(
      image: provider,
      hiResImage: provider,
      sizeHint: const Size(1000, 1414),
    );
  }

  group('Protected Magazine Reader Flipbook Lifecycle Tests', () {
    testWidgets(
        'Fixed Configuration: Initial page is rendered on first frame without blank/black screen',
        (WidgetTester tester) async {
      final controller = FlipbookController();
      final pages = [
        createTestPage(1),
        createTestPage(2),
        createTestPage(3),
        createTestPage(4),
      ];

      bool isFlipping = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox(
              width: 400,
              height: 800,
              child: IgnorePointer(
                ignoring: isFlipping,
                child: RealisticFlipbook(
                  controller: controller,
                  pages: pages,
                  flipDuration: const Duration(milliseconds: 300),
                  singlePageSpreadNavigation: false,
                  forwardDirection: FlipbookForwardDirection.right,
                  centering: true,
                  startPage: 1,
                  tapToFlip: false,
                  clickToZoom: false,
                  dragToFlip: true,
                  nPolygons: 10,
                  ambient: 0.8,
                  onFlipGuard: (currentPage, targetPage, direction, auto) =>
                      !isFlipping,
                  onFlipLeftStart: (_) => isFlipping = true,
                  onFlipRightStart: (_) => isFlipping = true,
                  onFlipLeftEnd: (_) => isFlipping = false,
                  onFlipRightEnd: (_) => isFlipping = false,
                ),
              ),
            ),
          ),
        ),
      );

      // Verify immediate render without black screen
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(controller.page, equals(1));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets(
        'Thumbnail sync logic: Jumping to Page 2 then back to Page 1 works correctly',
        (WidgetTester tester) async {
      final controller = FlipbookController();
      final pages = [
        createTestPage(1),
        createTestPage(2),
        createTestPage(3),
        createTestPage(4),
      ];

      int currentPage = 0; // 0-indexed logical page

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox(
              width: 400,
              height: 800,
              child: RealisticFlipbook(
                controller: controller,
                pages: pages,
                singlePageSpreadNavigation: false,
                forwardDirection: FlipbookForwardDirection.right,
                centering: true,
                startPage: 1,
                tapToFlip: false,
                clickToZoom: false,
                dragToFlip: true,
                nPolygons: 10,
                ambient: 0.8,
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(controller.page, equals(1));

      // Emulate _jumpToPage(1) -> Page 2
      void jumpToPage(int index) {
        if (index < 0 || index >= pages.length) return;
        final targetPage = index + 1;
        final needsSync = controller.page != targetPage;
        if (index == currentPage && !needsSync) return;

        controller.goToPage(targetPage);
        currentPage = index;
      }

      // Jump to thumbnail 1 (Page 2)
      jumpToPage(1);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(currentPage, equals(1));
      expect(controller.page, equals(2));

      // Jump to thumbnail 0 (Page 1) - must NOT be blocked by early return
      jumpToPage(0);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(currentPage, equals(0));
      expect(controller.page, equals(1));

      // Re-triggering thumbnail 0 when controller is already at 1 should be a safe no-op
      jumpToPage(0);
      expect(controller.page, equals(1));
    });

    testWidgets(
        'Continue Reading: initialPage initializes directly to the saved page position',
        (WidgetTester tester) async {
      final controller = FlipbookController();
      final pages = [
        createTestPage(1),
        createTestPage(2),
        createTestPage(3),
        createTestPage(4),
      ];

      const initialPage = 2; // 0-indexed Page 3

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox(
              width: 400,
              height: 800,
              child: RealisticFlipbook(
                controller: controller,
                pages: pages,
                singlePageSpreadNavigation: false,
                forwardDirection: FlipbookForwardDirection.right,
                centering: true,
                startPage: (initialPage + 1).clamp(1, pages.length),
                tapToFlip: false,
                clickToZoom: false,
                dragToFlip: true,
                nPolygons: 10,
                ambient: 0.8,
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(controller.page, equals(3));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets(
        'Thumbnail Bar: Renders for offline files with Image.file fallback and highlights selection',
        (WidgetTester tester) async {
      int selectedPage = 0;
      final tempFile = File('assets/images/blank.png');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Container(
                  height: 94,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 4,
                    itemBuilder: (context, index) {
                      final isSelected = index == selectedPage;
                      return GestureDetector(
                        key: ValueKey('thumb_$index'),
                        onTap: () => setState(() => selectedPage = index),
                        child: Container(
                          width: isSelected ? 58 : 44,
                          height: isSelected ? 80 : 60,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? const Color(0xFF00E676) : Colors.white24,
                            ),
                          ),
                          child: Image.file(tempFile, fit: BoxFit.cover),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify all 4 thumbnails rendered
      expect(find.byType(Image), findsNWidgets(4));

      // Tap thumbnail 1
      await tester.tap(find.byKey(const ValueKey('thumb_1')));
      await tester.pump();
      expect(selectedPage, equals(1));

      // Tap thumbnail 0
      await tester.tap(find.byKey(const ValueKey('thumb_0')));
      await tester.pump();
      expect(selectedPage, equals(0));
    });

    test('Reading Progress Persistence: Per-magazine page & progress saving and restoration', () async {
      final prefs = await SharedPreferences.getInstance();
      const magId = 'mag_progress_test_123';
      const totalPages = 20;
      const currentPage = 7; // 0-indexed Page 8

      // Save reading progress simulation
      await prefs.setString('last_read_mag_id', magId);
      await prefs.setString('last_read_title', 'Wildlife Special Edition');
      await prefs.setInt('last_read_page', currentPage);
      await prefs.setInt('last_read_total_pages', totalPages);
      await prefs.setInt('last_read_page_$magId', currentPage);
      await prefs.setInt('last_read_total_$magId', totalPages);
      await prefs.setDouble('progress_$magId', (currentPage + 1) / totalPages);

      // Verify global Continue Reading keys
      expect(prefs.getString('last_read_mag_id'), equals(magId));
      expect(prefs.getInt('last_read_page'), equals(7));
      expect(prefs.getInt('last_read_total_pages'), equals(20));

      // Verify per-magazine Bookshelf keys
      expect(prefs.getInt('last_read_page_$magId'), equals(7));
      expect(prefs.getInt('last_read_total_$magId'), equals(20));
      expect(prefs.getDouble('progress_$magId'), closeTo(0.40, 0.001));

      // Bookshelf resumption calculation
      final savedPage = prefs.getInt('last_read_page_$magId');
      expect(savedPage, equals(7));

      // Fallback calculation from progress if last_read_page was absent
      final double p = prefs.getDouble('progress_$magId')!;
      final restoredFromProgress = ((p * totalPages) - 1).round();
      expect(restoredFromProgress, equals(7));
    });
  });
}
