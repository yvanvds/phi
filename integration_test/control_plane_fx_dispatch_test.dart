import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/engine.dart';

import '../test/engine/test_doubles/fake_bus_tap.dart';
import '../test/engine/test_doubles/fake_fx_gateway.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_synth_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end walk for the host-mediated **fx param plane** in production
/// (issues #316, #348): the frame `fx.reverb.impact = 0.25` publishes (the
/// `phi` library's Python suite proves the `phi.ctl.fx.<addr>.<param>` shape
/// byte-for-byte — `python/tests/test_verbs.py::FxVerbTest`) rides the engine's
/// real bus-tap seam into the [ControlPlaneDispatcher] the *engine itself*
/// builds in [PhiEngine.start] — no dispatcher is constructed here — and out
/// through the real fx port onto the **live** effect handle the rack
/// materialiser placed on a bus's insert chain.
///
/// The tap and the fx gateway are faked (no audio hardware; the tap C API is a
/// pending engine dependency, design `docs/design/live-coding.md` §9), but
/// every seam between them is the production one. The set is performance, not
/// authorship: nothing is journaled and the authored `fx.` payload is
/// untouched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a phi.ctl.fx param set moves the live effect through the '
      'production dispatcher, unjournaled', (tester) async {
    final reverb = EntityAddress.parse('fx.reverb');
    const authored = FxDefinition(
      kind: FxKind.lowpassDelay,
      params: {'impact': 0.8, 'frequency': 1200},
    );

    final busTap = FakeBusTap();
    final midiGateway = FakeMidiGateway();
    final fxGateway = FakeFxGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      synthGateway: FakeSynthGateway(),
      fxGateway: fxGateway,
      busTap: busTap,
    );
    engine.start();

    // A seeded project plus an `fx.reverb` placed on a bus's insert chain.
    final registry = ProjectRegistry();
    seedDefaultProject(registry);
    registry.createEntity(reverb, payload: authored.toJson());
    registry.createEntity(
      EntityAddress.parse('mix.verb_bus'),
      payload: MixStrip(voice: 9, inserts: [reverb]).toJson(),
    );
    final recorded = <ProjectCommand>[];
    engine.bindProject(registry, recordCommand: recorded.add);
    await tester.pumpAndSettle();

    final handle = fxGateway.handles.lastWhere(
      (h) => h.kind == FxKind.lowpassDelay,
    );
    // The effect is live on the bus chain before any script touches it.
    expect(
      fxGateway.chains.any((c) => c.walkFromHead().contains(handle)),
      isTrue,
    );
    expect(handle.liveParams, isEmpty);

    // ── `fx.reverb.impact = 0.25` moves the live effect's param ──────────────
    busTap.publish('phi.ctl.fx.reverb.impact', const BusFloat(0.25));
    await tester.pumpAndSettle();

    expect(handle.liveParams, {'impact': 0.25});
    // Unjournaled: the authored definition and payload stand, nothing recorded.
    expect(handle.definition, authored);
    expect(
      FxDefinition.fromJson(
        (registry.entityAt(reverb)!.payload as Map).cast<String, Object?>(),
      ),
      authored,
    );
    expect(recorded, isEmpty);

    // ── A non-numeric value degrades gracefully — never a route, never a crash
    busTap.publish('phi.ctl.fx.reverb.impact', const BusString('loud'));
    await tester.pumpAndSettle();
    expect(handle.liveParams, {'impact': 0.25});

    // After the engine stops its dispatcher is gone: a set reaches nothing.
    await engine.dispose();
    busTap.publish('phi.ctl.fx.reverb.impact', const BusFloat(0.9));
    await tester.pump();
    expect(handle.liveParams, {'impact': 0.25});

    await busTap.dispose();
    await midiGateway.dispose();
    registry.dispose();
  });
}
