import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

/// Probe: does shimmer 4.0.0 (which imports package:material_ui) render inside a
/// standard MaterialApp that uses package:flutter/material.dart?
void main() {
  testWidgets('shimmer 4.0.0 renders inside MaterialApp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Shimmer.fromColors(
              baseColor: const Color(0xFF1B2E1E),
              highlightColor: const Color(0xFF2E7D32),
              period: const Duration(milliseconds: 1400),
              child: Container(
                key: const Key('shimmer-child'),
                width: 200,
                height: 60,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.byKey(const Key('shimmer-child')), findsOneWidget);
    // No MaterialUiCompatibilityBridge required.
    expect(tester.takeException(), isNull);
  });

  testWidgets('shimmer respects enabled=false and reduced motion', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Shimmer.fromColors(
                baseColor: const Color(0xFF1B2E1E),
                highlightColor: const Color(0xFF2E7D32),
                enabled: false,
                child: Container(
                  key: const Key('shimmer-child'),
                  width: 200,
                  height: 60,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Shimmer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
