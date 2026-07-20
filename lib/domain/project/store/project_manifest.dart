import '../../shell_layout/shell_layout.dart';

/// The project-wide state that lives in `project.json` at the root of a `.phi`
/// folder — the manifest of design `docs/design/project-registry.md` §5.
///
/// The manifest owns what belongs to the *project* rather than to any one
/// entity: the on-disk [formatVersion] (the folder-layout migration seam), the
/// project [name] (the folder is `<name>.phi/`, but `project.json` is the actual
/// marker), the two pieces of `SessionState` that must survive a restart
/// ([tempo] and [sceneName]), the **master strip's** live state ([masterVolume]
/// and [masterMuted], issue #166), and — since issue #253 — the workspace
/// [layout] (the split tree + tab stacks, design `docs/design/shell-layout.md`
/// §3). Master is not a registry entity (design `docs/design/mix.md` §3 — it
/// can't be renamed, removed, grouped or sent anywhere), so its state has
/// nowhere else to live; the manifest closes the reload gap. The layout lives
/// here because a set's arrangement is part of the set, yet it is **journal-free
/// and not undoable** — workspace arrangement, not authored content, so recovery
/// replay ignores it (§7 decision 1). The recent-projects list deliberately does
/// *not* live here; it belongs to app settings (`%APPDATA%/phi/`).
///
/// A plain, immutable value type: it (de)serialises to a JSON map and compares
/// by value so a save/load round-trip is easy to assert.
class ProjectManifest {
  /// Builds a manifest. [formatVersion] defaults to [currentFormatVersion] so
  /// freshly-minted projects carry the newest layout. [masterVolume] defaults to
  /// unity and [masterMuted] to off — a fresh project's master is untouched.
  /// [layout] defaults to the single-pane Mix seed, so a fresh project boots
  /// behaviour-neutral (design §3).
  const ProjectManifest({
    required this.name,
    this.formatVersion = currentFormatVersion,
    this.tempo = 120,
    this.sceneName = 'untitled',
    this.masterVolume = 1.0,
    this.masterMuted = false,
    this.layout = ShellLayout.defaultSeed,
  });

  /// Reads a manifest from a decoded `project.json` map, tolerating missing keys
  /// (an older or hand-edited file) by falling back to the same defaults as the
  /// constructor. A missing or malformed `layout` section seeds the single-pane
  /// Mix layout, so an older (layout-less) project opens behaviour-neutral.
  factory ProjectManifest.fromJson(Map<String, Object?> json) {
    final layoutJson = json['layout'];
    return ProjectManifest(
      name: json['name'] as String? ?? 'untitled',
      formatVersion: json['formatVersion'] as int? ?? currentFormatVersion,
      tempo: (json['tempo'] as num?)?.toDouble() ?? 120,
      sceneName: json['sceneName'] as String? ?? 'untitled',
      masterVolume: (json['masterVolume'] as num?)?.toDouble() ?? 1.0,
      masterMuted: json['masterMuted'] as bool? ?? false,
      layout: layoutJson is Map
          ? ShellLayout.fromJson(layoutJson.cast<String, Object?>())
          : ShellLayout.defaultSeed,
    );
  }

  /// The current on-disk manifest/layout version. Bump when the folder format
  /// changes in a way that needs a load-time migration.
  static const int currentFormatVersion = 1;

  /// The on-disk layout version this manifest was written with.
  final int formatVersion;

  /// The project's name — mirrored by the `<name>.phi/` folder for discovery.
  final String name;

  /// Session tempo in beats-per-minute, restored into `SessionState` on load.
  final double tempo;

  /// The scene name shown in the toolbar, restored into `SessionState` on load.
  final String sceneName;

  /// The master strip's user-set volume in `[0.0, 1.0]` — master is not an
  /// entity, so its fader value persists here (design `docs/design/mix.md` §3).
  final double masterVolume;

  /// Whether the master strip is muted — persisted here alongside [masterVolume].
  final bool masterMuted;

  /// The workspace layout — the split tree + tab stacks (design
  /// `docs/design/shell-layout.md` §3). Journal-free workspace arrangement:
  /// saved on save/autosave, but never journaled and untouched by recovery
  /// replay (§7 decision 1). Restored with fit-fallback on open (the shell
  /// clamps it to the live surface set + screen).
  final ShellLayout layout;

  /// The manifest as the JSON map written to `project.json`.
  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'name': name,
    'tempo': tempo,
    'sceneName': sceneName,
    'masterVolume': masterVolume,
    'masterMuted': masterMuted,
    'layout': layout.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectManifest &&
      other.formatVersion == formatVersion &&
      other.name == name &&
      other.tempo == tempo &&
      other.sceneName == sceneName &&
      other.masterVolume == masterVolume &&
      other.masterMuted == masterMuted &&
      other.layout == layout;

  @override
  int get hashCode => Object.hash(
    formatVersion,
    name,
    tempo,
    sceneName,
    masterVolume,
    masterMuted,
    layout,
  );

  @override
  String toString() =>
      'ProjectManifest(name: $name, formatVersion: $formatVersion, '
      'tempo: $tempo, sceneName: $sceneName, masterVolume: $masterVolume, '
      'masterMuted: $masterMuted, layout: $layout)';
}
