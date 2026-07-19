import '../project/registry_kinds.dart';

/// Well-known `voice.` addresses the migration relies on (design
/// `docs/design/racks-and-voices.md` §3, §6).
///
/// A note's voice is stored as its dotted address string (`MidiNote.voice`), so
/// the one address a fresh project always carries lives here rather than being
/// re-typed as a literal across the seed, the default routing chain, and the
/// flatten resolver.
abstract final class VoiceAddresses {
  /// The seeded default voice — `voice.default` → `synth.sine` → master. A fresh
  /// project boots with it, an unrouted note (`MidiNote.voice == null`) resolves
  /// to it at flatten, and the default routing chain routes to it (§6).
  static const String defaultVoice = '${RegistryKinds.voice}.default';

  /// The leaf name of [defaultVoice] — `default` — the segment beneath the
  /// `voice` kind root.
  static const String defaultVoiceName = 'default';
}
