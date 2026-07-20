import '../../fx/fx_codec.dart';
import '../../midi/midi_clip_codec.dart';
import '../../mix/mix_strip_codec.dart';
import '../../patcher/patch_codec.dart';
import '../../synth/synth_codec.dart';
import '../../time_domains/time_domain_codec.dart';
import '../../voice/voice_codec.dart';
import '../registry_kinds.dart';
import 'entity_payload_codec.dart';

/// The per-kind [EntityPayloadCodec] map the v1 migration registers on every
/// [ProjectStore] (design `docs/design/project-registry.md` §5).
///
/// Before the migration the store fell back to the pass-through codec for every
/// kind; now the three migrated namespaces carry real, versioned payloads, so
/// the same map is handed to both `RealProjectStore` (production) and the test
/// fakes. A kind absent here still uses the pass-through codec.
Map<String, EntityPayloadCodec> defaultEntityCodecs() => const {
  RegistryKinds.clip: MidiClipCodec(),
  RegistryKinds.mix: MixStripCodec(),
  RegistryKinds.domain: TimeDomainCodec(),
  RegistryKinds.voice: VoiceCodec(),
  RegistryKinds.synth: SynthCodec(),
  RegistryKinds.fx: FxCodec(),
  RegistryKinds.patch: PatchCodec(),
};

/// The kinds whose *groups* carry a persisted payload in `_group.json` (issue
/// #165, design `docs/design/mix.md` §3). A `mix.` group is a bus with its own
/// fader/sends, so it round-trips a [MixStripCodec] payload; every other kind
/// has plain structural groups (order/colour metadata only). Handed to every
/// [ProjectStore] alongside [defaultEntityCodecs].
Set<String> defaultGroupPayloadKinds() => const {RegistryKinds.mix};
