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
    // Issue #460: a fader shorter than its 24 px thumb — a patcher slider node
    // squeezed into a one-line box — inverted the thumb's `clamp` range and
    // threw on every build.
    for (final height in [0.0, 1.0, 12.0, 23.9, 24.0]) {
      for (final value in [0.0, 0.5, 1.0]) {
        testWidgets(
          'renders at height $height (value $value) without throwing',
          (tester) async {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Center(
                    child: PhiFader(
                      value: value,
                      onChanged: (_) {},
                      height: height,
                    ),
                  ),
                ),
              ),
            );

            expect(tester.takeException(), isNull);
            expect(tester.getSize(find.byType(PhiFader)).height, height);
          },
        );
      }
    }

    testWidgets('a below-thumb fader still answers a tap with a valid value', (
      tester,
    ) async {
      double? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PhiFader(
                value: 0.5,
                onChanged: (v) => captured = v,
                height: 16,
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(PhiFader));
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(captured, isNotNull);
      expect(captured!, inInclusiveRange(0.0, 1.0));
    });

    testWidgets('a zero-height fader never emits NaN', (tester) async {
      final emitted = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 40,
                child: PhiFader(value: 0.3, onChanged: emitted.add, height: 0),
              ),
            ),
          ),
        ),
      );

      final fader = tester.widget<PhiFader>(find.byType(PhiFader));
      // Nothing to hit-test on a zero-height track, so drive the gesture
      // handler the way a tap at its origin would.
      final detector = tester.widget<GestureDetector>(
        find.descendant(
          of: find.byType(PhiFader),
          matching: find.byType(GestureDetector),
        ),
      );
      detector.onTapDown!(TapDownDetails(localPosition: Offset.zero));
      expect(emitted.single, fader.value);
    });
  });
}
