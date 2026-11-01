import 'package:earanyak/widgets/magazine_flipbook_layout_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('waits for usable layout before building the flipbook',
      (tester) async {
    var buildCount = 0;
    final gate = MagazineFlipbookLayoutGate(
      builder: (context, constraints) {
        buildCount++;
        return const ColoredBox(color: Colors.white, child: Text('pages'));
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Center(child: SizedBox(width: 0, height: 0, child: gate)),
    ));
    expect(buildCount, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(width: 300, height: 500, child: gate),
    ));
    expect(buildCount, 1);
    expect(find.text('pages'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
