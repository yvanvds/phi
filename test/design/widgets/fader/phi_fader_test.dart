import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';

void main() {
  group('PhiFader', () {
    testWidgets('renders readout and label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhiFader(
              value: 0.5,
              onChanged: (_) {},
              readout: '0.50',
              label: 'master',
            ),
          ),
        ),
      );

      expect(find.text('0.50'), findsOneWidget);
      expect(find.text('master'), findsOneWidget);
    });

    testWidgets('tap on lower track emits a small value', (tester) async {
      double? captured;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PhiFader(
                value: 0.0,
                onChanged: (v) => captured = v,
                height: 100,
              ),
            ),
          ),
        ),
      );

      final fader = find.byType(PhiFader);
      final rect = tester.getRect(fader);
      // Tap near the bottom of the track → value should be close to 0.
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 5));
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!, lessThan(0.1));
    });

    testWidgets('drag upward emits an increasing value', (tester) async {
      final emitted = <double>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PhiFader(value: 0.0, onChanged: emitted.add, height: 100),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(PhiFader));
      final start = Offset(rect.center.dx, rect.bottom - 5);
      final end = Offset(rect.center.dx, rect.top + 5);

      final g = await tester.startGesture(start);
      await g.moveTo(end);
      await g.up();
      await tester.pump();

      expect(emitted, isNotEmpty);
      expect(emitted.last, greaterThan(0.8));
    });
  });
}
