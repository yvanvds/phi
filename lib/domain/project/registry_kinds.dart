/// The registry namespace names the v1 migration populates (design
/// `docs/design/project-registry.md` §2, entity-kinds table).
///
/// The registry core is kind-generic — it never hard-codes these — but the
/// migration layer (seeding, the per-kind codec map, the engine's channel sync)
/// needs a single, spelled-once home for the strings so `mix`, `clip` and
/// `domain` are never re-typed as literals scattered across files.
abstract final class RegistryKinds {
  /// MIDI clips — the demo clip migrates here in v1.
  static const String clip = 'clip';

  /// Mix buses / channels — the current strips migrate here in v1.
  static const String mix = 'mix';

  /// Time domains — `TimeDomainRegistry` migrates here in v1.
  static const String domain = 'domain';

  /// Playable voices — `voice.` entities binding synth + bus + colour (racks
  /// epic, `docs/design/racks-and-voices.md` §3).
  static const String voice = 'voice';

  /// Synth definitions — `synth.` recipes voices instantiate (racks epic §4).
  static const String synth = 'synth';

  /// Insert-effect instances — `fx.` entities placed on mix buses (racks
  /// epic §5).
  static const String fx = 'fx';

  /// Node-and-cable patchers — `patch.` entities whose payload is the engine
  /// dump (patcher epic, `docs/design/patcher.md` §3).
  static const String patch = 'patch';
}
