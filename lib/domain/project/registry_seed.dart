import '../midi/midi_clip_mode.dart';
import '../midi/midi_clip_seed.dart';
import '../midi/store/clip_document.dart';
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
      segments: [NameSlug.of(chain.source.name, fallback: 'clip')],
    ),
    payload: document.toJson(),
  );
  // The throwaway chain was only a vehicle for the default transform list; the
  // transforms and source it yielded are independent immutable values.
  chain.dispose();

  for (final domain in demoTimeDomains.domains) {
    registry.createEntity(
      EntityAddress(
        kind: RegistryKinds.domain,
        segments: [NameSlug.of(domain.name, fallback: 'domain')],
      ),
      payload: domain,
    );
  }
}
