import '../code/code_script.dart';
import '../code/code_script_seed.dart';
import '../midi/midi_clip_mode.dart';
import '../midi/midi_clip_seed.dart';
import '../midi/store/clip_document.dart';
import '../state_machine/store/state_seed.dart';
import '../synth/sine_synth.dart';
import '../voice/voice_addresses.dart';
import '../voice/voice_definition.dart';
import 'entity_address.dart';
import 'name_slug.dart';
import 'project_registry.dart';
import 'registry_kinds.dart';

/// Seeds a fresh [ProjectRegistry] with the app's default entities — the v1
/// migration of the on-load demo state into the registry (issue #124), extended
/// in issue #135 to carry the clip's interpretation.
///
/// A brand-new project starts with the same content the app has always booted:
/// the demo clip (`clip.phrase_a`) and the demo time domains (`domain.drum`, …).
/// They are created **directly**, not through the command layer — seeding is
/// initial state, like a load, so it is neither journaled nor marked dirty.
///
/// The clip payload is a [ClipDocument] (as its `toJson` map, matching the
/// map-native `mix.` payloads): the source [phraseA] notes **plus** the
/// [defaultDemoChain] transform list, so a fresh project's clip persists its
/// whole interpretation, not just its notes.
///
/// Mix channels are *not* seeded: a fresh project starts with only the master
/// channel, and user channels arrive as `mix.` entities the moment the performer
/// adds one (the engine's registry-backed channel sync). Display names are
/// slugged into valid addresses ([NameSlug]); the payloads keep the original
/// display name.
void seedDefaultProject(ProjectRegistry registry) {
  final chain = defaultDemoChain();
  final document = ClipDocument(
    source: chain.source,
    mode: MidiClipMode.chain,
    chain: chain.transforms,
  );
  registry.createEntity(
    EntityAddress(
      kind: RegistryKinds.clip,
      // The clip carries no display name (issue #184); its identity is the
      // address leaf, so seed it directly at `clip.phrase_a`.
      segments: const [phraseASlug],
    ),
    payload: document.toJson(),
  );
  // The throwaway chain was only a vehicle for the default transform list; the
  // transforms and source it yielded are independent immutable values.
  chain.dispose();

  // Seed the zero-config starter voice (design §6): `voice.default` →
  // `synth.sine` → master. A fresh project can sound a note before touching a
  // parameter — the default routing chain routes here and any unrouted note
  // resolves here at flatten. The synth definition is created first so the
  // voice's synth reference points at a real entity. Payloads are map-native
  // (their codecs' `toJson`), matching the clip and mix seeds.
  registry.createEntity(
    EntityAddress(kind: RegistryKinds.synth, segments: const ['sine']),
    payload: const SineSynth().toJson(),
  );
  registry.createEntity(
    EntityAddress(
      kind: RegistryKinds.voice,
      segments: const [VoiceAddresses.defaultVoiceName],
    ),
    payload: VoiceDefinition.internal(
      synth: EntityAddress(kind: RegistryKinds.synth, segments: const ['sine']),
      output: EntityAddress(
        kind: RegistryKinds.mix,
        segments: const ['master'],
      ),
    ).toJson(),
  );

  for (final domain in demoTimeDomains.domains) {
    registry.createEntity(
      EntityAddress(
        kind: RegistryKinds.domain,
        segments: [NameSlug.of(domain.name, fallback: 'domain')],
      ),
      payload: domain,
    );
  }

  // Seed the scratch script (design live-coding §5): a fresh project's Code
  // surface opens `code.scratch` so it is never empty. The payload is map-native
  // (its codec's `toJson`), matching the clip / mix / domain seeds.
  registry.createEntity(
    EntityAddress(kind: RegistryKinds.code, segments: const ['scratch']),
    payload: const CodeScript(source: codeScratchSource).toJson(),
  );

  // Seed the default state graph (design state-graph §3, issue #240):
  // `state.intro` → `state.verse`, the pair the State surface has always
  // shown. Payloads are map-native (the journal contract), so each document's
  // outgoing references are declared explicitly — that is how `intro`'s
  // transition to `verse` enters the back-reference index (delete-impact on
  // `verse` lists `intro`; a rename of `verse` remaps the edge). Which state
  // is *live* is performance state and is not seeded here (§8 decision 2);
  // the registry-backed controller (issue #241) keys the seeded live state.
  final intro = introStateDocument();
  registry.createEntity(
    introStateAddress,
    payload: intro.toJson(),
    references: intro.references,
  );
  final verse = verseStateDocument();
  registry.createEntity(
    verseStateAddress,
    payload: verse.toJson(),
    references: verse.references,
  );
}
