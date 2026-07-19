import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_midi_transport.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end concurrent playback through the real workstation (issue #187).
///
/// The single-clip toolbar transport still drives the edited (boot) clip
/// through the real `session → shell → EngineMidiController` path; on top of it
/// a second clip is opened and played on the live controller — the seam the
/// library panel (a later issue) will drive. This exercises the *real* engine
/// bridge: two clip sessions on two independent domain clocks, pause freezing
/// one while the other runs on, resume without a restart, loop-off pushing a
/// one-shot, and stop-all halting everything — with a [FakeMidiGateway]
/// recording the per-session transports in place of the native MIDI-out.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  EntityAddress clip(String name) =>
      EntityAddress(kind: 'clip', segments: [name]);

  FakeMidiTransport onClock(FakeMidiGateway gateway, String clockName) =>
      gateway.transports.firstWhere((t) => t.clockName == clockName);

  testWidgets('midi: two clips play concurrently; pause/resume/stop-all + loop', (
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

    // Open the MIDI surface; nothing has played yet.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(midiGateway.transports, isEmpty);

    // 1) Start the edited (boot) clip through the real toolbar → shell path.
    session.play();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(midiGateway.transports, hasLength(1));
    const bootClock = 'phi.midi.default';
    expect(onClock(midiGateway, bootClock).isPlaying, isTrue);

    // 2) Open a second clip on the live controller and play it *concurrently*
    //    — the library-selection seam the panel will drive. Loop is off, so it
    //    is a one-shot; the boot clip keeps looping.
    final second = clip('phrase_b');
    engine.midi.openSession(
      second,
      ClipDocument(
        source: MidiClip(
          bars: 2,
          notes: const [
            MidiNote(pitch: 67, start: 0, duration: 1, velocity: 1),
          ],
        ),
        loop: false,
      ),
    );
    expect(engine.midi.playSession(second), isTrue);
    await tester.pump(const Duration(milliseconds: 40));

    // Two sessions run at once, each on its own domain clock.
    expect(midiGateway.transports, hasLength(2));
    const secondClock = 'phi.midi.clip.phrase_b';
    expect(onClock(midiGateway, bootClock).isPlaying, isTrue);
    expect(onClock(midiGateway, secondClock).isPlaying, isTrue);

    // Loop wiring: the boot clip loops its declared length; the second is a
    // one-shot (loopBeats <= 0).
    expect(onClock(midiGateway, bootClock).loopBeats, greaterThan(0));
    expect(onClock(midiGateway, secondClock).loopBeats, lessThanOrEqualTo(0));

    // 3) Pause the second clip: its clock freezes (tempo 0) while the boot clip
    //    keeps running — concurrent independence.
    expect(engine.midi.pauseSession(second), isTrue);
    await tester.pump(const Duration(milliseconds: 40));
    expect(engine.midi.sessionFor(second)!.isPaused, isTrue);
    expect(onClock(midiGateway, secondClock).tempo, 0);
    // The boot clip keeps running while the second is paused — independent
    // per-clock sessions.
    expect(onClock(midiGateway, bootClock).isPlaying, isTrue);

    // 4) Resume: playSession resumes the paused clip on the *same* transport
    //    (no second one minted for it) with its tempo restored.
    expect(engine.midi.playSession(second), isTrue);
    await tester.pump(const Duration(milliseconds: 40));
    expect(engine.midi.sessionFor(second)!.isPlaying, isTrue);
    expect(midiGateway.transports, hasLength(2)); // no restart-and-remint
    expect(onClock(midiGateway, secondClock).tempo, greaterThan(0));

    // 5) Stop-all halts every session (the panel header's stop-all).
    engine.midi.stopAll();
    await tester.pump(const Duration(milliseconds: 40));
    expect(onClock(midiGateway, bootClock).isPlaying, isFalse);
    expect(onClock(midiGateway, secondClock).isPlaying, isFalse);

    session.dispose();
    await engine.dispose();
  });
}
