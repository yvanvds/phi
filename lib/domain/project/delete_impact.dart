import 'entity_address.dart';

/// What deleting a node would strand — the *delete warning* a surface shows
/// before it removes an entity or group (design
/// `docs/design/project-registry.md` §4).
///
/// [target] is the address about to be removed; [referrers] are the entities
/// **outside** that subtree which still point at [target] (or, for a group, at
/// anything inside it) and would be left with a dangling reference. Referents
/// that live inside the subtree are excluded — they disappear with it, so they
/// are not stranded. The list is sorted by address for a stable, readable
/// warning.
///
/// The registry produces this from its back-reference index; the delete itself
/// is a separate, deliberate step. An empty [referrers] ([isSafe]) means the
/// delete strands nothing and a surface may skip the warning.
class DeleteImpact {
  DeleteImpact(this.target, List<EntityAddress> referrers)
    : referrers = List.unmodifiable(referrers);

  /// The address that would be removed.
  final EntityAddress target;

  /// The external entities left pointing at [target] (or its subtree), sorted
  /// by address. Empty when nothing references it.
  final List<EntityAddress> referrers;

  /// Whether the delete strands no references — nothing points in from outside.
  bool get isSafe => referrers.isEmpty;

  /// Whether at least one external entity would be left dangling.
  bool get hasReferrers => referrers.isNotEmpty;
}
