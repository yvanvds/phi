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
    required ValueChanged<int> onBarsChanged,
    ValueChanged<int>? onBeatsPerBarChanged,
    ValueChanged<bool>? onAutoExtendChanged,
    ClipTransportControls? transport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
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
}
