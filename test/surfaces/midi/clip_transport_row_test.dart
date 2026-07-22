import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/transport_button/transport_button.dart';
import 'package:phi/surfaces/midi/clip_transport_row.dart';

/// The header transport + length row in isolation (issue #190): its length
/// fields, auto-extend toggle, and transport buttons drive their callbacks; the
/// transport cluster is hidden when no session is wired.
void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    int bars = 4,
    int beatsPerBar = 4,
    bool autoExtend = true,
    double width = 900,
    required ValueChanged<int> onBarsChanged,
    ValueChanged<int>? onBeatsPerBarChanged,
    ValueChanged<bool>? onAutoExtendChanged,
    ClipTransportControls? transport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: ClipTransportRow(
              bars: bars,
              beatsPerBar: beatsPerBar,
              autoExtend: autoExtend,
              onBarsChanged: onBarsChanged,
              onBeatsPerBarChanged: onBeatsPerBarChanged ?? (_) {},
              onAutoExtendChanged: onAutoExtendChanged ?? (_) {},
              transport: transport,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('editing the bars field commits the parsed value', (
    tester,
  ) async {
    int? committed;
    await pumpRow(tester, onBarsChanged: (v) => committed = v);

    await tester.enterText(find.byKey(ClipTransportRow.barsFieldKey), '8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(committed, 8);
  });

  testWidgets('editing the beats-per-bar field commits the parsed value', (
    tester,
  ) async {
    int? committed;
    await pumpRow(
      tester,
      onBarsChanged: (_) {},
      onBeatsPerBarChanged: (v) => committed = v,
    );

    await tester.enterText(
      find.byKey(ClipTransportRow.beatsPerBarFieldKey),
      '3',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(committed, 3);
  });

  testWidgets('a blank / invalid length entry reverts, commits nothing', (
    tester,
  ) async {
    var calls = 0;
    await pumpRow(tester, onBarsChanged: (_) => calls++);

    await tester.enterText(find.byKey(ClipTransportRow.barsFieldKey), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('the auto-extend toggle flips its value', (tester) async {
    bool? toggled;
    await pumpRow(
      tester,
      onBarsChanged: (_) {},
      autoExtend: true,
      onAutoExtendChanged: (v) => toggled = v,
    );

    await tester.tap(find.byKey(ClipTransportRow.autoExtendKey));
    await tester.pump();

    expect(toggled, isFalse);
  });

  testWidgets('transport buttons are hidden without a session', (tester) async {
    await pumpRow(tester, onBarsChanged: (_) {});

    expect(find.byKey(ClipTransportRow.playKey), findsNothing);
    expect(find.byKey(ClipTransportRow.pauseKey), findsNothing);
    expect(find.byKey(ClipTransportRow.stopKey), findsNothing);
    expect(find.byKey(ClipTransportRow.loopKey), findsNothing);
    expect(find.byType(TransportButton), findsNothing);
  });

  testWidgets('transport buttons drive their callbacks when wired', (
    tester,
  ) async {
    final log = <String>[];
    await pumpRow(
      tester,
      onBarsChanged: (_) {},
      transport: ClipTransportControls(
        isPlaying: false,
        isPaused: false,
        loop: true,
        onPlay: () => log.add('play'),
        onPause: () => log.add('pause'),
        onStop: () => log.add('stop'),
        onToggleLoop: () => log.add('loop'),
      ),
    );

    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.tap(find.byKey(ClipTransportRow.pauseKey));
    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.tap(find.byKey(ClipTransportRow.loopKey));
    await tester.pump();

    expect(log, ['play', 'pause', 'stop', 'loop']);
  });

  testWidgets(
    'degrades to a horizontal scroll in a narrow pane without overflowing '
    '(issue #299)',
    (tester) async {
      // A pane far narrower than the row's ~475px intrinsic width, with the
      // transport cluster wired so the full content is present. Without the
      // scroll fallback this asserts a `RenderFlex overflowed`.
      await pumpRow(
        tester,
        width: 412,
        onBarsChanged: (_) {},
        transport: ClipTransportControls(
          isPlaying: false,
          isPaused: false,
          loop: false,
          onPlay: () {},
          onPause: () {},
          onStop: () {},
          onToggleLoop: () {},
        ),
      );

      // No RenderFlex overflow was thrown laying out the narrow row…
      expect(tester.takeException(), isNull);

      // …because it degraded to a horizontal scroll view whose content is
      // wider than the pane (so it scrolls rather than clipping/asserting).
      // Scope through the outer SingleChildScrollView — the length TextFields
      // each carry their own inner Scrollable, so matching Scrollable directly
      // would be ambiguous.
      expect(scrollExtentOf(tester), greaterThan(0));

      // The transport buttons are still present — just reachable by scrolling.
      expect(find.byKey(ClipTransportRow.loopKey), findsOneWidget);
    },
  );

  testWidgets('fills a wide pane, pinning the transport cluster right', (
    tester,
  ) async {
    // At a comfortable width the row still fills its pane (the Spacer expands),
    // so the common maximized layout is unchanged and does not scroll.
    await pumpRow(
      tester,
      width: 900,
      onBarsChanged: (_) {},
      transport: ClipTransportControls(
        isPlaying: false,
        isPaused: false,
        loop: false,
        onPlay: () {},
        onPause: () {},
        onStop: () {},
        onToggleLoop: () {},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(scrollExtentOf(tester), 0);
  });
}

/// The max horizontal scroll extent of the transport row's outer scroll view.
/// Scopes through the [SingleChildScrollView] the row wraps its content in, so
/// the length fields' own inner [Scrollable]s don't make the match ambiguous;
/// `> 0` means the content is wider than the pane (it degraded to a scroll),
/// `== 0` means it filled the pane exactly (no overflow, common wide layout).
double scrollExtentOf(WidgetTester tester) {
  final outer = find.descendant(
    of: find.byType(ClipTransportRow),
    matching: find.byType(SingleChildScrollView),
  );
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: outer, matching: find.byType(Scrollable)).first,
  );
  return scrollable.position.maxScrollExtent;
}
