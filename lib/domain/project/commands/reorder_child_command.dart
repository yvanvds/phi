import '../entity_address.dart';
import '../project_command.dart';
import '../project_registry.dart';

/// Reorders a child within its parent group (or the kind root) to a new
/// position among its siblings — the `_group.json` order a Mix-surface section
/// reorder writes (design `docs/design/mix.md` §7).
///
/// [apply] moves the child to [toIndex]; [revert] restores it to [fromIndex]
/// (its position before the reorder), so undo round-trips. A reorder shifts no
/// address, so [entitiesTouched] carries just the reordered child's address —
/// enough to mark the project dirty; the child order itself persists through the
/// controller's `_group.json` capture on save.
class ReorderChildCommand implements ProjectCommand {
  ReorderChildCommand(
    this.registry, {
    required this.kind,
    required this.group,
    required this.childName,
    required this.fromIndex,
    required this.toIndex,
  });

  final ProjectRegistry registry;

  /// The namespace the reorder happens in (`mix`, …).
  final String kind;

  /// The parent group whose children are reordered, or `null` for the kind root
  /// (a top-level reorder).
  final EntityAddress? group;

  /// The leaf name of the reordered child.
  final String childName;

  /// The child's index before the reorder — the target [revert] restores.
  final int fromIndex;

  /// The child's index after the reorder — the target [apply] moves it to.
  final int toIndex;

  EntityAddress get _childAddress => group == null
      ? EntityAddress(kind: kind, segments: [childName])
      : group!.child(childName);

  @override
  String get label => 'reorder $childName';

  @override
  Set<EntityAddress> get entitiesTouched => {_childAddress};

  @override
  void apply() => registry.reorderChild(
    kind: kind,
    group: group,
    childName: childName,
    index: toIndex,
  );

  @override
  void revert() => registry.reorderChild(
    kind: kind,
    group: group,
    childName: childName,
    index: fromIndex,
  );

  @override
  Map<String, Object?> toJson() => {
    'type': 'reorder_child',
    'kind': kind,
    if (group != null) 'group': group!.format(),
    'child': childName,
    'from': fromIndex,
    'to': toIndex,
  };
}
