import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/fx/fx_definition.dart';
import '../../domain/fx/fx_kind.dart';
import '../../domain/project/commands/create_entity_command.dart';
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
import '../../domain/synth/fm_synth.dart';
import '../../domain/synth/sampler_synth.dart';
import '../../domain/synth/sine_synth.dart';
import '../../domain/synth/synth_definition.dart';
import '../../domain/synth/synth_kind.dart';
import '../../domain/synth/va_synth.dart';
import '../../domain/voice/voice_definition.dart';
import 'rack_tree_node.dart';
import 'rack_voice_row.dart';

/// The seam the racks **definitions panel** (issue #209) binds to — the bridge
/// between the `synth.` and `fx.` registry namespaces, the definition-editor
/// selection, and the journaled command layer (design
/// `docs/design/racks-and-voices.md` §8).
///
/// A [ChangeNotifier], so the panel + editor + voices pane rebuild on every
/// change it drives: each definition tree re-renders when the registry mutates
/// (it listens to it), [select] moves the editor pane's target, and creating /
/// renaming / deleting a definition threads through the ordinary journaled
/// command layer — [CreateEntityCommand] via [newSynth] / [newFx] / [duplicate],
/// [CreateGroupCommand] for groups, [MoveEntityCommand] for rename (= refactor)
/// and drag-to-regroup, [ReorderChildCommand] for in-section reorder, and
/// [RemoveEntityCommand] for delete — applied and recorded through
/// [recordCommand] so it dirties + journals like any other project change.
///
/// It owns neither the [registry] (the project controller does) nor any engine
/// state: it only listens to the registry and builds commands, so [dispose] just
/// detaches the listener. The center editor's per-kind panels and the voices
/// pane's editing land in later racks issues (#211, #212); here the panel is a
/// tree with full registry affordances, the editor is a routed placeholder, and
/// the voices pane renders read-only rows.
class RackDefinitionsController extends ChangeNotifier {
  RackDefinitionsController({
    required ProjectRegistry registry,
    void Function(ProjectCommand)? recordCommand,
  }) : _registry = registry,
       _recordCommand = recordCommand {
    _registry.addListener(_onRegistryChanged);
  }

  ProjectRegistry _registry;
  void Function(ProjectCommand)? _recordCommand;
  EntityAddress? _selected;

  /// The registry whose `synth.` / `fx.` / `voice.` namespaces this drives.
  ProjectRegistry get registry => _registry;

  /// Re-point the controller at a fresh [registry] (a project New / Open swaps the
  /// instance) and refresh the [recordCommand]. Detaches the old listener,
  /// attaches to the new registry, clears any now-stale selection, and notifies
  /// so the tree re-renders. Idempotent when [registry] is already bound.
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
    _selected = null;
    _registry.addListener(_onRegistryChanged);
    notifyListeners();
  }

  void _onRegistryChanged() => notifyListeners();

  // ─── trees ────────────────────────────────────────────────────────────────

  /// The `synth.` namespace as an ordered forest of [RackTreeNode]s — groups
  /// nesting their children, in the registry's child order.
  List<RackTreeNode> get synthTree => _treeOf(RegistryKinds.synth);

  /// The `fx.` namespace as an ordered forest of [RackTreeNode]s.
  List<RackTreeNode> get fxTree => _treeOf(RegistryKinds.fx);

  List<RackTreeNode> _treeOf(String kind) =>
      _nodesOf(_registry.childrenOfKind(kind), kind, const []);

  List<RackTreeNode> _nodesOf(
    List<RegistryNode> nodes,
    String kind,
    List<String> prefix,
  ) {
    final result = <RackTreeNode>[];
    for (final node in nodes) {
      final address = EntityAddress(
        kind: kind,
        segments: [...prefix, node.name],
      );
      if (node is RegistryGroup) {
        result.add(
          RackTreeNode(
            address: address,
            isGroup: true,
            children: _nodesOf(node.children.toList(), kind, [
              ...prefix,
              node.name,
            ]),
          ),
        );
      } else {
        result.add(
          RackTreeNode(
            address: address,
            isGroup: false,
            kindTag: kindTagAt(address),
          ),
        );
      }
    }
    return result;
  }

  // ─── selection (editor pane target) ─────────────────────────────────────────

  /// The address of the definition currently open in the center editor pane, or
  /// `null` when nothing is selected (the editor shows its empty hint).
  EntityAddress? get selected => _selected;

  /// Select the definition at [address] — it becomes the editor pane's target
  /// (design §8: selection drives the center editor). A no-op when no entity sits
  /// there. Notifies so the panel highlight and the editor both follow.
  void select(EntityAddress address) {
    if (_registry.entityAt(address) == null) return;
    if (_selected == address) return;
    _selected = address;
    notifyListeners();
  }

  /// The `kind` tag on the definition payload at [address] (`va`, `lowpass`, …),
  /// or `null` for a group or an entity with no readable kind — the editor pane
  /// and the tree leaves label themselves with it.
  String? kindTagAt(EntityAddress address) {
    final payload = _registry.entityAt(address)?.payload;
    if (payload is Map) return payload['kind'] as String?;
    return null;
  }

  // ─── editor decode / mutate (issue #210) ────────────────────────────────────

  /// The `synth.` definition at [address] decoded into its typed
  /// [SynthDefinition] (dispatched on the payload `kind`), or `null` when nothing
  /// synth-shaped sits there — the center editor reads this to build its panel.
  SynthDefinition? synthAt(EntityAddress address) {
    final payload = _registry.entityAt(address)?.payload;
    if (payload is SynthDefinition) return payload;
    if (payload is Map) {
      try {
        return SynthDefinition.fromJson(payload.cast<String, Object?>());
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// The `fx.` instance at [address] decoded into its typed [FxDefinition], or
  /// `null` when nothing fx-shaped sits there.
  FxDefinition? fxAt(EntityAddress address) {
    final payload = _registry.entityAt(address)?.payload;
    if (payload is FxDefinition) return payload;
    if (payload is Map) {
      try {
        return FxDefinition.fromJson(payload.cast<String, Object?>());
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// Write an edited synth [definition] to the entity at [address] as one
  /// journaled payload command (design §8: "all edits are journaled payload
  /// commands"). Continuous controls coalesce a whole drag into a single call —
  /// the editor commits once, on gesture end — so a slider sweep is one undoable
  /// edit, not dozens. A no-op when [address] holds no entity.
  void updateSynth(EntityAddress address, SynthDefinition definition) {
    if (_registry.entityAt(address) == null) return;
    _apply(UpdateEntityPayloadCommand(_registry, address, definition.toJson()));
  }

  /// Write an edited fx [definition] to the entity at [address] as one journaled
  /// payload command — the fx param rows' commit path. A no-op when [address]
  /// holds no entity.
  void updateFx(EntityAddress address, FxDefinition definition) {
    if (_registry.entityAt(address) == null) return;
    _apply(UpdateEntityPayloadCommand(_registry, address, definition.toJson()));
  }

  // ─── add ────────────────────────────────────────────────────────────────────

  /// Create a `synth.` definition of [kind] with sensible defaults under [group]
  /// (top-level when null), then select it. Returns its address.
  EntityAddress newSynth(SynthKind kind, {EntityAddress? group}) {
    final address = _freshAddress(
      kind: RegistryKinds.synth,
      group: group,
      desired: NameSlug.of(kind.name, fallback: 'synth'),
    );
    _apply(
      CreateEntityCommand(
        _registry,
        address,
        payload: _defaultSynth(kind).toJson(),
      ),
    );
    select(address);
    return address;
  }

  /// Create an `fx.` instance of [kind] with default (empty) params under [group]
  /// (top-level when null), then select it. Returns its address.
  EntityAddress newFx(FxKind kind, {EntityAddress? group}) {
    final address = _freshAddress(
      kind: RegistryKinds.fx,
      group: group,
      desired: NameSlug.of(kind.name, fallback: 'fx'),
    );
    _apply(
      CreateEntityCommand(
        _registry,
        address,
        payload: FxDefinition(kind: kind).toJson(),
      ),
    );
    select(address);
    return address;
  }

  /// Create an empty group folder in the [kind] namespace (`synth`/`fx`) under
  /// [group] (top-level when null). Returns the new group's address.
  EntityAddress newGroup(String kind, {EntityAddress? group}) {
    final address = _freshAddress(
      kind: kind,
      group: group,
      desired: NameSlug.of('group', fallback: 'group'),
    );
    _apply(CreateGroupCommand(_registry, address));
    return address;
  }

  /// Duplicate the definition at [source] to `<name>_copy` beside it (its payload
  /// copied verbatim), then select the copy. A no-op (returns `null`) when
  /// [source] is not a definition entity.
  EntityAddress? duplicate(EntityAddress source) {
    final entity = _registry.entityAt(source);
    if (entity == null) return null;
    final address = _freshUnder(
      source.kind,
      source.parent?.segments ?? const [],
      '${source.name}_copy',
    );
    _apply(
      CreateEntityCommand(
        _registry,
        address,
        payload: _clonePayload(entity.payload),
        references: Set.of(entity.references),
      ),
    );
    select(address);
    return address;
  }

  // ─── rename / delete ────────────────────────────────────────────────────────

  /// Rename the definition or group at [address] to [newName] — a registry move,
  /// so the address follows the name and every referent is rewritten (rename =
  /// refactor, design §8). A no-op for a blank name or one whose slug is
  /// unchanged. Keeps the selection on the renamed node at its new address.
  void rename(EntityAddress address, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final slug = NameSlug.of(trimmed, fallback: address.kind);
    if (slug == address.name) return;
    final to = _freshUnder(
      address.kind,
      address.parent?.segments ?? const [],
      slug,
    );
    final wasSelected = _selected == address;
    _apply(MoveEntityCommand(_registry, address, to));
    if (wasSelected) _selected = to;
  }

  /// What deleting the node at [address] would strand — the referents left
  /// dangling (design §8, e.g. a `voice.` that instantiates a deleted `synth.`,
  /// or a `mix.` bus whose `inserts` name a deleted `fx.`). The panel raises the
  /// delete-impact dialog when this [DeleteImpact.hasReferrers].
  DeleteImpact impactOf(EntityAddress address) =>
      _registry.impactOfRemoving(address);

  /// Remove the definition or group at [address] (a group takes its subtree),
  /// clearing the selection when it targeted the removed node (or its subtree).
  void delete(EntityAddress address) {
    if (_selected != null &&
        (_selected == address || _selected!.isDescendantOf(address))) {
      _selected = null;
    }
    _apply(RemoveEntityCommand(_registry, address));
  }

  // ─── drag: regroup + reorder ────────────────────────────────────────────────

  /// Re-parent the node at [address] under [targetGroup] (top-level when null) —
  /// the drag-into / drag-out-of-a-group gesture. A registry move rewrites the
  /// address to follow the tree. A no-op when it is already directly under
  /// [targetGroup], when the kinds differ (a synth can't move into an fx group),
  /// or when a group is dropped into its own subtree. Keeps the selection on the
  /// moved node.
  void regroup(EntityAddress address, EntityAddress? targetGroup) {
    if (targetGroup == address) return;
    if (targetGroup != null && targetGroup.kind != address.kind) return;
    final parentSegments = targetGroup?.segments ?? const <String>[];
    if (_sameSegments(address.groupPath, parentSegments)) return;
    if (targetGroup != null && targetGroup.isDescendantOf(address)) return;
    final to = _freshUnder(address.kind, parentSegments, address.name);
    final wasSelected = _selected == address;
    _apply(MoveEntityCommand(_registry, address, to));
    if (wasSelected) _selected = to;
  }

  /// Reorder the node at [address] to sit immediately before [before] among their
  /// shared siblings — the drag-to-reorder-within-a-section gesture. A no-op
  /// unless the two currently share a parent (a cross-group drop is a [regroup]).
  void reorderBefore(EntityAddress address, EntityAddress before) {
    if (address == before || address.parent != before.parent) return;
    final group = address.parent;
    final siblings = group == null
        ? _registry.childrenOfKind(address.kind)
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
        kind: address.kind,
        group: group,
        childName: address.name,
        fromIndex: fromIndex,
        toIndex: toIndex,
      ),
    );
  }

  // ─── voices (right pane scaffold) ────────────────────────────────────────────

  /// The `voice.` namespace as a flat, read-only list of [RackVoiceRow]s in
  /// registry order (top-level voices; groups are flattened depth-first). The
  /// voices pane renders these; binding / colour / kind editing lands in #211.
  List<RackVoiceRow> get voices {
    final rows = <RackVoiceRow>[];
    _collectVoices(
      _registry.childrenOfKind(RegistryKinds.voice),
      const [],
      rows,
    );
    return rows;
  }

  void _collectVoices(
    List<RegistryNode> nodes,
    List<String> prefix,
    List<RackVoiceRow> out,
  ) {
    for (final node in nodes) {
      final segments = [...prefix, node.name];
      if (node is RegistryGroup) {
        _collectVoices(node.children.toList(), segments, out);
        continue;
      }
      final address = EntityAddress(
        kind: RegistryKinds.voice,
        segments: segments,
      );
      final row = _voiceRowAt(address);
      if (row != null) out.add(row);
    }
  }

  RackVoiceRow? _voiceRowAt(EntityAddress address) {
    final payload = _registry.entityAt(address)?.payload;
    final VoiceDefinition definition;
    if (payload is VoiceDefinition) {
      definition = payload;
    } else if (payload is Map) {
      try {
        definition = VoiceDefinition.fromJson(payload.cast<String, Object?>());
      } on FormatException {
        return null;
      }
    } else {
      return null;
    }
    return RackVoiceRow(
      address: address,
      kind: definition.kind,
      synth: definition.synth,
      channel: definition.channel,
      output: definition.output,
      colorToken: definition.color,
    );
  }

  // ─── helpers ────────────────────────────────────────────────────────────────

  SynthDefinition _defaultSynth(SynthKind kind) {
    switch (kind) {
      case SynthKind.sine:
        return const SineSynth();
      case SynthKind.va:
        return const VaSynth();
      case SynthKind.fm:
        return const FmSynth();
      case SynthKind.sampler:
        return const SamplerSynth();
    }
  }

  /// A deep clone of a stored definition [payload] for a duplicate. Definition
  /// payloads are map-native (the journal contract), so a JSON round-trip is a
  /// full deep copy.
  Object _clonePayload(Object? payload) {
    if (payload is Map) {
      return (jsonDecode(jsonEncode(payload)) as Map).cast<String, Object?>();
    }
    if (payload is SynthDefinition) return payload.toJson();
    if (payload is FxDefinition) return payload.toJson();
    throw ArgumentError.value(
      payload,
      'payload',
      'definition entity has no payload to duplicate',
    );
  }

  /// A free [kind] address for [desired] under [group] (top-level when null),
  /// made unique among its siblings by suffixing `_2`, `_3`, …
  EntityAddress _freshAddress({
    required String kind,
    required EntityAddress? group,
    required String desired,
  }) => _freshUnder(kind, group?.segments ?? const [], desired);

  /// A free [kind] address for [leaf] directly under [parentSegments] (empty =
  /// top level), suffixed until unused.
  EntityAddress _freshUnder(
    String kind,
    List<String> parentSegments,
    String leaf,
  ) {
    EntityAddress at(String name) =>
        EntityAddress(kind: kind, segments: [...parentSegments, name]);
    var segment = leaf;
    var n = 2;
    while (_registry.contains(at(segment))) {
      segment = '${leaf}_$n';
      n++;
    }
    return at(segment);
  }

  /// Apply a structural [command] and record it through [recordCommand] for
  /// dirty-tracking + journaling — the same path the Mix and clip surfaces use.
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
