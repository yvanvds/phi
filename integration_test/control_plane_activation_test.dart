import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/domain/voice/voice_channel_resolver.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/engine.dart';

import '../test/engine/test_doubles/fake_bus_tap.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the live-coding **control plane is activated in
/// production** (issue #334): the [ControlPlaneDispatcher] the *engine itself*
/// constructs in [PhiEngine.start] — no dispatcher is built in this test — taps
/// the engine's bus seam and routes each `phi.ctl.*` frame to its **real**
/// owning controller.
///
/// The tap is faked (its C API is a pending engine dependency, design
/// `docs/design/live-coding.md` §9), but every seam past it is the production
/// one: the same [FakeBusTap] the engine holds carries each publish through the
/// engine's own `phi.ctl` subscription into the dispatcher `start()` wired, and
/// out to the real state / var / domain-tempo / clip / voice ports. Each verb is
/// the exact frame the `phi` library publishes (proven byte-for-byte by its
/// Python suite).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the production-constructed dispatcher routes each verb to its '
      'real owning controller', (tester) async {
    final clipA = EntityAddress.parse('clip.phrase_a');

    final busTap = FakeBusTap();
    final midiGateway = FakeMidiGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      busTap: busTap,
    );
    // Boot the engine — this is where the dispatcher is constructed over the
    // real ports. Then open a seeded project so there is a real clip, state
    // graph, and domain to drive.
    engine.start();
    final registry = ProjectRegistry();
    seedDefaultProject(registry);
    engine.bindProject(registry);
    await tester.pumpAndSettle();

    // A defined runtime variable for the `var` leg, and an external voice so the
    // `voice` leg sounds through the observable MIDI-out (no racks in this
    // gateway-only setup).
    engine.runtimeVariables.define(
      name: 'section',
      values: ['a', 'b'],
      current: 'a',
    );
    engine.midi.voiceResolver = const VoiceChannelResolver(
      externalChannels: {'voice.bells': 1},
    );

    // Preconditions: live state is `intro`, nothing overridden, nothing sounding.
    expect(engine.stateMachine.activeStateAddress, introStateAddress);
    expect(engine.midi.domainTempoOverride('drum'), isNull);
    expect(engine.midi.sessionFor(clipA)?.isPlaying, isFalse);

    // ── state: `state.verse.fire()` → the trigger scheduler fires the live
    //    transition, so `verse` becomes live ──────────────────────────────────
    busTap.publish('phi.ctl.state.fire', const BusString('verse'));
    await tester.pumpAndSettle();
    expect(engine.stateMachine.activeStateAddress, verseStateAddress);

    // ── var: `var.section = "b"` → the runtime registry moves ────────────────
    busTap.publish('phi.ctl.var.section', const BusString('b'));
    await tester.pumpAndSettle();
    expect(engine.runtimeVariables.byName('section')!.current, 'b');

    // ── domain tempo: `domain.drum.tempo = 124` → a live domain override ──────
    busTap.publish('phi.ctl.domain.drum.tempo', const BusFloat(124));
    await tester.pumpAndSettle();
    expect(engine.midi.domainTempoOverride('drum'), 124);

    // ── clip: `clip.phrase_a.play()` → the session manager plays it ──────────
    busTap.publish('phi.ctl.clip.phrase_a.play', const BusInt(1));
    await tester.pumpAndSettle();
    expect(engine.midi.sessionFor(clipA)?.isPlaying, isTrue);

    // ── voice: `voice.bells.note(60)` → the racks audition path sounds it ────
    busTap.publish('phi.ctl.voice.bells.note', const BusFloatList([60, 100]));
    await tester.pumpAndSettle();
    expect(midiGateway.calls, contains('sendNoteOn:0:60:100'));

    // Nothing degraded anywhere along the walk.
    expect(engine.lastStateNotice.value, isNull);

    // Silence the note before teardown and confirm the `off` leg routes too.
    busTap.publish('phi.ctl.voice.bells.off', const BusFloatList([60]));
    await tester.pumpAndSettle();
    expect(midiGateway.calls, contains('sendNoteOff:0:60'));

    // Guard: this test never built a dispatcher — the one under test is the
    // engine's own. Its teardown (via `stop`) must cancel the tap subscription,
    // so a publish after dispose reaches nothing.
    await engine.dispose();
    final before = midiGateway.calls.length;
    busTap.publish('phi.ctl.voice.bells.note', const BusFloatList([72, 100]));
    await tester.pump();
    expect(midiGateway.calls.length, before);

    await busTap.dispose();
    await midiGateway.dispose();
    registry.dispose();
  });
}
