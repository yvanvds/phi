import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/code/code_library.dart';
import '../../domain/code/code_script.dart';
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
import 'code_tree_node.dart';

/// The seam the Code surface's script library panel (issue #235) binds to — the
/// bridge between the `code.` registry namespace and the open editor (design
/// `docs/design/live-coding.md` §5).
///
/// A [ChangeNotifier], so the panel rebuilds on every change it drives: the tree
/// re-renders when the registry mutates (it listens to it), and selection swaps
/// the script open in the editor. Every structural edit goes through the ordinary
/// journaled command layer — a create-entity command via [CodeLibrary] for
/// new / duplicate scripts, [CreateGroupCommand] for groups,
/// [MoveEntityCommand] for rename (= refactor) and drag-to-regroup,
/// [ReorderChildCommand] for in-section reorder, [RemoveEntityCommand] for delete
/// — applied and recorded through [recordCommand] so it dirties + journals like
/// any other project change.
///
/// **Journaled edits, coalesced per idle pause.** Typing does not journal a
/// command per keystroke: [onEditorChanged] restarts an [idleDelay] timer and,
/// when the burst settles, publishes the whole source as one
/// [UpdateEntityPayloadCommand] (de-duped by content). Swapping scripts,
/// renaming, or disposing first [flushPendingEdits] into the *previously* open
/// script — the ordinary dirty-tracking guard against a lost edit, so no
/// separate unsaved-buffer concept is needed.
///
/// Evaluation is elsewhere and unaffected: what has been evaluated is
/// performance state and never touches the registry.
class CodeLibraryController extends ChangeNotifier {
  CodeLibraryController({
    required ProjectRegistry registry,
    void Function(ProjectCommand)? recordCommand,
    this.idleDelay = const Duration(milliseconds: 400),
  }) : _registry = registry,
       _recordCommand = recordCommand {
    _library = CodeLibrary(registry);
    _registry.addListener(_onRegistryChanged);
    _ensureOpenSelection();
  }

  /// The idle pause after which an edit burst is journaled as one command
  /// (design §5: "one command per idle pause, not per keystroke").
  final Duration idleDelay;

  ProjectRegistry _registry;
  void Function(ProjectCommand)? _recordCommand;
  late CodeLibrary _library;

  EntityAddress? _openAddress;
  String _openSource = '';

  /// Bumped whenever the editor should reload its text from [openSource] — on a
  /// selection swap, an open-script relocation, or a registry rebind. Never
  /// bumped by a journaled edit (that would fight the performer's cursor).
  int _openRevision = 0;

  Timer? _debounce;
  String? _pendingText;
  String? _lastPublished;

  /// True while the open script is being relocated (rename / regroup), so the
  /// mid-move registry notification — which momentarily sees the old address gone
  /// — doesn't re-home the editor onto a different script before we re-point it
  /// at the destination.
  bool _relocatingOpen = false;

  /// The registry whose `code.` namespace this panel shows.
  ProjectRegistry get registry => _registry;

  /// Re-point the controller at a fresh [registry] (a project New / Open swaps the
  /// instance) and refresh the [recordCommand]. Flushes any pending edit into the
  /// old registry first, rebuilds the [CodeLibrary], and re-opens the new
  /// registry's first script. Idempotent when [registry] is already bound.
  void rebind({
    required ProjectRegistry registry,
    void Function(ProjectCommand)? recordCommand,
  }) {
    if (identical(registry, _registry)) {
      _recordCommand = recordCommand;
      return;
    }
    flushPendingEdits();
    _registry.removeListener(_onRegistryChanged);
    _registry = registry;
    _recordCommand = recordCommand;
    _library = CodeLibrary(registry);
    _registry.addListener(_onRegistryChanged);
    _openAddress = null;
    _lastPublished = null;
    _ensureOpenSelection();
    notifyListeners();
  }

  void _onRegistryChanged() {
    // An external removal / undo that dropped the open script re-homes the editor
    // onto whatever script survives (or clears it), so it never tracks a ghost.
    // A deliberate relocation of the open script re-points it itself, so skip.
    if (!_relocatingOpen &&
        _openAddress != null &&
        !_registry.contains(_openAddress!)) {
      _ensureOpenSelection();
    }
    notifyListeners();
  }

  /// Re-point the open selection at [to] after a deliberate relocation (rename /
  /// regroup) of the open script, refreshing its source from the registry and
  /// bumping the revision so the editor follows.
  void _reopenAt(EntityAddress to) {
    _openAddress = to;
    _openSource = _scriptAt(to)?.source ?? _openSource;
    _lastPublished = _openSource;
    _openRevision++;
    notifyListeners();
  }

  // ─── tree ─────────────────────────────────────────────────────────────────

  /// The `code.` namespace as an ordered forest of [CodeTreeNode]s — groups
  /// nesting their children, in the registry's child order.
  List<CodeTreeNode> get tree =>
      _nodesOf(_registry.childrenOfKind(RegistryKinds.code), const []);

  List<CodeTreeNode> _nodesOf(List<RegistryNode> nodes, List<String> prefix) {
    final result = <CodeTreeNode>[];
    for (final node in nodes) {
      final address = EntityAddress(
        kind: RegistryKinds.code,
        segments: [...prefix, node.name],
      );
      if (node is RegistryGroup) {
        result.add(
          CodeTreeNode(
            address: address,
            isGroup: true,
            children: _nodesOf(node.children.toList(), [...prefix, node.name]),
          ),
        );
      } else {
        result.add(CodeTreeNode(address: address, isGroup: false));
      }
    }
    return result;
  }

  /// Whether the tree carries no scripts or groups yet.
  bool get isEmpty => _registry.childrenOfKind(RegistryKinds.code).isEmpty;

  // ─── selection (open script) ─────────────────────────────────────────────

  /// The address of the script currently open in the editor, or `null` when the
  /// `code.` namespace is empty.
  EntityAddress? get openAddress => _openAddress;

  /// The source text of the open script — what the editor loads on an
  /// [openRevision] change.
  String get openSource => _openSource;

  /// A monotone counter the surface watches: when it changes, the editor should
  /// reload its text from [openSource]. It moves only on a genuine swap, never on
  /// the performer's own edits.
  int get openRevision => _openRevision;

  /// Open the script at [address] in the editor (design §5: selection opens the
  /// script). Flushes any pending edit into the previously open script first
  /// (the dirty-tracking guard), then swaps. A no-op when [address] is already
  /// open or carries no decodable script payload.
  void select(EntityAddress address) {
    if (address == _openAddress) return;
    final script = _scriptAt(address);
    if (script == null) return;
    flushPendingEdits();
    _openAddress = address;
    _openSource = script.source;
    _lastPublished = script.source;
    _openRevision++;
    notifyListeners();
  }

  // ─── context-menu commands ──────────────────────────────────────────────────

  /// Create an empty script under [group] (top-level when null) and open it.
  /// Returns the new script's address.
  EntityAddress newScript({EntityAddress? group}) {
    final command = _library.newScript(group: group);
    _apply(command);
    select(command.address);
    return command.address;
  }

  /// Create an empty group folder under [group] (top-level when null). Returns
  /// the new group's address.
  EntityAddress newGroup({EntityAddress? group}) {
    final address = _freshAddress(
      group: group,
      desired: NameSlug.of('group', fallback: 'group'),
    );
    _apply(CreateGroupCommand(_registry, address));
    return address;
  }

  /// Duplicate the script at [source] to `<name>_copy` beside it, then open the
  /// copy. A no-op when [source] is not a script entity.
  EntityAddress? duplicate(EntityAddress source) {
    if (_registry.entityAt(source) == null) return null;
    final command = _library.duplicate(source);
    _apply(command);
    select(command.address);
    return command.address;
  }

  /// Rename the script or group at [address] to [newName] — a registry move, so
  /// the address follows the name and every referent is rewritten (rename =
  /// refactor). A no-op for a blank name or one whose slug is unchanged. When the
  /// renamed node is the open script it is re-opened at its new address so the
  /// editor keeps tracking it.
  void rename(EntityAddress address, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final slug = NameSlug.of(trimmed, fallback: 'script');
    if (slug == address.name) return;
    final to = _freshAddress(group: address.parent, desired: slug);
    _moveOpenAware(address, to);
  }

  /// What deleting the node at [address] would strand — the referents left
  /// dangling. The panel raises the delete-impact dialog when this
  /// [DeleteImpact.hasReferrers].
  DeleteImpact impactOf(EntityAddress address) =>
      _registry.impactOfRemoving(address);

  /// Remove the script or group at [address] (a group takes its subtree). Any
  /// pending edit to a *different* open script is flushed first so it is not
  /// lost; edits to a script being deleted are discarded. If the open script
  /// vanished, the editor re-homes onto whatever survives.
  void delete(EntityAddress address) {
    final removingOpen =
        _openAddress != null &&
        (_openAddress == address || _openAddress!.isDescendantOf(address));
    if (removingOpen) {
      _cancelDebounce();
    } else {
      flushPendingEdits();
    }
    _apply(RemoveEntityCommand(_registry, address));
  }

  // ─── drag: regroup + reorder ────────────────────────────────────────────────

  /// Re-parent the node at [address] under [targetGroup] (top-level when null).
  /// A registry move rewrites the address to follow the tree. A no-op when it is
  /// already directly under [targetGroup], or when a group is dropped into its
  /// own subtree. The open script is re-opened at its new address.
  void regroup(EntityAddress address, EntityAddress? targetGroup) {
    if (targetGroup == address) return;
    final parentSegments = targetGroup?.segments ?? const <String>[];
    if (_sameSegments(address.groupPath, parentSegments)) return;
    if (targetGroup != null && targetGroup.isDescendantOf(address)) return;
    final to = _freshUnder(parentSegments, address.name);
    _moveOpenAware(address, to);
  }

  /// Move the node at [from] to [to] as one journaled command. When [from] is the
  /// open script, its pending edit is flushed first and the editor re-points at
  /// [to] afterwards (guarded so the mid-move notification doesn't re-home it).
  void _moveOpenAware(EntityAddress from, EntityAddress to) {
    final wasOpen = _openAddress == from;
    if (!wasOpen) {
      _apply(MoveEntityCommand(_registry, from, to));
      return;
    }
    flushPendingEdits();
    _relocatingOpen = true;
    try {
      _apply(MoveEntityCommand(_registry, from, to));
    } finally {
      _relocatingOpen = false;
    }
    _reopenAt(to);
  }

  /// Reorder the node at [address] to sit immediately before [before] among
  /// their shared siblings. A no-op unless the two currently share a parent.
  void reorderBefore(EntityAddress address, EntityAddress before) {
    if (address == before || address.parent != before.parent) return;
    final group = address.parent;
    final siblings = group == null
        ? _registry.childrenOfKind(RegistryKinds.code)
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
        kind: RegistryKinds.code,
        group: group,
        childName: address.name,
        fromIndex: fromIndex,
        toIndex: toIndex,
      ),
    );
  }

  // ─── journaled edits ────────────────────────────────────────────────────────

  /// Note a live editor change to the open script. Restarts the [idleDelay]
  /// timer; the burst is journaled as one [UpdateEntityPayloadCommand] when it
  /// settles. A no-op when no script is open.
  void onEditorChanged(String text) {
    if (_openAddress == null) return;
    _pendingText = text;
    _debounce?.cancel();
    _debounce = Timer(idleDelay, () {
      _debounce = null;
      final pending = _pendingText;
      _pendingText = null;
      if (pending != null) _publish(pending);
    });
  }

  /// Publish any pending edit immediately (rather than waiting out the idle
  /// pause) — the guard called before a swap / rename / delete / dispose so a
  /// just-typed edit is never lost. A no-op when nothing is pending.
  void flushPendingEdits() {
    final pending = _pendingText;
    _cancelDebounce();
    if (pending != null) _publish(pending);
  }

  void _cancelDebounce() {
    _debounce?.cancel();
    _debounce = null;
    _pendingText = null;
  }

  void _publish(String text) {
    final address = _openAddress;
    if (address == null || !_registry.contains(address)) return;
    if (text == _lastPublished) return;
    _lastPublished = text;
    _openSource = text;
    final command = UpdateEntityPayloadCommand(
      _registry,
      address,
      CodeScript(source: text).toJson(),
    );
    command.apply();
    _recordCommand?.call(command);
  }

  // ─── helpers ────────────────────────────────────────────────────────────────

  /// The [CodeScript] stored at [address], or `null` when no script entity with
  /// a source payload sits there.
  CodeScript? _scriptAt(EntityAddress address) {
    final payload = _registry.entityAt(address)?.payload;
    if (payload is CodeScript) return payload;
    if (payload is Map) {
      return CodeScript.fromJson(payload.cast<String, Object?>());
    }
    return null;
  }

  /// Re-home the open selection when it is null or no longer present: onto the
  /// first script in the tree, or nothing when the namespace is empty. Bumps the
  /// revision so the editor reloads. Never journals — this is a view concern.
  void _ensureOpenSelection() {
    if (_openAddress != null && _registry.contains(_openAddress!)) return;
    final first = _firstScript();
    if (first != null) {
      _openAddress = first;
      _openSource = _scriptAt(first)?.source ?? '';
      _lastPublished = _openSource;
    } else {
      _openAddress = null;
      _openSource = '';
      _lastPublished = null;
    }
    _openRevision++;
  }

  /// The first script leaf in the tree, in pre-order (a group's own scripts
  /// before deeper ones), or `null` when there are none.
  EntityAddress? _firstScript() {
    for (final node in tree) {
      final found = _firstLeaf(node);
      if (found != null) return found;
    }
    return null;
  }

  EntityAddress? _firstLeaf(CodeTreeNode node) {
    if (!node.isGroup) return node.address;
    for (final child in node.children) {
      final found = _firstLeaf(child);
      if (found != null) return found;
    }
    return null;
  }

  /// A free `code.` address for [desired] under [group] (top-level when null),
  /// made unique among its siblings.
  EntityAddress _freshAddress({
    required EntityAddress? group,
    required String desired,
  }) => _freshUnder(group?.segments ?? const [], desired);

  /// A free `code.` address for [leaf] directly under [parentSegments] (empty =
  /// top level), suffixed until unused.
  EntityAddress _freshUnder(List<String> parentSegments, String leaf) {
    EntityAddress at(String name) => EntityAddress(
      kind: RegistryKinds.code,
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

  /// Apply a structural [command] and record it through [recordCommand] for
  /// dirty-tracking + journaling — the same path the Mix / clip surfaces use.
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
    _cancelDebounce();
    _registry.removeListener(_onRegistryChanged);
    super.dispose();
  }
}
