import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/bridge/real_yse_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:yse/yse.dart' as yse;

import '../test/engine/test_doubles/fake_fx_gateway.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_synth_gateway.dart';

/// The live-coding control plane over the **real** host bus tap (issue #480).
///
/// Unlike the other control-plane walks, nothing here injects a tap: the engine
/// runs on a [RealYseGateway] and listens on that gateway's own session-bound
/// `Bus.tap`. Each frame is published with yse's `Bus.publish` — the same path
/// a script's `yse.send(...)` takes (the bundled engine has no CPython, so a
/// Python `state.verse.fire()` itself cannot run here) — and travels the
/// native tap, the main-isolate callback, the `RealBusTap` adapter and the
/// engine's own [ControlPlaneDispatcher] into the owning controllers. Only the
/// MIDI / synth / fx gateways are fakes, so the routed effects are observable
/// without hardware.
///
/// It also walks the session lifecycle: after a stop → start the engine has a
/// new native session, and the rebuilt dispatcher hears the new session's tap.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a phi.ctl publish reaches the owning controllers through the '
      'real bus tap, across an engine restart', (tester) async {
    final reverb = EntityAddress.parse('fx.reverb');
    const authored = FxDefinition(
      kind: FxKind.lowpassDelay,
      params: {'impact': 0.8, 'frequency': 1200},
    );

    final midiGateway = FakeMidiGateway();
    final fxGateway = FakeFxGateway();
    final engine = PhiEngine(
      RealYseGateway(),
      midiGateway: midiGateway,
      synthGateway: FakeSynthGateway(),
      fxGateway: fxGateway,
    );
    engine.start();

    final registry = ProjectRegistry();
    seedDefaultProject(registry);
    registry.createEntity(reverb, payload: authored.toJson());
    registry.createEntity(
      EntityAddress.parse('mix.verb_bus'),
      payload: MixStrip(voice: 9, inserts: [reverb]).toJson(),
    );
    engine.bindProject(registry);
    await tester.pumpAndSettle();
    engine.runtimeVariables.define(
      name: 'section',
      values: ['a', 'b'],
      current: 'a',
    );

    FakeMaterialisedFx liveReverb() =>
        fxGateway.handles.lastWhere((h) => h.kind == FxKind.lowpassDelay);

    expect(engine.stateMachine.activeStateAddress, introStateAddress);

    // ── state: `state.verse.fire()` ──────────────────────────────────────────
    yse.Bus.publish('phi.ctl.state.fire', const yse.BusString('verse'));
    await tester.pumpAndSettle();
    expect(engine.stateMachine.activeStateAddress, verseStateAddress);

    // ── var: `var.section = "b"` ─────────────────────────────────────────────
    yse.Bus.publish('phi.ctl.var.section', const yse.BusString('b'));
    await tester.pumpAndSettle();
    expect(engine.runtimeVariables.byName('section')!.current, 'b');

    // ── fx: `fx.reverb.impact = 0.25` moves the live effect ──────────────────
    yse.Bus.publish('phi.ctl.fx.reverb.impact', const yse.BusFloat(0.25));
    await tester.pumpAndSettle();
    expect(liveReverb().liveParams, {'impact': 0.25});

    // ── A new engine session: stop closes the native session (and with it
    //    every tap), start opens a fresh one and rebuilds the dispatcher ──────
    engine.stop();
    engine.start();
    await tester.pumpAndSettle();
    expect(liveReverb().liveParams, isEmpty, reason: 'a fresh live effect');

    yse.Bus.publish('phi.ctl.fx.reverb.impact', const yse.BusFloat(0.5));
    await tester.pumpAndSettle();
    expect(liveReverb().liveParams, {'impact': 0.5});

    await engine.dispose();
    await midiGateway.dispose();
    registry.dispose();
  });
}
