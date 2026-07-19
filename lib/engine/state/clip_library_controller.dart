import 'package:flutter/foundation.dart';

import '../../domain/midi/library/clip_library.dart';
import '../../domain/midi/store/clip_document.dart';
import '../../domain/midi/store/midi_transform_codec.dart';
import '../../domain/project/commands/create_group_command.dart';
import '../../domain/project/commands/move_entity_command.dart';
import '../../domain/project/commands/remove_entity_command.dart';
import '../../domain/project/commands/reorder_child_command.dart';
import '../../domain/project/delete_impact.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/name_slug.dart';
import '../../domain/project/project_command.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_group.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/project/registry_node.dart';
import 'clip_tree_node.dart';
import 'engine_midi_controller.dart';

/// The seam the MIDI library panel (issue #188) binds to — the bridge between the
/// `clip.` registry namespace, the [EngineMidiController] session manager, and the
/// [ClipLibrary] command factory (design `docs/design/midi-clips.md` §3, §4).
///
/// A [ChangeNotifier], so the panel rebuilds on every change it drives: the tree
/// re-renders when the registry mutates (it listens to it), selection swaps the
/// edited session, and per-row / group play state moves. Every structural edit
/// goes through the ordinary journaled command layer — a create-entity command
/// via [ClipLibrary] for new / duplicate clips, [CreateGroupCommand] for groups,
/// [MoveEntityCommand] for rename (= refactor) and drag-to-regroup,
/// [ReorderChildCommand] for in-section reorder, [RemoveEntityCommand] for delete
/// — applied and recorded through [recordCommand] so it dirties + journals like
/// any other project change.
///
/// It owns neither the [registry] (the project controller does) nor the
/// [sessions] (the engine does): it only listens to the registry and drives the
/// session manager, so [dispose] just detaches the listener.
class ClipLibraryController extends ChangeNotifier {
  ClipLibraryController({
    required ProjectRegistry registry,
    required this.sessions,
    void Function(ProjectCommand)? recordCommand,
    MidiTransformCodec transformCodec = const MidiTransformCodec(),
  }) : _registry = registry,
       _recordCommand = recordCommand,
       _transformCodec = transformCodec {
    _library = ClipLibrary(registry, transformCodec: transformCodec);
    _registry.addListener(_onRegistryChanged);
  }

  /// The session manager the panel drives — selection opens a session, rows play
  /// / pause / stop / loop it, the header stops all.
  final EngineMidiController sessions;

  ProjectRegistry _registry;
  void Function(ProjectCommand)? _recordCommand;
  final MidiTransformCodec _transformCodec;
  late ClipLibrary _library;

  /// The registry whose `clip.` namespace this panel shows.
  ProjectRegistry get registry => _registry;

  /// Re-point the controller at a fresh [registry] (a project New / Open swaps the
  /// instance) and refresh the [recordCommand]. Detaches the old listener, rebuilds
  /// the [ClipLibrary] against the new registry, and notifies so the tree
  /// re-renders. Idempotent when [registry] is already bound.
  void rebind({
    required ProjectRegistry registry,
    void Function(ProjectCommand)? recordCommand,
  }) {
    if (identical(registry, _registry)) {
      _recordCommand = recordCommand;
      return;
    }
    _registry.removeListener(_onRegistryChanged);
    _registry = registry;
    _recordCommand = recordCommand;
    _library = ClipLibrary(registry, transformCodec: _transformCodec);
    _registry.addListener(_onRegistryChanged);
    notifyListeners();
  }

  void _onRegistryChanged() => notifyListeners();

  // ─── tree ─────────────────────────────────────────────────────────────────

  /// The `clip.` namespace as an ordered forest of [ClipTreeNode]s — groups
  /// nesting their children, in the registry's child order (mirroring the
  /// persisted `_group.json` order).
  List<ClipTreeNode> get tree =>
      _nodesOf(_registry.childrenOfKind(RegistryKinds.clip), const []);

  List<ClipTreeNode> _nodesOf(List<RegistryNode> nodes, List<String> prefix) {
    final result = <ClipTreeNode>[];
    for (final node in nodes) {
      final address = EntityAddress(
        kind: RegistryKinds.clip,
        segments: [...prefix, node.name],
      );
      if (node is RegistryGroup) {
        result.add(
          ClipTreeNode(
            address: address,
            isGroup: true,
            children: _nodesOf(node.children.toList(), [...prefix, node.name]),
          ),
        );
      } else {
        result.add(ClipTreeNode(address: address, isGroup: false));
      }
    }
    return result;
  }

  /// Whether the tree carries no clips or groups yet.
  bool get isEmpty => _registry.childrenOfKind(RegistryKinds.clip).isEmpty;

  // ─── selection (edited session) ─────────────────────────────────────────────

  /// The address of the clip currently open in the editor — the edited session's
  /// (`null` before any project clip is opened, i.e. the boot session).
  EntityAddress? get editedAddress => sessions.editedSession.address;

  /// Open the clip at [address] in the editor — its session becomes the edited
  /// one (design §3: selection opens the clip). A no-op when no clip entity with a
  /// decodable document sits there. Notifies so the panel highlight and the roll
  /// both follow.
  void select(EntityAddress address) {
    final document = _documentAt(address);
    if (document == null) return;
    sessions.openSession(address, document);
    notifyListeners();
  }

  // ─── context-menu commands ──────────────────────────────────────────────────

  /// Create an empty clip under [group] (top-level when null) and open it in the
  /// editor. Returns the new clip's address, or `null` when the command could not
  /// be built.
  EntityAddress? newClip({EntityAddress? group}) {
    final command = _library.newClip(group: group);
    _apply(command);
    select(command.address);
    return command.address;
  }

  /// Create an empty group folder under [group] (top-level when null). Returns the
  /// new group's address.
  EntityAddress newGroup({EntityAddress? group}) {
    final address = _freshAddress(
      group: group,
      desired: NameSlug.of('group', fallback: 'group'),
    );
    _apply(CreateGroupCommand(_registry, address));
    return address;
  }

  /// Duplicate the whole clip document at [source] to `<name>_copy` beside it, then
  /// open the copy. A no-op when [source] is not a clip entity.
  EntityAddress? duplicate(EntityAddress source) {
    if (_registry.entityAt(source) == null) return null;
    final command = _library.duplicate(source);
    _apply(command);
    select(command.address);
    return command.address;
  }

  /// Rename the clip or group at [address] to [newName] — a registry move, so the
  /// address follows the name and every referent is rewritten (rename = refactor,
  /// design §3). A no-op for a blank name or one whose slug is unchanged. When the
  /// renamed node is the edited clip, it is re-opened at its new address so the
  /// editor keeps tracking it.
  void rename(EntityAddress address, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final slug = NameSlug.of(trimmed, fallback: 'clip');
    if (slug == address.name) return;
    final to = _freshAddress(group: address.parent, desired: slug);
    final wasEdited = editedAddress == address;
    _apply(MoveEntityCommand(_registry, address, to));
    if (wasEdited) select(to);
  }

  /// What deleting the node at [address] would strand — the referents left
  /// dangling (design §4). The panel raises the delete-impact dialog when this
  /// [DeleteImpact.hasReferrers].
  DeleteImpact impactOf(EntityAddress address) =>
      _registry.impactOfRemoving(address);

  /// Remove the clip or group at [address] (a group takes its subtree). Stops any
  /// open session at or beneath it first so a removed clip is never left sounding,
  /// then records the removal.
  void delete(EntityAddress address) {
    sessions.stopSession(address);
    sessions.stopGroup(address);
    _apply(RemoveEntityCommand(_registry, address));
  }

  // ─── drag: regroup + reorder ────────────────────────────────────────────────

  /// Re-parent the node at [address] under [targetGroup] (top-level when null) —
  /// the drag-into / drag-out-of-a-group gesture (design §3). A registry move
  /// rewrites the address to follow the tree. A no-op when it is already directly
  /// under [targetGroup], or when a group is dropped into its own subtree. The
  /// edited clip is re-opened at its new address.
  void regroup(EntityAddress address, EntityAddress? targetGroup) {
    if (targetGroup == address) return;
    final parentSegments = targetGroup?.segments ?? const <String>[];
    if (_sameSegments(address.groupPath, parentSegments)) return;
    if (targetGroup != null && targetGroup.isDescendantOf(address)) return;
    final to = _freshUnder(parentSegments, address.name);
    final wasEdited = editedAddress == address;
    _apply(MoveEntityCommand(_registry, address, to));
    if (wasEdited) select(to);
  }

  /// Reorder the node at [address] to sit immediately before [before] among their
  /// shared siblings — the drag-to-reorder-within-a-section gesture (design §3).
  /// A no-op unless the two currently share a parent (a cross-group drop is a
  /// [regroup] instead).
  void reorderBefore(EntityAddress address, EntityAddress before) {
    if (address == before || address.parent != before.parent) return;
    final group = address.parent;
    final siblings = group == null
        ? _registry.childrenOfKind(RegistryKinds.clip)
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
        kind: RegistryKinds.clip,
        group: group,
        childName: address.name,
        fromIndex: fromIndex,
        toIndex: toIndex,
      ),
    );
  }

  // ─── play state ─────────────────────────────────────────────────────────────

  /// Whether the clip at [address] is currently playing.
  bool isPlaying(EntityAddress address) =>
      sessions.sessionFor(address)?.isPlaying ?? false;

  /// Whether the clip at [address] is currently paused.
  bool isPaused(EntityAddress address) =>
      sessions.sessionFor(address)?.isPaused ?? false;

  /// Whether any open clip beneath the group at [group] is playing — the group
  /// row's playing indicator.
  bool isGroupPlaying(EntityAddress group) {
    for (final address in _clipsUnder(group)) {
      if (isPlaying(address)) return true;
    }
    return false;
  }

  /// Whether the clip at [address] loops (its live session's flag when open, else
  /// the stored document's flag; on by default).
  bool loopOf(EntityAddress address) =>
      sessions.sessionFor(address)?.loop ??
      (_documentAt(address)?.loop ?? true);

  /// Start (or resume) the clip at [address], concurrently with any others — its
  /// session is opened (without disturbing the edited clip) if not already. A
  /// no-op when [address] has no decodable document.
  void playClip(EntityAddress address) {
    if (!_ensureOpen(address)) return;
    sessions.playSession(address);
    notifyListeners();
  }

  /// Pause the clip at [address] (freezing its clock, keeping its position).
  void pauseClip(EntityAddress address) {
    sessions.pauseSession(address);
    notifyListeners();
  }

  /// Stop the clip at [address] (clearing only its own scene agents).
  void stopClip(EntityAddress address) {
    sessions.stopSession(address);
    notifyListeners();
  }

  /// Toggle whether the clip at [address] loops. Opens its session if needed (loop
  /// is a per-session flag), then flips it live.
  void toggleLoop(EntityAddress address) {
    if (!_ensureOpen(address)) return;
    sessions.setSessionLoop(address, !loopOf(address));
    notifyListeners();
  }

  /// Play every clip beneath the group at [group] together (design §4,
  /// `clip.drums` → play all drums) — opening each first so a not-yet-touched clip
  /// still starts.
  void playGroup(EntityAddress group) {
    for (final address in _clipsUnder(group)) {
      _ensureOpen(address);
    }
    sessions.playGroup(group);
    notifyListeners();
  }

  /// Stop every open clip beneath the group at [group].
  void stopGroup(EntityAddress group) {
    sessions.stopGroup(group);
    notifyListeners();
  }

  /// Stop every session — the panel header's stop-all (design §4).
  void stopAll() {
    sessions.stopAll();
    notifyListeners();
  }

  // ─── helpers ────────────────────────────────────────────────────────────────

  /// Decode the [ClipDocument] stored at [address], or `null` when no clip entity
  /// with a document payload sits there.
  ClipDocument? _documentAt(EntityAddress address) {
    final payload = _registry.entityAt(address)?.payload;
    if (payload is ClipDocument) return payload;
    if (payload is Map) {
      return ClipDocument.fromJson(
        payload.cast<String, Object?>(),
        transformCodec: _transformCodec,
      );
    }
    return null;
  }

  /// Ensure a session exists for the clip at [address] without making it edited.
  /// Returns whether a session is now open there (`false` when there was no
  /// decodable document to build one from).
  bool _ensureOpen(EntityAddress address) {
    if (sessions.sessionFor(address) != null) return true;
    final document = _documentAt(address);
    if (document == null) return false;
    sessions.ensureSession(address, document);
    return true;
  }

  /// The addresses of every clip entity nested beneath the group at [group].
  List<EntityAddress> _clipsUnder(EntityAddress group) {
    final result = <EntityAddress>[];
    final node = _registry.groupAt(group);
    if (node != null) _collectClips(node, group, result);
    return result;
  }

  void _collectClips(
    RegistryGroup group,
    EntityAddress at,
    List<EntityAddress> out,
  ) {
    for (final child in group.children) {
      final childAt = at.child(child.name);
      if (child is RegistryGroup) {
        _collectClips(child, childAt, out);
      } else {
        out.add(childAt);
      }
    }
  }

  /// A free `clip.` address for [desired] under [group] (top-level when null),
  /// made unique among its siblings by suffixing `_2`, `_3`, …
  EntityAddress _freshAddress({
    required EntityAddress? group,
    required String desired,
  }) => _freshUnder(group?.segments ?? const [], desired);

  /// A free `clip.` address for [leaf] directly under [parentSegments] (empty =
  /// top level), suffixed until unused.
  EntityAddress _freshUnder(List<String> parentSegments, String leaf) {
    EntityAddress at(String name) => EntityAddress(
      kind: RegistryKinds.clip,
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
  /// dirty-tracking + journaling — the same path the Mix surface uses.
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
    _registry.removeListener(_onRegistryChanged);
    super.dispose();
  }
}
