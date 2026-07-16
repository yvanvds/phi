import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end push contract through the real workstation (issue #101).
///
/// Playback dispatch now belongs to the engine clip transport: on play the
/// player flattens the interpreted clip and *pushes* it (not tick-by-tick
/// `noteOn`s from the UI isolate); an edit while playing re-evaluates once in
/// Dart and re-pushes, so the engine swaps its event buffer at the next block.
/// This drives that whole path through real navigation and the real
/// session → shell → player wiring, with a [FakeMidiGateway] recording the
/// pushes in place of the native MIDI-out.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: play pushes the clip; an edit re-pushes it', (
    tester,
  ) async {
    final midiGateway = FakeMidiGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Open the MIDI surface; nothing has been pushed yet.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(midiGateway.transport, isNull);

    // Start the transport through the real session → shell → player path. Use
    // pump, not pumpAndSettle — the looping playhead timer never settles.
    session.play();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    // The whole interpreted clip was pushed once, and the transport is playing
    // — the engine owns the note timing from here.
    final transport = midiGateway.transport;
    expect(transport, isNotNull);
    expect(transport!.isPlaying, isTrue);
    expect(transport.events, isNotEmpty);
    expect(transport.loopBeats, greaterThan(0));
    final pushesAfterPlay = transport.pushCount;
    expect(pushesAfterPlay, 1);
    final eventsAfterPlay = transport.events.length;

    // Author a fresh note through the *same* editor the surface uses, while
    // playing. The memoised output changes instance, the player detects it on
    // the next tick and re-pushes the (transformed) clip — one more note flows
    // through the active chain — so the edit is heard without a restart.
    engine.midi.editor.addNote(
      const MidiNote(pitch: 74, start: 0.75, duration: 0.25, velocity: 1.0),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(transport.pushCount, greaterThan(pushesAfterPlay));
    expect(
      transport.events.length,
      eventsAfterPlay + 1,
      reason: 'the live edit was re-pushed to the engine transport',
    );

    // Stopping halts the transport.
    session.stop();
    await tester.pump(const Duration(milliseconds: 20));
    expect(transport.isPlaying, isFalse);

    session.dispose();
    await engine.dispose();
  });
}
