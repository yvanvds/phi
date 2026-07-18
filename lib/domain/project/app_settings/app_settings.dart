import 'audio_settings.dart';
import 'midi_settings.dart';

/// The app-wide settings that live outside any project — the contents of the
/// settings file in `%APPDATA%/phi/` (design
/// `docs/design/project-registry.md` §5, §9 and
/// `docs/design/settings-and-devices.md` §3).
///
/// Deliberately *not* part of a project's `.phi` folder: recents, pins, the
/// autosave cadence, and the chosen audio/MIDI hardware belong to the
/// installation (they would be *wrong on another machine*), not to any one set.
/// A plain, immutable value type — it (de)serialises to a JSON map and compares
/// by value so a load/save round-trip is easy to assert.
///
/// Growth is by *tolerant parse*: each section's `fromJson` falls back per key,
/// so an older or hand-edited file missing the newer keys loads to defaults. The
/// [version] field is written now (design §3) for the day tolerance alone isn't
/// enough and an explicit migration is needed.
class AppSettings {
  /// Builds settings. [recentProjects] is most-recent-first; [pinnedProjects]
  /// are the performer's pins (listed first in the File menu, never dropped by
  /// the recents cap); [autosaveInterval] defaults to the design's 60 s.
  const AppSettings({
    this.recentProjects = const [],
    this.pinnedProjects = const [],
    this.autosaveInterval = defaultAutosaveInterval,
    this.audio = const AudioSettings(),
    this.midi = const MidiSettings(),
    this.version = schemaVersion,
  });

  /// Reads settings from a decoded `settings.json` map, tolerating missing or
  /// malformed keys (an older or hand-edited file) by falling back to defaults.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    final rawRecents = json['recentProjects'];
    final recents = <String>[
      for (final entry in (rawRecents is List ? rawRecents : const []))
        if (entry is String) entry,
    ];
    final rawPinned = json['pinnedProjects'];
    final pinned = <String>[
      for (final entry in (rawPinned is List ? rawPinned : const []))
        if (entry is String) entry,
    ];
    final seconds = json['autosaveSeconds'];
    final storedVersion = json['version'];
    final audioJson = json['audio'];
    final midiJson = json['midi'];
    return AppSettings(
      recentProjects: List.unmodifiable(recents),
      pinnedProjects: List.unmodifiable(pinned),
      // An explicit non-negative cadence is honoured — including `0`, which
      // disables autosave (design §6) and must survive a round-trip. A missing,
      // negative, or non-numeric value falls back to the default.
      autosaveInterval: seconds is num && seconds >= 0
          ? Duration(seconds: seconds.toInt())
          : defaultAutosaveInterval,
      audio: audioJson is Map<String, Object?>
          ? AudioSettings.fromJson(audioJson)
          : const AudioSettings(),
      midi: midiJson is Map<String, Object?>
          ? MidiSettings.fromJson(midiJson)
          : const MidiSettings(),
      version: storedVersion is num && storedVersion > 0
          ? storedVersion.toInt()
          : schemaVersion,
    );
  }

  /// The current `settings.json` schema version (design §3 — write `1`).
  static const int schemaVersion = 1;

  /// The autosave cadence a fresh install starts with (§3, review decision 3).
  static const Duration defaultAutosaveInterval = Duration(seconds: 60);

  /// How many recent projects the list keeps before dropping the oldest. Pins
  /// are exempt — they live in [pinnedProjects] and never age out.
  static const int maxRecentProjects = 10;

  /// The `.phi` folder paths of recently opened projects, most-recent first.
  /// Never contains a path that is also in [pinnedProjects] — a pin moves the
  /// path out of here so the File menu shows it once.
  final List<String> recentProjects;

  /// The `.phi` folder paths the performer pinned — listed first in the File
  /// menu and never dropped by the recents cap. Most-recently pinned first.
  final List<String> pinnedProjects;

  /// How often autosave writes the dirty entities while a project is open.
  final Duration autosaveInterval;

  /// The chosen audio output device and its overrides (design §3).
  final AudioSettings audio;

  /// The chosen MIDI output port and enabled input ports (design §3).
  final MidiSettings midi;

  /// The schema version this value was built with — [schemaVersion] for a fresh
  /// install or a tolerant load of an older file.
  final int version;

  /// A copy with [path] promoted to the front of [recentProjects]: any existing
  /// occurrence is removed first (so it moves rather than duplicates), and the
  /// list is capped at [maxRecentProjects], dropping the oldest. A pinned path
  /// is left as-is — it is already remembered as a pin, so recents is unchanged.
  AppSettings withRecentProject(String path) {
    if (pinnedProjects.contains(path)) return this;
    final next = <String>[
      path,
      for (final existing in recentProjects)
        if (existing != path) existing,
    ];
    return _copyWith(
      recentProjects: List.unmodifiable(
        next.length > maxRecentProjects
            ? next.sublist(0, maxRecentProjects)
            : next,
      ),
    );
  }

  /// A copy with [path] forgotten entirely — removed from both [recentProjects]
  /// and [pinnedProjects]. Used when an open fails because the folder is gone.
  AppSettings withoutRecentProject(String path) => _copyWith(
    recentProjects: List.unmodifiable(
      recentProjects.where((p) => p != path).toList(),
    ),
    pinnedProjects: List.unmodifiable(
      pinnedProjects.where((p) => p != path).toList(),
    ),
  );

  /// A copy with [path] pinned: moved to the front of [pinnedProjects]
  /// (de-duplicated) and removed from [recentProjects] so the File menu lists it
  /// once, at the top, immune to the recents cap.
  AppSettings withPinnedProject(String path) {
    final pins = <String>[
      path,
      for (final existing in pinnedProjects)
        if (existing != path) existing,
    ];
    return _copyWith(
      recentProjects: List.unmodifiable(
        recentProjects.where((p) => p != path).toList(),
      ),
      pinnedProjects: List.unmodifiable(pins),
    );
  }

  /// A copy with [path] unpinned: removed from [pinnedProjects] and promoted to
  /// the front of [recentProjects] (through [withRecentProject], so it is capped
  /// like any recent) — it becomes an ordinary recent that can age out again.
  AppSettings withoutPinnedProject(String path) {
    if (!pinnedProjects.contains(path)) return this;
    return _copyWith(
      pinnedProjects: List.unmodifiable(
        pinnedProjects.where((p) => p != path).toList(),
      ),
    ).withRecentProject(path);
  }

  /// A copy with the [audio] section replaced — the single write the settings
  /// dialog's AUDIO section makes (design §6, §7). Everything else (recents,
  /// pins, cadence, MIDI, version) is carried through unchanged, so persisting an
  /// audio edit never disturbs the rest of the file.
  AppSettings withAudio(AudioSettings audio) => AppSettings(
    recentProjects: recentProjects,
    pinnedProjects: pinnedProjects,
    autosaveInterval: autosaveInterval,
    audio: audio,
    midi: midi,
    version: version,
  );

  /// A copy with the [midi] section replaced — the single write the settings
  /// dialog's MIDI section makes (design §6, §7). Everything else (recents,
  /// pins, cadence, audio, version) is carried through unchanged, so persisting a
  /// MIDI edit never disturbs the rest of the file.
  AppSettings withMidi(MidiSettings midi) => AppSettings(
    recentProjects: recentProjects,
    pinnedProjects: pinnedProjects,
    autosaveInterval: autosaveInterval,
    audio: audio,
    midi: midi,
    version: version,
  );

  /// A copy with the autosave [interval] replaced — the PROJECTS section's
  /// cadence field (design §6). A zero (or negative) interval disables autosave;
  /// the change takes effect on the next timer arm (design §5). Everything else
  /// is carried through unchanged.
  AppSettings withAutosaveInterval(Duration interval) => AppSettings(
    recentProjects: recentProjects,
    pinnedProjects: pinnedProjects,
    autosaveInterval: interval,
    audio: audio,
    midi: midi,
    version: version,
  );

  /// A copy with the recents list emptied — the PROJECTS section's "clear all"
  /// (design §6, §9.2). Pins are left intact: they are managed separately and
  /// never age out, so clearing recents leaves the pinned projects standing.
  AppSettings withClearedRecents() => AppSettings(
    recentProjects: const [],
    pinnedProjects: pinnedProjects,
    autosaveInterval: autosaveInterval,
    audio: audio,
    midi: midi,
    version: version,
  );

  /// The settings as the JSON map written to `settings.json`.
  Map<String, Object?> toJson() => {
    'version': version,
    'recentProjects': recentProjects,
    'pinnedProjects': pinnedProjects,
    'autosaveSeconds': autosaveInterval.inSeconds,
    'audio': audio.toJson(),
    'midi': midi.toJson(),
  };

  AppSettings _copyWith({
    List<String>? recentProjects,
    List<String>? pinnedProjects,
  }) => AppSettings(
    recentProjects: recentProjects ?? this.recentProjects,
    pinnedProjects: pinnedProjects ?? this.pinnedProjects,
    autosaveInterval: autosaveInterval,
    audio: audio,
    midi: midi,
    version: version,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.version == version &&
      other.autosaveInterval == autosaveInterval &&
      other.audio == audio &&
      other.midi == midi &&
      _listEquals(other.recentProjects, recentProjects) &&
      _listEquals(other.pinnedProjects, pinnedProjects);

  @override
  int get hashCode => Object.hash(
    version,
    autosaveInterval,
    audio,
    midi,
    Object.hashAll(recentProjects),
    Object.hashAll(pinnedProjects),
  );

  @override
  String toString() =>
      'AppSettings(version: $version, recentProjects: $recentProjects, '
      'pinnedProjects: $pinnedProjects, autosaveInterval: $autosaveInterval, '
      'audio: $audio, midi: $midi)';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
