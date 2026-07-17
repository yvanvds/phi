import '../midi/midi_clip_seed.dart';
import 'entity_address.dart';
import 'name_slug.dart';
import 'project_registry.dart';
import 'registry_kinds.dart';

/// Seeds a fresh [ProjectRegistry] with the app's default entities — the v1
/// migration of the on-load demo state into the registry (issue #124).
///
/// A brand-new project starts with the same content the app has always booted:
/// the demo clip (`clip.phrase_a`, carrying the [phraseA] source) and the demo
/// time domains (`domain.drum`, …). They are created **directly**, not through
/// the command layer — seeding is initial state, like a load, so it is neither
/// journaled nor marked dirty.
///
/// Mix channels are *not* seeded: a fresh project starts with only the master
/// channel, and user channels arrive as `mix.` entities the moment the performer
/// adds one (the engine's registry-backed channel sync). Display names are
/// slugged into valid addresses ([NameSlug]); the payloads keep the original
/// display name.
void seedDefaultProject(ProjectRegistry registry) {
  final clip = phraseA();
  registry.createEntity(
    EntityAddress(
      kind: RegistryKinds.clip,
      segments: [NameSlug.of(clip.name, fallback: 'clip')],
    ),
    payload: clip,
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
}
