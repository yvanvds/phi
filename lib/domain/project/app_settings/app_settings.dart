/// The app-wide settings that live outside any project — the minimal seed of
/// the settings file in `%APPDATA%/phi/` (design
/// `docs/design/project-registry.md` §5, §9; the full settings window is
/// `docs/phase2-direction.md` §4.2, separate work).
///
/// Deliberately *not* part of a project's `.phi` folder: the recent-projects
/// list and the autosave cadence belong to the installation, not to any one set.
/// A plain, immutable value type — it (de)serialises to a JSON map and compares
/// by value so a load/save round-trip is easy to assert.
class AppSettings {
  /// Builds settings. [recentProjects] is most-recent-first; [autosaveInterval]
  /// defaults to the design's 60 s (§3, review decision 3).
  const AppSettings({
    this.recentProjects = const [],
    this.autosaveInterval = defaultAutosaveInterval,
  });

  /// Reads settings from a decoded `settings.json` map, tolerating missing or
  /// malformed keys (an older or hand-edited file) by falling back to defaults.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final recents = <String>[
      for (final entry
          in (json['recentProjects'] as List<Object?>? ?? const []))
        if (entry is String) entry,
    ];
    final seconds = (json['autosaveSeconds'] as num?)?.toInt();
    return AppSettings(
      recentProjects: List.unmodifiable(recents),
      autosaveInterval: seconds != null && seconds > 0
          ? Duration(seconds: seconds)
          : defaultAutosaveInterval,
    );
  }

  /// The autosave cadence a fresh install starts with (§3, review decision 3).
  static const Duration defaultAutosaveInterval = Duration(seconds: 60);

  /// How many recent projects the list keeps before dropping the oldest.
  static const int maxRecentProjects = 10;

  /// The `.phi` folder paths of recently opened projects, most-recent first.
  final List<String> recentProjects;

  /// How often autosave writes the dirty entities while a project is open.
  final Duration autosaveInterval;

  /// A copy with [path] promoted to the front of [recentProjects]: any existing
  /// occurrence is removed first (so it moves rather than duplicates), and the
  /// list is capped at [maxRecentProjects], dropping the oldest.
  AppSettings withRecentProject(String path) {
    final next = <String>[
      path,
      for (final existing in recentProjects)
        if (existing != path) existing,
    ];
    return AppSettings(
      recentProjects: List.unmodifiable(
        next.length > maxRecentProjects
            ? next.sublist(0, maxRecentProjects)
            : next,
      ),
      autosaveInterval: autosaveInterval,
    );
  }

  /// A copy with [path] removed from [recentProjects] — used when an open fails
  /// because the folder is gone.
  AppSettings withoutRecentProject(String path) => AppSettings(
    recentProjects: List.unmodifiable(
      recentProjects.where((p) => p != path).toList(),
    ),
    autosaveInterval: autosaveInterval,
  );

  /// The settings as the JSON map written to `settings.json`.
  Map<String, Object?> toJson() => {
    'recentProjects': recentProjects,
    'autosaveSeconds': autosaveInterval.inSeconds,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.autosaveInterval == autosaveInterval &&
      _listEquals(other.recentProjects, recentProjects);

  @override
  int get hashCode =>
      Object.hash(autosaveInterval, Object.hashAll(recentProjects));

  @override
  String toString() =>
      'AppSettings(recentProjects: $recentProjects, '
      'autosaveInterval: $autosaveInterval)';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
