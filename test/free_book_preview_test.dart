import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earanyak/screens/free_book_preview_screen.dart';

void main() {
  group('FreeBookPreviewScreen Widget Tests', () {
    testWidgets('Displays friendly empty state message when pageUrls is empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FreeBookPreviewScreen(
            title: 'Sample Book',
            pageUrls: [],
          ),
        ),
      );

      expect(find.text('Sample Book (Preview)'), findsOneWidget);
      expect(find.textContaining('No preview pages available'), findsOneWidget);
      expect(find.byIcon(Icons.menu_book), findsOneWidget);
    });

    testWidgets('Displays page counter badge when pageUrls contains pages', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FreeBookPreviewScreen(
            title: 'Wildlife Guide',
            pageUrls: [
              'https://example.com/page1.jpg',
              'https://example.com/page2.jpg',
            ],
          ),
        ),
      );

      expect(find.text('Wildlife Guide (Preview)'), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);
    });
  });
}
