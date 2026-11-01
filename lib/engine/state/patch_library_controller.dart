import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/patcher/patch_library.dart';
import '../../domain/patcher/patch_payload.dart';
import '../../domain/patcher/tutorial/patch_tutorial.dart';
import '../../domain/patcher/tutorial/tutorial_catalog.dart';
import '../../domain/project/commands/create_group_command.dart';
import '../../domain/project/commands/move_entity_command.dart';
import '../../domain/project/commands/remove_entity_command.dart';
import '../../domain/project/commands/reorder_child_command.dart';
import '../../domain/project/commands/update_entity_payload_command.dart';
import '../../domain/project/delete_impact.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/name_slug.dart';
import '../../domain/project/project_command.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_group.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/project/registry_node.dart';
import '../bridge/patcher_gateway.dart';
import 'patch_bus_option.dart';
import 'patch_clipboard.dart';
import 'patch_reconciler.dart';
import 'patch_tree_node.dart';
import 'patcher_controller.dart';
import 'tutorial/patch_tutorial_session.dart';
import 'tutorial/patch_tutorial_source.dart';

/// The seam the patcher entity strip (issue #224) binds to — the bridge between
/// the `patch.` registry namespace, the [PatchReconciler]'s per-entity native
/// patchers, and the [PatchLibrary] command factory (design
/// `docs/design/patcher.md` §3, §4, §8).
///
/// A [ChangeNotifier], so the strip rebuilds on every change it drives: the tree
/// re-renders when the registry mutates (it listens to it), **opening** a patch
/// swaps the edited [openEditor], and placement / running state moves. Every
/// structural edit goes through the ordinary journaled command layer — a
/// create-entity command via [PatchLibrary] for new / duplicate patches,
/// [CreateGroupCommand] for groups, [MoveEntityCommand] for rename (= refactor)
/// and drag-to-regroup, [ReorderChildCommand] for in-section reorder,
/// [RemoveEntityCommand] for delete, [UpdateEntityPayloadCommand] for a placement
/// change — applied and recorded through [recordCommand] so it dirties + journals
/// like any other project change.
///
/// **One open patcher at a time (v1).** [open] binds a cached [PatcherController]
/// editor to the reconciler's live instance for that entity (the surface edits
/// the *same* native patcher the reconciler mounts). The editor does **not** own
/// the instance — the reconciler does — so switching patches leaks nothing: the
/// cached editors are disposed only when their entity is deleted or the whole
/// controller is disposed, and disposing one never touches the reconciler's
/// native patcher.
///
/// **Tutorials (issue #489).** Beside the project's patches it can show one
/// bundled tutorial at a time ([openTutorial]): a [PatchTutorialSession] — a
/// transient native patcher that is *not* a registry entity — whose editor
/// [openEditor] answers while it is open, so the surface renders it like any
/// patch. Nothing about it is journaled or saved; [copyTutorialToProject]
/// mints an ordinary `patch.tutorials.<slug>` entity from it. Opening a project
/// patch, a rebind, a session restart and [dispose] all close it.
///
/// It owns neither the [registry] (the project controller does) nor the
/// reconciler (the engine does); it only listens to the registry and drives the
/// reconciler, so [dispose] detaches the listener and disposes its own editors.
class PatchLibraryController extends ChangeNotifier {
  PatchLibraryController({
    required ProjectRegistry registry,
    required this._patches,
    required this._gateway,
    required this._busOptions,
    this._recordCommand,
    this._tutorialSource,
  }) : _registry = registry {
    _library = PatchLibrary(registry);
    _registry.addListener(_onRegistryChanged);
  }

  final PatcherGateway _gateway;
  ProjectRegistry _registry;
  PatchReconciler _patches;
  List<PatchBusOption> Function() _busOptions;
  void Function(ProjectCommand)? _recordCommand;
  late PatchLibrary _library;

  /// One editor per opened patch, bound to the reconciler's live instance and
  /// kept alive across switches so a re-open shows the same live graph.
  final Map<EntityAddress, PatcherController> _editors = {};

  /// One copy buffer shared by every editor this controller binds (issue
  /// #435), so a fragment copied in one patch pastes into another — and the
  /// copy survives switching patches. Deliberately kept across [rebind]: what
  /// was copied is the performer's, not the project's.
  final PatchClipboard _clipboard = PatchClipboard();
  EntityAddress? _openAddress;

  final PatchTutorialSource? _tutorialSource;
  TutorialCatalog _tutorials = TutorialCatalog.empty;
  final Map<String, PatchTutorial> _tutorialCache = {};
  PatchTutorialSession? _tutorial;
  bool _disposed = false;

  /// Bumped by [requestTutorialBrowser] — the surface listens and switches its
  /// palette to the Tutorials tab (the "Open Patcher Tutorial…" command).
  final ValueNotifier<int> tutorialBrowserRequests = ValueNotifier(0);

  /// The registry whose `patch.` namespace this strip shows.
  ProjectRegistry get registry => _registry;

  /// The address of the patch currently open in the editor, or `null` when none
  /// is open (an empty `patch.` namespace).
  EntityAddress? get openAddress => _openAddress;

  /// The editor driving the currently-open patch, or `null` when none is open.
  /// Bound to the reconciler's live instance for [openAddress].
  ///
  /// While a tutorial is open ([tutorial]), this is the tutorial's editor.
  PatcherController? get openEditor =>
      _tutorial?.editor ??
      (_openAddress == null ? null : _editors[_openAddress]);

  /// Re-point the controller at a fresh [registry] (a project New / Open swaps
  /// the instance) and refresh the injected seams. Disposes the old editors
  /// (their reconciler instances are torn down by the engine's project swap),
  /// rebuilds the [PatchLibrary], and notifies so the strip re-renders. Idempotent
  /// when [registry] is already bound (it only refreshes the seams).
  void rebind({
    required ProjectRegistry registry,
    PatchReconciler? patches,
    List<PatchBusOption> Function()? busOptions,
    void Function(ProjectCommand)? recordCommand,
  }) {
    if (busOptions != null) _busOptions = busOptions;
    if (patches != null) _patches = patches;
    _recordCommand = recordCommand;
    if (identical(registry, _registry)) return;
    _closeTutorial();
    _registry.removeListener(_onRegistryChanged);
    _disposeEditors();
    _openAddress = null;
    _registry = registry;
    _library = PatchLibrary(registry);
    _registry.addListener(_onRegistryChanged);
    notifyListeners();
  }

  void _onRegistryChanged() => notifyListeners();

  // ─── tree ─────────────────────────────────────────────────────────────────

  /// The `patch.` namespace as an ordered forest of [PatchTreeNode]s — groups
  /// nesting their children, in the registry's child order.
  List<PatchTreeNode> get tree =>
      _nodesOf(_registry.childrenOfKind(RegistryKinds.patch), const []);

  List<PatchTreeNode> _nodesOf(List<RegistryNode> nodes, List<String> prefix) {
    final result = <PatchTreeNode>[];
    for (final node in nodes) {
      final address = EntityAddress(
        kind: RegistryKinds.patch,
        segments: [...prefix, node.name],
      );
      if (node is RegistryGroup) {
        result.add(
          PatchTreeNode(
            address: address,
            isGroup: true,
            children: _nodesOf(node.children.toList(), [...prefix, node.name]),
          ),
        );
      } else {
        result.add(PatchTreeNode(address: address, isGroup: false));
      }
    }
    return result;
  }

  /// Whether the tree carries no patches or groups yet.
  bool get isEmpty => _registry.childrenOfKind(RegistryKinds.patch).isEmpty;

  // ─── open / switch ──────────────────────────────────────────────────────────

  /// Open the patch at [address] in the editor — its live native instance
  /// becomes the edited one (v1: one at a time). A no-op when [address] is not a
  /// patch entity or the reconciler could not materialise it. Notifies so the
  /// strip highlight and the canvas both follow.
  ///
  /// Closes an open tutorial — picking a project patch leaves it.
  void open(EntityAddress address) {
    if (_registry.entityAt(address) == null) return;
    _closeTutorial();
    _patches.sync(_registry); // ensure the native instance exists
    final instanceId = _patches.instanceIdOf(address);
    if (instanceId == null) return;
    _openAddress = address;
    _editors.putIfAbsent(
      address,
      // A freshly-bound editor mirrors an empty graph; rebuild it from the live
      // native instance so a patch loaded from disk (or re-materialised by a
      // rename) shows its graph rather than a blank canvas (issue #308).
      // A freshly-bound editor mirrors an empty graph; rebuild it from the live
      // native instance so a patch loaded from disk (or re-materialised by a
      // rename) shows its graph rather than a blank canvas (issue #308).
      () => PatcherController.bound(
        _gateway,
        instanceId: instanceId,
        clipboard: _clipboard,
      )..rebuildFromInstance(),
    );
    notifyListeners();
  }

  /// Drop every cached editor — each is bound to a native instance an engine
  /// session restart is about to free (issue #448). The open address is kept,
  /// so [reopen] binds a fresh editor to the same patch once the reconciler
  /// has re-materialised it.
  /// An open tutorial is closed too: its native patcher goes with the session.
  void releaseEditors() {
    _closeTutorial();
    _disposeEditors();
  }

  /// Re-open the patch that was open before [releaseEditors] on its freshly
  /// materialised instance (issue #448) — the first patch when that one is
  /// gone — and notify, so the canvas rebinds to the new editor.
  void reopen() {
    final address = _openAddress;
    _openAddress = null;
    if (address != null) open(address);
    if (_openAddress == null) openFirst();
    notifyListeners();
  }

  /// Open the first patch entity in the tree, if any — the engine's start-up /
  /// project-swap hook so the surface always shows a patch when one exists.
  void openFirst() {
    final first = _firstPatchAddress();
    if (first != null) open(first);
  }

  // ─── context-menu commands ──────────────────────────────────────────────────

  /// Create an **empty** patch under [group] (top-level when null) and open it.
  /// Returns the new patch's address.
  EntityAddress? newPatch({EntityAddress? group}) {
    final command = _library.newPatch(group: group);
    _apply(command);
    open(command.address);
    return command.address;
  }

  /// Create an empty group folder under [group] (top-level when null). Returns
  /// the new group's address.
  EntityAddress newGroup({EntityAddress? group}) {
    final address = _freshUnder(
      group?.segments ?? const [],
      NameSlug.of('group', fallback: 'group'),
    );
    _apply(CreateGroupCommand(_registry, address));
    return address;
  }

  /// Duplicate the whole patch at [source] to `<name>_copy` beside it (dump +
  /// placement), then open the copy. A no-op when [source] is not a patch entity.
  /// Flushes the source's live dump first when it is open, so the copy reflects
  /// unsaved edits.
  EntityAddress? duplicate(EntityAddress source) {
    if (_registry.entityAt(source) == null) return null;
    if (_editors.containsKey(source)) {
      _patches.flushToPayloads(_registry, _recordCommand);
    }
    final command = _library.duplicate(source);
    _apply(command);
    open(command.address);
    return command.address;
  }

  /// Rename the patch or group at [address] to [newName] — a registry move, so
  /// the address follows the name and every referent is rewritten (rename =
  /// refactor, design §3). A no-op for a blank name or one whose slug is
  /// unchanged.
  ///
  /// The reconciler re-materialises the moved entity under its new address, so
  /// the open patch's live dump is **flushed first** to carry its current graph
  /// across the move; the renamed patch is then re-opened at its new address.
  void rename(EntityAddress address, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final slug = NameSlug.of(trimmed, fallback: 'patch');
    if (slug == address.name) return;
    final to = _freshUnder(address.groupPath, slug);
    final wasOpen = _openAddress == address;
    if (_editors.containsKey(address)) {
      _patches.flushToPayloads(_registry, _recordCommand);
    }
    _apply(MoveEntityCommand(_registry, address, to));
    _patches.sync(_registry);
    _dropEditorsUnder(address);
    if (wasOpen) {
      _openAddress = null;
      open(to);
    }
    notifyListeners();
  }

  /// What deleting the node at [address] would strand — the referents left
  /// dangling (design §4). The strip raises the delete-impact dialog when this
  /// [DeleteImpact.hasReferrers].
  DeleteImpact impactOf(EntityAddress address) =>
      _registry.impactOfRemoving(address);

  /// Remove the patch or group at [address] (a group takes its subtree). Stops
  /// any running source at or beneath it, drops its editors, then records the
  /// removal — and opens another patch when the open one went away.
  void delete(EntityAddress address) {
    for (final open in _patches.openPatches.toList()) {
      if (open == address || open.isDescendantOf(address)) _patches.stop(open);
    }
    final closedOpen =
        _openAddress != null &&
        (_openAddress == address || _openAddress!.isDescendantOf(address));
    _apply(RemoveEntityCommand(_registry, address));
    _patches.sync(_registry); // tears down the removed entities' instances
    _dropEditorsUnder(address);
    if (closedOpen) {
      _openAddress = null;
      openFirst();
    }
    notifyListeners();
  }

  // ─── drag: regroup + reorder ────────────────────────────────────────────────

  /// Re-parent the node at [address] under [targetGroup] (top-level when null) —
  /// the drag-into / drag-out-of-a-group gesture. A registry move rewrites the
  /// address to follow the tree. A no-op when it is already directly under
  /// [targetGroup], or when a group is dropped into its own subtree. The open
  /// patch is re-opened at its new address.
  void regroup(EntityAddress address, EntityAddress? targetGroup) {
    if (targetGroup == address) return;
    final parentSegments = targetGroup?.segments ?? const <String>[];
    if (_sameSegments(address.groupPath, parentSegments)) return;
    if (targetGroup != null && targetGroup.isDescendantOf(address)) return;
    final to = _freshUnder(parentSegments, address.name);
    final wasOpen = _openAddress == address;
    if (_editors.containsKey(address)) {
      _patches.flushToPayloads(_registry, _recordCommand);
    }
    _apply(MoveEntityCommand(_registry, address, to));
    _patches.sync(_registry);
    _dropEditorsUnder(address);
    if (wasOpen) {
      _openAddress = null;
      open(to);
    }
    notifyListeners();
  }

  /// Reorder the node at [address] to sit immediately before [before] among
  /// their shared siblings — the drag-to-reorder-within-a-section gesture. A
  /// no-op unless the two currently share a parent (a cross-group drop is a
  /// [regroup] instead).
  void reorderBefore(EntityAddress address, EntityAddress before) {
    if (address == before || address.parent != before.parent) return;
    final group = address.parent;
    final siblings = group == null
        ? _registry.childrenOfKind(RegistryKinds.patch)
        : _registry.childrenOfGroup(group);
    final names = siblings.map((n) => n.name).toList();
    final fromIndex = names.indexOf(address.name);
    final targetIndex = names.indexOf(before.name);
    if (fromIndex < 0 || targetIndex < 0) return;
    final toIndex = fromIndex < targetIndex ? targetIndex - 1 : targetIndex;
    if (toIndex == fromIndex) return;
    _apply(
      ReorderChildCommand(
        _registry,
        kind: RegistryKinds.patch,
        group: group,
        childName: address.name,
        fromIndex: fromIndex,
        toIndex: toIndex,
      ),
    );
  }

  // ─── source placement ────────────────────────────────────────────────────────

  /// The placeable mix buses offered in the placement picker — master, user
  /// strips, group buses, returns (design §4 role 1).
  List<PatchBusOption> busOptions() => _busOptions();

  /// The source-placement bus the patch at [address] currently carries, or
  /// `null` when it is unplaced / not open.
  EntityAddress? placementOf(EntityAddress address) =>
      _patches.placementOf(address);

  /// Whether the patch at [address] is currently mounted + sounding as a source.
  bool isRunning(EntityAddress address) => _patches.isRunning(address);

  /// Place the patch at [address] onto [bus] (or unplace it when `null`) —
  /// records the placement in the payload so it persists (design §4, §8), then
  /// re-syncs the reconciler so a running source follows the new bus.
  void place(EntityAddress address, EntityAddress? bus) {
    final entity = _registry.entityAt(address);
    if (entity == null) return;
    final current = _payloadOf(entity.payload);
    final next = current.withPlacement(bus);
    if (next == current) return;
    _apply(UpdateEntityPayloadCommand(_registry, address, next.toJson()));
    _patches.sync(_registry);
    notifyListeners();
  }

  /// Clear the source placement of the patch at [address].
  void unplace(EntityAddress address) => place(address, null);

  /// Start the patch at [address] as a source — mount it on its placement bus and
  /// begin sounding (design §4 role 1). Returns whether it started; a no-op when
  /// it is unplaced or its placement bus is stale (which surfaces a notice through
  /// the engine).
  bool start(EntityAddress address) {
    final started = _patches.start(address);
    notifyListeners();
    return started;
  }

  /// Stop the source at [address] — unmount it, silencing it.
  void stop(EntityAddress address) {
    _patches.stop(address);
    notifyListeners();
  }

  // ─── tutorials (issue #489) ─────────────────────────────────────────────────

  /// The bundled tutorial index — [TutorialCatalog.empty] until
  /// [loadTutorials] has read it (or when there is no source).
  TutorialCatalog get tutorials => _tutorials;

  /// Whether the object [type] has a bundled tutorial.
  bool hasTutorial(String type) => _tutorials.hasTutorial(type);

  /// The tutorial open in the editor, or null when a project patch is shown.
  PatchTutorialSession? get tutorial => _tutorial;

  /// Read the tutorial index from the source. A missing or unreadable index
  /// leaves the catalog empty (no tutorial buttons), never fails the app.
  Future<void> loadTutorials() async {
    final source = _tutorialSource;
    if (source == null) return;
    TutorialCatalog catalog;
    try {
      final text = await source.read(TutorialCatalog.indexPath);
      final decoded = text == null ? null : jsonDecode(text);
      catalog = decoded is Map
          ? TutorialCatalog.fromJson(decoded.cast<String, Object?>())
          : TutorialCatalog.empty;
    } on FormatException {
      catalog = TutorialCatalog.empty;
    }
    if (_disposed) return;
    _tutorials = catalog;
    notifyListeners();
  }

  /// Load (and cache) the tutorial stored under [slug], or null when the file
  /// is missing or malformed.
  Future<PatchTutorial?> loadTutorial(String slug) async {
    final cached = _tutorialCache[slug];
    if (cached != null) return cached;
    final source = _tutorialSource;
    if (source == null) return null;
    try {
      final text = await source.read(TutorialCatalog.assetPathFor(slug));
      if (text == null) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final tutorial = PatchTutorial.fromJson(decoded.cast<String, Object?>());
      return _tutorialCache[slug] = tutorial;
    } on FormatException {
      return null;
    }
  }

  /// Open the tutorial for the object [type] in the editor, replacing any
  /// tutorial already open. Returns whether one opened (false when [type] has
  /// none or its file cannot be read).
  Future<bool> openTutorial(String type) async {
    final slug = _tutorials.tutorialFor(type);
    if (slug == null) return false;
    final tutorial = await loadTutorial(slug);
    if (tutorial == null || _disposed) return false;
    _closeTutorial();
    _tutorial = PatchTutorialSession.open(
      _gateway,
      tutorial: tutorial,
      slug: slug,
      clipboard: _clipboard,
    );
    notifyListeners();
    return true;
  }

  /// Close the open tutorial — the editor returns to the project patch that
  /// was open before. A no-op when none is open.
  void closeTutorial() {
    if (_tutorial == null) return;
    _closeTutorial();
    notifyListeners();
  }

  /// Copy the open tutorial into the project as an ordinary, editable patch at
  /// `patch.tutorials.<slug>` — journaled and undoable like a new patch — then
  /// close the tutorial and open the copy. Returns the copy's address, or null
  /// when no tutorial is open.
  EntityAddress? copyTutorialToProject() {
    final session = _tutorial;
    if (session == null) return null;
    final command = _library.fromTutorial(session.tutorial, slug: session.slug);
    _apply(command);
    open(command.address); // closes the tutorial
    return command.address;
  }

  /// Ask the surface to show the Tutorials browser.
  void requestTutorialBrowser() => tutorialBrowserRequests.value++;

  /// The open **project** patch written in the tutorial file format — the
  /// dev-facing "Export Patch as Tutorial…" authoring path. Title is the patch
  /// name and `covers` is left empty for the author to fill in. Null when no
  /// project patch is open (or a tutorial is showing).
  String? exportOpenAsTutorial() {
    final address = _openAddress;
    final editor = address == null ? null : _editors[address];
    if (address == null || editor == null || _tutorial != null) return null;
    final entity = _registry.entityAt(address);
    final current = _payloadOf(entity?.payload);
    final text = _gateway.dumpJson(editor.instanceId);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    final tutorial = PatchTutorial(
      title: address.name,
      covers: const [],
      payload: current.withDump(
        decoded is Map ? decoded.cast<String, Object?>() : const {},
      ),
    );
    return const JsonEncoder.withIndent('  ').convert(tutorial.toJson());
  }

  void _closeTutorial() {
    _tutorial?.dispose();
    _tutorial = null;
  }

  // ─── helpers ────────────────────────────────────────────────────────────────

  PatchPayload _payloadOf(Object? payload) {
    if (payload is PatchPayload) return payload;
    if (payload is Map) {
      return PatchPayload.fromJson(payload.cast<String, Object?>());
    }
    return PatchPayload.empty;
  }

  /// The address of the first top-level `patch.` **entity** (skipping groups), or
  /// `null` when none exists.
  EntityAddress? _firstPatchAddress() {
    for (final node in _registry.childrenOfKind(RegistryKinds.patch)) {
      if (node is! RegistryGroup) {
        return EntityAddress(kind: RegistryKinds.patch, segments: [node.name]);
      }
    }
    return null;
  }

  /// A free `patch.` address for [leaf] directly under [parentSegments] (empty =
  /// top level), suffixed until unused.
  EntityAddress _freshUnder(List<String> parentSegments, String leaf) {
    EntityAddress at(String name) => EntityAddress(
      kind: RegistryKinds.patch,
      segments: [...parentSegments, name],
    );
    var segment = leaf;
    var n = 2;
    while (_registry.contains(at(segment))) {
      segment = '${leaf}_$n';
      n++;
    }
    return at(segment);
  }

  /// Dispose and forget every cached editor at or beneath [address] — called
  /// after a rename / regroup / delete re-keys or removes those entities.
  void _dropEditorsUnder(EntityAddress address) {
    for (final key in _editors.keys.toList()) {
      if (key == address || key.isDescendantOf(address)) {
        _editors.remove(key)?.dispose();
      }
    }
  }

  void _disposeEditors() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _editors.clear();
  }

  /// Apply a structural [command] and record it through [recordCommand] for
  /// dirty-tracking + journaling — the same path the clip library uses.
  void _apply(ProjectCommand command) {
    command.apply();
    _recordCommand?.call(command);
  }

  static bool _sameSegments(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _closeTutorial();
    tutorialBrowserRequests.dispose();
    _registry.removeListener(_onRegistryChanged);
    _disposeEditors();
    super.dispose();
  }
}
