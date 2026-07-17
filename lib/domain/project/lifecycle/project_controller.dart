import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../session/session_state.dart';
import '../app_settings/app_settings.dart';
import '../app_settings/app_settings_store.dart';
import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';
import '../recovery/command_journal.dart';
import '../recovery/crash_recovery.dart';
import '../recovery/recovery_offer.dart';
import '../recovery/registry_command_codec.dart';
import '../store/group_metadata.dart';
import '../store/journal_store.dart';
import '../store/project_manifest.dart';
import '../store/project_snapshot.dart';
import '../store/project_store.dart';

/// Shown to the performer when a project's journal holds unsaved work at open
/// time; resolves to the chosen [RecoveryChoice] or `null` to leave the project
/// unopened. The shell supplies one that renders the `RecoveryDialog`.
typedef RecoveryPrompt = Future<RecoveryChoice?> Function(RecoveryOffer offer);

/// The running project's lifecycle coordinator (design
/// `docs/design/project-registry.md` §5, §9) — the object the menu, the dirty
/// indicator, autosave, and the crash-recovery launch flow all talk to.
///
/// It ties together the pure-Dart pieces built by the earlier registry issues:
/// the [ProjectRegistry] (source of truth), a [ProjectStore]/[JournalStore] bound
/// to the current `.phi` folder (built lazily through the injected factories so
/// this class touches no filesystem itself), [SessionState] (tempo + scene name
/// live in the manifest), [CrashRecovery] (replay a dirty journal on open), and
/// [AppSettings] (the recent-projects list and autosave cadence, persisted to
/// `%APPDATA%/phi/`).
///
/// A [ChangeNotifier] plus a handful of [ValueNotifier]s so the toolbar can bind
/// to the project name, the dirty flag, and the recents list without rebuilding
/// on every internal change.
class ProjectController extends ChangeNotifier {
  /// Wires the controller to its collaborators. [storeFactory] and
  /// [journalStoreFactory] mint the I/O seams for a given `.phi` folder (real in
  /// production, fakes in tests). [autosaveIntervalOverride] forces a cadence
  /// regardless of settings — handy for deterministic tests.
  ProjectController({
    required SessionState session,
    required AppSettingsStore settingsStore,
    required ProjectStore Function(String directory) storeFactory,
    required JournalStore Function(String directory) journalStoreFactory,
    RegistryCommandCodec codec = const RegistryCommandCodec(),
    Duration? autosaveIntervalOverride,
  }) : _session = session,
       _settingsStore = settingsStore,
       _storeFactory = storeFactory,
       _journalStoreFactory = journalStoreFactory,
       _codec = codec,
       _autosaveIntervalOverride = autosaveIntervalOverride {
    _session.sceneName.addListener(_onSessionChanged);
    _session.tempo.addListener(_onSessionChanged);
  }

  final SessionState _session;
  final AppSettingsStore _settingsStore;
  final ProjectStore Function(String directory) _storeFactory;
  final JournalStore Function(String directory) _journalStoreFactory;
  final RegistryCommandCodec _codec;
  final Duration? _autosaveIntervalOverride;

  /// The project name, mirrored by the `<name>.phi` folder and written to the
  /// manifest. Bind to it for the toolbar title.
  final ValueNotifier<String> name = ValueNotifier<String>('untitled');

  /// Whether unsaved changes exist since the last save — the dirty indicator's
  /// source (design §9).
  final ValueNotifier<bool> isDirty = ValueNotifier<bool>(false);

  /// The absolute path of the open project's `.phi` folder, or `null` for a new
  /// project that has never been saved.
  final ValueNotifier<String?> location = ValueNotifier<String?>(null);

  /// The recent-projects list, most-recent first — the "Open Recent" menu.
  final ValueNotifier<List<String>> recentProjects =
      ValueNotifier<List<String>>(const []);

  ProjectRegistry _registry = ProjectRegistry();

  /// The live registry — the source of truth for the open project's entities.
  ProjectRegistry get registry => _registry;

  ProjectStore? _store;
  CommandJournal? _journal;
  Map<EntityAddress, GroupMetadata> _groupMetadata = const {};
  final Set<EntityAddress> _dirtyEntities = {};

  AppSettings _settings = const AppSettings();
  Timer? _autosaveTimer;
  bool _applyingSnapshot = false;

  /// Whether the open project has an on-disk home yet (`false` for a brand-new,
  /// never-saved project — the menu must pick a location before it can save).
  bool get isSaved => _store != null;

  /// The autosave cadence in force — the override if given, else the settings
  /// value (design §3, default 60 s).
  Duration get autosaveInterval =>
      _autosaveIntervalOverride ?? _settings.autosaveInterval;

  /// Loads persisted settings (recents + autosave cadence) and starts the
  /// autosave timer. Call once at launch. Safe to call before any project is
  /// open — autosave simply no-ops until one is bound.
  Future<void> loadSettings() async {
    _settings = await _settingsStore.load();
    recentProjects.value = _settings.recentProjects;
    _restartAutosave();
    notifyListeners();
  }

  /// Starts a fresh, empty, never-saved project — the "New" menu action. Resets
  /// the registry and the manifest-backed session state (tempo, scene name) to
  /// defaults without marking anything dirty.
  void newProject({String projectName = 'untitled'}) {
    _unbind();
    _replaceRegistry(ProjectRegistry());
    _groupMetadata = const {};
    _dirtyEntities.clear();
    _applyManifest(ProjectManifest(name: projectName));
    isDirty.value = false;
    notifyListeners();
  }

  /// Opens the project at [directory]. If its journal holds unsaved work, calls
  /// [prompt] and replays per the performer's [RecoveryChoice]; a `null` choice
  /// aborts the open (the current project stays put). On a clean open the
  /// project is loaded as-is; on a recovery the replayed state is saved back so
  /// the journal and sentinel are cleared.
  ///
  /// Throws (e.g. [FormatException] when [directory] is not a project folder);
  /// the caller catches and can [forgetRecent] a dead path.
  Future<void> open(String directory, {RecoveryPrompt? prompt}) async {
    final store = _storeFactory(directory);
    if (!await store.exists()) {
      throw FormatException('Not a project folder: "$directory".');
    }
    final journal = CommandJournal(_journalStoreFactory(directory));
    final recovery = CrashRecovery(
      store: store,
      journal: journal,
      codec: _codec,
    );

    final offer = await recovery.detect();
    RecoveryChoice? choice;
    ProjectSnapshot snapshot;
    if (offer != null) {
      choice = prompt == null ? null : await prompt(offer);
      if (choice == null) return; // performer dismissed — leave project as-is.
      snapshot = await recovery.recover(choice);
    } else {
      snapshot = await store.load();
    }

    _store = store;
    _journal = journal;
    location.value = directory;
    _groupMetadata = snapshot.groupMetadata;
    _dirtyEntities.clear();
    _replaceRegistry(snapshot.registry);
    _applyManifest(snapshot.manifest);

    if (choice != null) {
      // Persist the recovered state, then clear the journal + sentinel (§7).
      await store.save(_snapshot());
      await recovery.resolve();
    }
    isDirty.value = false;
    _rememberRecent(directory);
    notifyListeners();
  }

  /// Saves the open project. Requires [isSaved]; the menu calls [saveAs] first
  /// for a never-saved project. A full save (prunes stale files), then the
  /// journal is truncated and the dirty flag cleared (§5, §7).
  Future<void> save() async {
    final store = _store;
    if (store == null) {
      throw StateError('save() on an unsaved project — call saveAs first.');
    }
    await store.save(_snapshot());
    await _clearJournalAndDirty();
  }

  /// Writes the open project to a new [directory] and continues working there —
  /// the "Save As" / "Duplicate Project" action (design §9; a duplicate is a
  /// portable copy of the folder). Rebinds the store, journal, and recovery to
  /// the new location and records it in recents.
  Future<void> saveAs(String directory) async {
    final store = _storeFactory(directory);
    final journal = CommandJournal(_journalStoreFactory(directory));
    _store = store;
    _journal = journal;
    location.value = directory;
    // The folder is `<name>.phi`, so a Save-As / Duplicate names the project
    // after the folder the performer chose (design §5).
    name.value = _projectNameFor(directory);
    await store.save(_snapshot());
    await _clearJournalAndDirty();
    _rememberRecent(directory);
    notifyListeners();
  }

  /// Renames the project — updates the in-memory name (written to the manifest
  /// on the next save) and marks the project dirty. The on-disk `<name>.phi`
  /// folder is not renamed here; `project.json` remains the marker (§5).
  void renameProject(String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == name.value) return;
    name.value = trimmed;
    markDirty();
  }

  /// Marks the project dirty from a manifest-level change (a scene rename, a
  /// tempo change). No-op while a snapshot is being applied on load, so a clean
  /// load never looks unsaved.
  void markDirty() {
    if (_applyingSnapshot) return;
    if (!isDirty.value) {
      isDirty.value = true;
      notifyListeners();
    }
  }

  /// Records an applied registry [command] against the open project (design §6,
  /// §7): adds its touched entities to the dirty set and, when a project is
  /// bound, appends it to the journal. The seam the entity-migration epic (#124)
  /// wires its command producers into; harmless when no command producers exist
  /// yet.
  void recordCommand(ProjectCommand command) {
    _dirtyEntities.addAll(command.entitiesTouched);
    markDirty();
    final journal = _journal;
    if (journal != null && command.entitiesTouched.isNotEmpty) {
      unawaited(journal.record(command));
    }
  }

  /// Runs one autosave pass: when a project is bound and dirty, writes exactly
  /// the dirty entities (the manifest is always written too) and clears the
  /// journal + dirty flag. Returns whether anything was written. Called by the
  /// autosave timer; exposed so tests drive it deterministically.
  Future<bool> autosaveNow() async {
    final store = _store;
    if (store == null || !isDirty.value) return false;
    await store.save(_snapshot(), dirty: Set.of(_dirtyEntities));
    await _clearJournalAndDirty();
    return true;
  }

  /// Drops [path] from the recents list and persists the change — used when an
  /// open fails because the folder has moved or been deleted.
  void forgetRecent(String path) {
    _settings = _settings.withoutRecentProject(path);
    recentProjects.value = _settings.recentProjects;
    unawaited(_settingsStore.save(_settings));
    notifyListeners();
  }

  // --- internals -----------------------------------------------------------

  ProjectSnapshot _snapshot() => ProjectSnapshot(
    manifest: _manifestFromSession(),
    registry: _registry,
    groupMetadata: _groupMetadata,
  );

  /// The project name a `<name>.phi` folder implies — its basename with the
  /// `.phi` suffix stripped. Falls back to the current name for an oddly-named
  /// folder so the project is never left nameless.
  String _projectNameFor(String directory) {
    var base = p.basename(directory);
    const suffix = '.phi';
    if (base.toLowerCase().endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
    }
    return base.isEmpty ? name.value : base;
  }

  ProjectManifest _manifestFromSession() => ProjectManifest(
    name: name.value,
    tempo: _session.tempo.value,
    sceneName: _session.sceneName.value,
  );

  void _applyManifest(ProjectManifest manifest) {
    _applyingSnapshot = true;
    try {
      name.value = manifest.name;
      _session.setTempo(manifest.tempo);
      _session.renameScene(manifest.sceneName);
    } finally {
      _applyingSnapshot = false;
    }
  }

  void _replaceRegistry(ProjectRegistry next) {
    if (identical(next, _registry)) return;
    final old = _registry;
    _registry = next;
    old.dispose();
  }

  void _unbind() {
    _store = null;
    _journal = null;
    location.value = null;
  }

  Future<void> _clearJournalAndDirty() async {
    final journal = _journal;
    if (journal != null) {
      await journal.truncate();
      await journal.clearRecovering();
    }
    _dirtyEntities.clear();
    isDirty.value = false;
    notifyListeners();
  }

  void _rememberRecent(String directory) {
    _settings = _settings.withRecentProject(directory);
    recentProjects.value = _settings.recentProjects;
    unawaited(_settingsStore.save(_settings));
  }

  void _onSessionChanged() => markDirty();

  void _restartAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(
      autosaveInterval,
      (_) => unawaited(autosaveNow()),
    );
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _session.sceneName.removeListener(_onSessionChanged);
    _session.tempo.removeListener(_onSessionChanged);
    name.dispose();
    isDirty.dispose();
    location.dispose();
    recentProjects.dispose();
    _registry.dispose();
    super.dispose();
  }
}
