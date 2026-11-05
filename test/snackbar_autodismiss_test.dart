import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SnackBar with SnackBarAction and persist: false auto-dismisses after duration',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 4),
                      persist: false,
                      content: const Text('Download completed'),
                      action: SnackBarAction(
                        label: 'পড়ুন (Read)',
                        onPressed: () {},
                      ),
                    ),
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    // Tap the button to show the SnackBar
    await tester.tap(find.text('Show'));
    await tester.pump(); // Start animation
    await tester.pump(const Duration(milliseconds: 300)); // Finish entry animation

    expect(find.text('পড়ুন (Read)'), findsOneWidget);

    // Advance time past 4 seconds
    await tester.pump(const Duration(seconds: 4));
    // Run exit animation
    await tester.pump(const Duration(milliseconds: 350));

    // Must be completely dismissed!
    expect(find.text('পড়ুন (Read)'), findsNothing);
  });

  testWidgets('clearSnackBars immediately removes active action snackbar',
      (WidgetTester tester) async {
    late BuildContext scaffoldContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              scaffoldContext = context;
              return ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 4),
                      persist: false,
                      content: const Text('Download completed'),
                      action: SnackBarAction(
                        label: 'পড়ুন (Read)',
                        onPressed: () {},
                      ),
                    ),
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('পড়ুন (Read)'), findsOneWidget);

    // Clear snackbars (as done in initState / tab switch)
    ScaffoldMessenger.of(scaffoldContext).clearSnackBars();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('পড়ুন (Read)'), findsNothing);
  });
}
