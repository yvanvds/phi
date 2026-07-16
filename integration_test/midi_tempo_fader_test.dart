import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the tempo-source seam's first gesture (issue #104),
/// through the real workstation.
///
/// Tempo is *played, not set*: a domain's tempo is a base rate bent by a stack
/// of control-rate sources summed in Dart. The first source is a hand fader
/// riding the played domain's tempo. This drives the full session → shell →
/// player path — playing the default clip, then bending the player's
/// [tempoFader] — and asserts the transport clock ramps live while the pushed
/// note list never moves, because tempo lives in the clock, not the data
/// (`docs/timing-architecture.md` §3). The fader has no chrome yet (it graduates
/// into the toolbar with the wider time-domain UI), so it is exercised through
/// the same code-drivable seam a widget will bind to — the pattern the scatter /
/// grab / effect-volume performer actions already use.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('midi: the tempo fader bends the clock, not the notes', (
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

    // Play through the real session → shell → player path. Use pump, not
    // pumpAndSettle — the looping playhead timer never settles.
    session.play();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final transport = midiGateway.transport;
    expect(transport, isNotNull);
    expect(transport!.isPlaying, isTrue);

    // Whatever the base tempo is (the default chain subscribes to drum @ 124),
    // the fader bends *on top of it* without moving the pushed beats.
    final baseTempo = transport.tempo;
    final startsBefore = transport.events
        .map((e) => e.startBeat)
        .toList(growable: false);
    final pushesBefore = transport.pushCount;
    expect(startsBefore, isNotEmpty);

    // Pull the fader up: +0.5 of the ±40 BPM span → +20 BPM, live.
    engine.midi.tempoFader.position = 0.5;
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      transport.tempo,
      baseTempo + 20,
      reason: 'the fader bends the played tempo up',
    );

    // Pull it below centre: -0.25 → -10 BPM off the base.
    engine.midi.tempoFader.position = -0.25;
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      transport.tempo,
      baseTempo - 10,
      reason: 'the fader bends the played tempo down',
    );

    // The whole point of played tempo: the note list was never re-pushed and no
    // beat moved, so a live bend never smuggles rescheduling back in.
    expect(transport.pushCount, pushesBefore);
    expect(
      transport.events.map((e) => e.startBeat).toList(growable: false),
      startsBefore,
    );

    session.stop();
    await tester.pump(const Duration(milliseconds: 20));
    expect(transport.isPlaying, isFalse);

    session.dispose();
    await engine.dispose();
  });
}
