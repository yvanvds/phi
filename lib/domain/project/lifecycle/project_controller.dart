import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../session/session_state.dart';
import '../../shell_layout/shell_layout.dart';
import '../app_settings/app_settings_controller.dart';
import '../app_settings/audio_settings.dart';
import '../app_settings/midi_settings.dart';
import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';
import '../recovery/command_journal.dart';
import '../recovery/crash_recovery.dart';
import '../recovery/recovery_offer.dart';
import '../recovery/registry_command_codec.dart';
import '../registry_group.dart';
import '../registry_node.dart';
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
/// the [AppSettingsController] (the single owner of the recent-projects list and
/// autosave cadence — this controller folds its recents writes through it, so
/// `settings.json` is never written from two places).
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
    required AppSettingsController settings,
    required ProjectStore Function(String directory) storeFactory,
    required JournalStore Function(String directory) journalStoreFactory,
    RegistryCommandCodec codec = const RegistryCommandCodec(),
    void Function(ProjectRegistry registry)? seedRegistry,
    Duration? autosaveIntervalOverride,
  }) : _session = session,
       _settings = settings,
       _storeFactory = storeFactory,
       _journalStoreFactory = journalStoreFactory,
       _codec = codec,
       _seedRegistry = seedRegistry,
       _autosaveIntervalOverride = autosaveIntervalOverride {
    _session.sceneName.addListener(_onSessionChanged);
    _session.tempo.addListener(_onSessionChanged);
    // Master volume/mute are manifest state too (design `docs/design/mix.md` §3),
    // so a live master change dirties the project like a tempo change.
    _session.masterVolume.addListener(_onSessionChanged);
    _session.masterMuted.addListener(_onSessionChanged);
    // The settings controller is the single owner of the live value; mirror its
    // recents into [recentProjects] so the File menu follows every write —
    // whether it came from here (open/save) or, later, the settings dialog.
    _settings.addListener(_onSettingsChanged);
  }

  final SessionState _session;

  /// The single owner of the app-wide settings value — the only object that ever
  /// writes `settings.json` (design §7). Recents writes and settings edits both
  /// flow through its `update`, so concurrent writers are impossible.
  final AppSettingsController _settings;
  final ProjectStore Function(String directory) _storeFactory;
  final JournalStore Function(String directory) _journalStoreFactory;
  final RegistryCommandCodec _codec;

  /// Populates a fresh project's registry with the app's default entities (the
  /// demo clip, the time domains) — the v1 migration seed (issue #124). `null`
  /// leaves a new project empty, the pre-migration behaviour.
  final void Function(ProjectRegistry registry)? _seedRegistry;
  final Duration? _autosaveIntervalOverride;

  /// The project name, mirrored by the `<name>.phi` folder and written to the
  /// manifest. Bind to it for the toolbar title.
  final ValueNotifier<String> name = ValueNotifier<String>('untitled');

  /// Whether unsaved changes exist since the last save — the dirty indicator's
  /// source (design §9).
  final ValueNotifier<bool> isDirty = ValueNotifier<bool>(false);

  /// Runs immediately before a [save] / [saveAs] / [autosaveNow] snapshots the
  /// project — the seam a subsystem that keeps live engine state outside the
  /// registry uses to fold it back in first. The engine wires this to flush each
  /// open patcher's dump into its `patch.` entity (issue #220), so a save captures
  /// the *live* patch, not the last-loaded one. Any registry updates it records
  /// (through [recordCommand]) are picked up by the snapshot / dirty set that
  /// follows. `null` (the default) skips the step.
  void Function()? onBeforeSave;

  /// The absolute path of the open project's `.phi` folder, or `null` for a new
  /// project that has never been saved.
  final ValueNotifier<String?> location = ValueNotifier<String?>(null);

  /// The recent-projects list, most-recent first — the "Open Recent" menu.
  final ValueNotifier<List<String>> recentProjects =
      ValueNotifier<List<String>>(const []);

  /// The pinned-projects list, most-recently pinned first — floated to the top
  /// of the File menu and never aged out (design §6, §9.2). Mirrored from the
  /// single settings owner so a pin/unpin in the settings dialog updates the
  /// menu at once.
  final ValueNotifier<List<String>> pinnedProjects =
      ValueNotifier<List<String>>(const []);

  ProjectRegistry _registry = ProjectRegistry();

  /// The live registry — the source of truth for the open project's entities.
  ProjectRegistry get registry => _registry;

  /// The workspace [ShellLayout] persisted in the manifest (design
  /// `docs/design/shell-layout.md` §3). Owned here so a save writes it and an
  /// open restores it, but **journal-free**: the shell's live layout controller
  /// is the editing owner and pushes changes in through [updateLayout], which
  /// dirties the manifest without ever touching the command journal. Seeds the
  /// single-pane Mix layout for a fresh project.
  ShellLayout _layout = ShellLayout.defaultSeed;

  /// The workspace layout the manifest carries — what a save persists.
  ShellLayout get layout => _layout;

  /// Bumped every time a load ([open]/[newProject]) applies a manifest layout,
  /// so the shell can adopt the restored arrangement into its live layout
  /// controller (with fit-fallback) without polling. A monotonic revision — not
  /// the layout itself — so a reopen that restores the *same* layout the shell
  /// currently shows still fires (an unsaved local rearrange is discarded).
  final ValueNotifier<int> layoutRestored = ValueNotifier<int>(0);

  ProjectStore? _store;
  CommandJournal? _journal;
  Map<EntityAddress, GroupMetadata> _groupMetadata = const {};
  final Set<EntityAddress> _dirtyEntities = {};

  Timer? _autosaveTimer;

  /// The cadence the autosave timer is currently armed for, so a settings change
  /// re-arms only when the interval actually moved. `null` until the first arm.
  Duration? _armedAutosaveInterval;

  /// Whether autosave has been armed at least once (via [loadSettings]). A
  /// cadence edit only re-arms after launch has started the timer, so a bare
  /// controller in a widget test never spins a stray timer on an unrelated
  /// settings write.
  bool _autosaveStarted = false;

  bool _applyingSnapshot = false;

  /// Whether the open project has an on-disk home yet (`false` for a brand-new,
  /// never-saved project — the menu must pick a location before it can save).
  bool get isSaved => _store != null;

  /// The autosave cadence in force — the override if given, else the settings
  /// value (design §3, default 60 s).
  Duration get autosaveInterval =>
      _autosaveIntervalOverride ?? _settings.value.autosaveInterval;

  /// The stored audio settings (chosen output device + overrides + layout) the
  /// engine boots from once [loadSettings] has read `settings.json` — the shell
  /// applies these to the engine at launch (design §5).
  AudioSettings get audioSettings => _settings.value.audio;

  /// The stored MIDI settings (chosen output port + enabled input ports) the
  /// engine applies once [loadSettings] has read `settings.json` — the shell
  /// applies these to the engine at launch (design §5).
  MidiSettings get midiSettings => _settings.value.midi;

  /// The single owner of the live app settings (design §7) — the object the
  /// settings dialog reads the current sections from and writes edits back
  /// through, so `settings.json` still has exactly one writer.
  AppSettingsController get settingsController => _settings;

  /// Loads persisted settings (recents + autosave cadence) through the single
  /// settings owner and starts the autosave timer. Call once at launch. Safe to
  /// call before any project is open — autosave simply no-ops until one is bound.
  Future<void> loadSettings() async {
    await _settings.load();
    // [_onSettingsChanged] mirrored the loaded recents; arm autosave with the
    // now-current cadence.
    _restartAutosave();
    notifyListeners();
  }

  /// Starts a fresh, empty, never-saved project — the "New" menu action. Resets
  /// the registry and the manifest-backed session state (tempo, scene name) to
  /// defaults without marking anything dirty.
  void newProject({String projectName = 'untitled'}) {
    _unbind();
    final registry = ProjectRegistry();
    _seedRegistry?.call(registry);
    _replaceRegistry(registry);
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
    onBeforeSave?.call();
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
    onBeforeSave?.call();
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

  /// Records a new workspace [layout] from the shell's live layout controller —
  /// the persistence side of a split / dock move / resize (design
  /// `docs/design/shell-layout.md` §3). It dirties the manifest so the next
  /// save/autosave writes the arrangement, but is deliberately **journal-free**:
  /// it never appends to the command journal and is not undoable (layout is
  /// workspace arrangement, not authored content — recovery replay ignores it).
  /// A no-op when the layout is unchanged, so an idempotent relayout — or the
  /// shell echoing a just-restored layout back — never spuriously dirties the
  /// set. Ignored while a snapshot is being applied, so a load never looks
  /// unsaved.
  void updateLayout(ShellLayout layout) {
    if (_applyingSnapshot) return;
    if (layout == _layout) return;
    _layout = layout;
    markDirty();
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
    onBeforeSave?.call();
    await store.save(_snapshot(), dirty: Set.of(_dirtyEntities));
    await _clearJournalAndDirty();
    return true;
  }

  /// Drops [path] from the recents list and persists the change — used when an
  /// open fails because the folder has moved or been deleted. Routed through the
  /// single settings owner, which mirrors the change back into [recentProjects].
  void forgetRecent(String path) {
    unawaited(_settings.update(_settings.value.withoutRecentProject(path)));
  }

  // --- internals -----------------------------------------------------------

  ProjectSnapshot _snapshot() => ProjectSnapshot(
    manifest: _manifestFromSession(),
    registry: _registry,
    groupMetadata: _liveGroupMetadata(),
  );

  /// The group metadata a save persists, with each group's child [order] taken
  /// from the **live registry** child order — so a Mix-surface section reorder
  /// (design `docs/design/mix.md` §7) sticks through a save/reload — and its
  /// cosmetic colour carried over from what was loaded. Order is omitted when it
  /// already matches the alphabetical default a load falls back to, so a group
  /// that was never reordered writes no `order` field (and nothing at all when
  /// it also has no colour), keeping saves minimal and diffable.
  Map<EntityAddress, GroupMetadata> _liveGroupMetadata() {
    final result = <EntityAddress, GroupMetadata>{};
    for (final address in _allGroupAddresses()) {
      final childNames = _registry
          .childrenOfGroup(address)
          .map((n) => n.name)
          .toList();
      final sorted = [...childNames]..sort();
      final order = _sameOrder(childNames, sorted)
          ? const <String>[]
          : childNames;
      final color = _groupMetadata[address]?.color;
      final meta = GroupMetadata(order: order, color: color);
      if (!meta.isEmpty) result[address] = meta;
    }
    return result;
  }

  /// Every group address in the live registry, across every kind, in pre-order.
  List<EntityAddress> _allGroupAddresses() {
    final result = <EntityAddress>[];
    void walk(String kind, List<String> prefix, Iterable<RegistryNode> nodes) {
      for (final node in nodes) {
        if (node is! RegistryGroup) continue;
        final segments = [...prefix, node.name];
        final address = EntityAddress(kind: kind, segments: segments);
        result.add(address);
        walk(kind, segments, _registry.childrenOfGroup(address));
      }
    }

    for (final kind in _registry.kinds) {
      walk(kind, const [], _registry.childrenOfKind(kind));
    }
    return result;
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

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
    masterVolume: _session.masterVolume.value,
    masterMuted: _session.masterMuted.value,
    layout: _layout,
  );

  void _applyManifest(ProjectManifest manifest) {
    _applyingSnapshot = true;
    try {
      name.value = manifest.name;
      _session.setTempo(manifest.tempo);
      _session.renameScene(manifest.sceneName);
      _session.setMasterVolume(manifest.masterVolume);
      _session.setMasterMuted(manifest.masterMuted);
      _layout = manifest.layout;
    } finally {
      _applyingSnapshot = false;
    }
    // Signal the shell to adopt the restored workspace layout (journal-free
    // state the shell owns the *editing* of). A monotonic bump so every load
    // fires, even one restoring the layout the shell already shows.
    layoutRestored.value = layoutRestored.value + 1;
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
    unawaited(_settings.update(_settings.value.withRecentProject(directory)));
  }

  void _onSessionChanged() => markDirty();

  /// Mirrors the single settings owner's recents + pins into [recentProjects] /
  /// [pinnedProjects] whenever the live value changes — so the File menu follows
  /// every write, no matter who triggered it (this controller or the settings
  /// dialog). A changed autosave cadence re-arms the timer (design §5, "on the
  /// next timer arm"), but only once launch has started it, so a bare controller
  /// never spins a stray timer.
  void _onSettingsChanged() {
    recentProjects.value = _settings.value.recentProjects;
    pinnedProjects.value = _settings.value.pinnedProjects;
    if (_autosaveStarted && autosaveInterval != _armedAutosaveInterval) {
      _restartAutosave();
    }
  }

  /// Arms (or re-arms) the autosave timer for the current [autosaveInterval]. A
  /// zero or negative cadence disables autosave (design §6): the timer is left
  /// cancelled until the cadence is raised again.
  void _restartAutosave() {
    _autosaveTimer?.cancel();
    _autosaveStarted = true;
    final interval = autosaveInterval;
    _armedAutosaveInterval = interval;
    if (interval <= Duration.zero) {
      _autosaveTimer = null;
      return;
    }
    _autosaveTimer = Timer.periodic(interval, (_) => unawaited(autosaveNow()));
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _session.sceneName.removeListener(_onSessionChanged);
    _session.tempo.removeListener(_onSessionChanged);
    _session.masterVolume.removeListener(_onSessionChanged);
    _session.masterMuted.removeListener(_onSessionChanged);
    // The settings controller is injected — stop listening, but its owner
    // disposes it.
    _settings.removeListener(_onSettingsChanged);
    name.dispose();
    isDirty.dispose();
    location.dispose();
    recentProjects.dispose();
    pinnedProjects.dispose();
    layoutRestored.dispose();
    _registry.dispose();
    super.dispose();
  }
}
