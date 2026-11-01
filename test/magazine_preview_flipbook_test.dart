import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_realistic_flipbook/flutter_realistic_flipbook.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final Uint8List realPngBytes;

  setUpAll(() {
    final file = File('assets/images/blank.png');
    realPngBytes = file.readAsBytesSync();
  });

  group('Magazine Preview Flipbook Lifecycle & Sequence Tests', () {
    FlipbookPage createTestImagePage(int pageNumber) {
      final provider = MemoryImage(realPngBytes);
      return FlipbookPage(
        image: provider,
        hiResImage: provider,
        sizeHint: const Size(1000, 1414),
      );
    }

    testWidgets(
        'Fixed Preview Configuration: Initial page is immediately rendered and visible without blank screen',
        (WidgetTester tester) async {
      final controller = FlipbookController();
      final pages = [
        createTestImagePage(1),
        createTestImagePage(2),
        createTestImagePage(3),
        createTestImagePage(4),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: RealisticFlipbook(
                controller: controller,
                pages: pages,
                singlePage: false,
                singlePageSpreadNavigation: false,
                centering: true,
                startPage: 1,
                forwardDirection: FlipbookForwardDirection.right,
                dragToFlip: true,
                tapToFlip: false,
                clickToZoom: false,
                nPolygons: 10,
                ambient: 0.8,
              ),
            ),
          ),
        ),
      );

      // Verify the first frame renders Page 1 immediately
      await tester.pump();
      expect(controller.page, equals(1));
    });

    testWidgets(
        'Monotonic Forward Navigation: Advances sequentially from page 1 to 4 without reversing',
        (WidgetTester tester) async {
      final controller = FlipbookController();
      final pages = [
        createTestImagePage(1),
        createTestImagePage(2),
        createTestImagePage(3),
        createTestImagePage(4),
      ];

      final recordedPages = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: RealisticFlipbook(
                controller: controller,
                pages: pages,
                singlePage: false,
                singlePageSpreadNavigation: false,
                centering: true,
                startPage: 1,
                flipDuration: const Duration(milliseconds: 100),
                forwardDirection: FlipbookForwardDirection.right,
                dragToFlip: true,
                tapToFlip: false,
                clickToZoom: false,
                nPolygons: 10,
                ambient: 0.8,
                onFlipRightEnd: (page) => recordedPages.add(controller.page),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(controller.page, equals(1));

      // Flip 1: Forward from Page 1 -> Page 2
      controller.flipRight();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.page, equals(2));

      // Flip 2: Forward from Page 2 -> Page 3 (must NOT reverse to Page 1)
      controller.flipRight();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.page, equals(3));
      expect(controller.page, isNot(equals(1)));

      // Flip 3: Forward from Page 3 -> Page 4
      controller.flipRight();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.page, equals(4));

      // Verify that after reaching Page 4, further forward flip cannot advance
      expect(controller.canFlipRight, isFalse);

      // Verify recorded page sequence is strictly monotonic
      expect(recordedPages, equals([2, 3, 4]));
    });

    testWidgets(
        'Boundary Condition: Download prompt threshold triggers at final preview page',
        (WidgetTester tester) async {
      final controller = FlipbookController();
      final pages = [
        createTestImagePage(1),
        createTestImagePage(2),
        createTestImagePage(3),
        createTestImagePage(4),
      ];

      bool showDownloadPrompt = false;

      void checkPageEnd() {
        final page = controller.page;
        final total = pages.length;
        final reachedEnd =
            page >= total || (page >= total - 1 && !controller.canFlipRight);
        showDownloadPrompt = reachedEnd;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: RealisticFlipbook(
                controller: controller,
                pages: pages,
                singlePage: false,
                singlePageSpreadNavigation: false,
                centering: true,
                startPage: 1,
                flipDuration: const Duration(milliseconds: 50),
                forwardDirection: FlipbookForwardDirection.right,
                onFlipRightEnd: (_) => checkPageEnd(),
                onFlipLeftEnd: (_) => checkPageEnd(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      checkPageEnd();
      expect(showDownloadPrompt, isFalse); // Page 1

      controller.flipRight();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(showDownloadPrompt, isFalse); // Page 2

      controller.flipRight();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(showDownloadPrompt, isFalse); // Page 3

      controller.flipRight();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(showDownloadPrompt, isTrue); // Page 4 (Final page reached)

      // Backward flip from Page 4 to Page 3 dismisses the prompt condition
      controller.flipLeft();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.page, equals(3));
      expect(showDownloadPrompt, isFalse);
    });
  });
}
