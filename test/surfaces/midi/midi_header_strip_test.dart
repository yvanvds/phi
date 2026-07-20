import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/surfaces/midi/midi_header_strip.dart';
import 'package:phi/surfaces/midi/snap_grid.dart';

void main() {
  group('MidiHeaderStrip', () {
    // Size the whole view so the header actually gets [width] to lay out in — a
    // `SizedBox` wider than the default 800px test surface would be clamped, and
    // the header must fill the pane to reproduce the docked-pane geometry.
    Future<void> pumpAtWidth(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MidiHeaderStrip(
                clipName: 'phrase_a',
                noteCount: 12,
                bars: 4,
                onImport: () {},
                onExport: () {},
                gridDivision: SnapGrid.off,
                onGridChanged: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    // The header's own horizontal scroll view (the snap picker is closed, so it
    // contributes no Scrollable of its own).
    ScrollableState headerScroll(WidgetTester tester) =>
        tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(MidiHeaderStrip),
            matching: find.byType(Scrollable),
          ),
        );

    testWidgets('scrolls instead of overflowing when the pane is narrow', (
      tester,
    ) async {
      await pumpAtWidth(tester, 320);

      // No `RenderFlex overflowed` was thrown in a pane narrower than the
      // header's content (issue #287).
      expect(tester.takeException(), isNull);

      // Every affordance still renders — nothing was dropped to make it fit.
      expect(find.textContaining('PHRASE_A'), findsOneWidget);
      expect(find.byKey(MidiHeaderStrip.snapPickerKey), findsOneWidget);
      expect(find.text('IMPORT'), findsOneWidget);
      expect(find.text('EXPORT'), findsOneWidget);
      expect(find.text('D DORIAN'), findsOneWidget);
      expect(find.text('DOMAIN · DRUM'), findsOneWidget);

      // It degraded by becoming horizontally scrollable rather than asserting.
      expect(headerScroll(tester).position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('fills the pane without scrolling when there is room', (
      tester,
    ) async {
      await pumpAtWidth(tester, 1800);

      expect(tester.takeException(), isNull);
      // Wide enough for everything: no scroll extent, so the trailing capsules
      // stay pinned to the right exactly as in the maximized layout.
      expect(headerScroll(tester).position.maxScrollExtent, equals(0));
    });
  });
}
