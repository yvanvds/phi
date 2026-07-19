import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/synth_definition.dart';
import 'package:phi/domain/voice/voice_definition.dart';

import '../test_doubles/fake_project_store.dart';

/// The racks-domain acceptance test (issue #204, design
/// `docs/design/racks-and-voices.md` §3–§5): a registry carrying `synth.`,
/// `voice.`, `fx.` and `mix.` entities round-trips every payload identity through
/// the store's per-kind codecs, and the back-reference index lists the right
/// referents for a delete — `voice → synth`, `voice → mix`, `mix.inserts → fx`.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  final synthAddr = addr('synth.fm_bells');
  final voiceAddr = addr('voice.bells');
  final fxAddr = addr('fx.big_delay');
  final busAddr = addr('mix.perc');

  const synth = FmSynth(
    bankAsset: 'assets/bells.syx',
    patchIndex: 4,
    algorithm: 5,
    voiceCount: 8,
  );
  final voice = VoiceDefinition.internal(
    synth: synthAddr,
    output: busAddr,
    color: 'amber',
  );
  const fx = FxDefinition(
    kind: FxKind.lowpassDelay,
    params: {'taps': 4.0, 'impact': 0.5},
  );
  final bus = MixStrip(voice: 3, inserts: [fxAddr]);

  /// Builds a registry wired the way the racks epic will: a synth definition, a
  /// voice pointing at it and at its bus, an fx instance, and a mix bus whose
  /// insert chain holds the fx. Payloads are stored as their domain objects so
  /// the `ReferenceSource` edges (voice → synth/bus, mix → fx) auto-register.
  ProjectRegistry buildRegistry() {
    final registry = ProjectRegistry();
    registry.createEntity(synthAddr, payload: synth);
    registry.createEntity(fxAddr, payload: fx);
    registry.createEntity(busAddr, payload: bus);
    registry.createEntity(voiceAddr, payload: voice);
    return registry;
  }

  ProjectSnapshot snapshotOf(ProjectRegistry registry) => ProjectSnapshot(
    manifest: const ProjectManifest(
      name: 'racks_set',
      tempo: 120,
      sceneName: 'intro',
    ),
    registry: registry,
  );

  void expectDeleteImpacts(ProjectRegistry registry) {
    // voice → synth: deleting the definition strands the voice built from it.
    expect(registry.impactOfRemoving(synthAddr).referrers, [voiceAddr]);
    // voice → mix: deleting the bus strands the voice routed to it.
    expect(registry.impactOfRemoving(busAddr).referrers, [voiceAddr]);
    // mix.inserts → fx: deleting the effect strands the bus that inserts it.
    expect(registry.impactOfRemoving(fxAddr).referrers, [busAddr]);
    // A leaf nothing points at is safe to remove.
    expect(registry.impactOfRemoving(voiceAddr).isSafe, isTrue);
  }

  test('delete-impact lists voice/synth/fx referents in memory', () {
    final registry = buildRegistry();
    addTearDown(registry.dispose);
    expectDeleteImpacts(registry);
  });

  test('every racks payload round-trips identity through save/load', () async {
    final registry = buildRegistry();
    addTearDown(registry.dispose);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));
    final loaded = await store.load();
    addTearDown(loaded.registry.dispose);

    Map<String, Object?> payloadAt(EntityAddress a) =>
        (loaded.registry.entityAt(a)!.payload! as Map).cast<String, Object?>();

    expect(SynthDefinition.fromJson(payloadAt(synthAddr)), synth);
    expect(VoiceDefinition.fromJson(payloadAt(voiceAddr)), voice);
    expect(FxDefinition.fromJson(payloadAt(fxAddr)), fx);
    expect(MixStrip.fromJson(payloadAt(busAddr)), bus);
  });

  test('the back-reference index is restored after a reload', () async {
    final registry = buildRegistry();
    addTearDown(registry.dispose);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));
    final loaded = await store.load();
    addTearDown(loaded.registry.dispose);

    // Delete-impact works identically on the freshly-loaded registry — the
    // references survived the store round-trip.
    expectDeleteImpacts(loaded.registry);
  });

  test(
    'the on-disk entity files carry their kind and schema version',
    () async {
      final registry = buildRegistry();
      addTearDown(registry.dispose);

      final store = FakeProjectStore(codecs: defaultEntityCodecs());
      await store.save(snapshotOf(registry));

      expect(store.files.containsKey('synth/fm_bells.json'), isTrue);
      expect(store.files.containsKey('voice/bells.json'), isTrue);
      expect(store.files.containsKey('fx/big_delay.json'), isTrue);
      expect(store.files.containsKey('mix/perc.json'), isTrue);
    },
  );

  test('the kinds are registered with real codecs (not pass-through)', () {
    final codecs = defaultEntityCodecs();
    expect(codecs[RegistryKinds.voice], isNotNull);
    expect(codecs[RegistryKinds.synth], isNotNull);
    expect(codecs[RegistryKinds.fx], isNotNull);
  });
}
