/// The project-wide state that lives in `project.json` at the root of a `.phi`
/// folder — the manifest of design `docs/design/project-registry.md` §5.
///
/// The manifest owns what belongs to the *project* rather than to any one
/// entity: the on-disk [formatVersion] (the folder-layout migration seam), the
/// project [name] (the folder is `<name>.phi/`, but `project.json` is the actual
/// marker), and today the two pieces of `SessionState` that must survive a
/// restart — [tempo] and [sceneName]. The recent-projects list deliberately does
/// *not* live here; it belongs to app settings (`%APPDATA%/phi/`).
///
/// A plain, immutable value type: it (de)serialises to a JSON map and compares
/// by value so a save/load round-trip is easy to assert.
class ProjectManifest {
  /// Builds a manifest. [formatVersion] defaults to [currentFormatVersion] so
  /// freshly-minted projects carry the newest layout.
  const ProjectManifest({
    required this.name,
    this.formatVersion = currentFormatVersion,
    this.tempo = 120,
    this.sceneName = 'untitled',
  });

  /// Reads a manifest from a decoded `project.json` map, tolerating missing keys
  /// (an older or hand-edited file) by falling back to the same defaults as the
  /// constructor.
  factory ProjectManifest.fromJson(Map<String, Object?> json) =>
      ProjectManifest(
        name: json['name'] as String? ?? 'untitled',
        formatVersion: json['formatVersion'] as int? ?? currentFormatVersion,
        tempo: (json['tempo'] as num?)?.toDouble() ?? 120,
        sceneName: json['sceneName'] as String? ?? 'untitled',
      );

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

  /// The manifest as the JSON map written to `project.json`.
  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'name': name,
    'tempo': tempo,
    'sceneName': sceneName,
  };

  @override
  bool operator ==(Object other) =>
      other is ProjectManifest &&
      other.formatVersion == formatVersion &&
      other.name == name &&
      other.tempo == tempo &&
      other.sceneName == sceneName;

  @override
  int get hashCode => Object.hash(formatVersion, name, tempo, sceneName);

  @override
  String toString() =>
      'ProjectManifest(name: $name, formatVersion: $formatVersion, '
      'tempo: $tempo, sceneName: $sceneName)';
}
