import '../entity_address.dart';
import '../project_registry.dart';
import 'group_metadata.dart';
import 'project_manifest.dart';

/// Everything a `.phi` folder round-trips: the [manifest], the whole entity/group
/// tree ([registry]), and the optional cosmetic [groupMetadata] that backs each
/// `_group.json` (design `docs/design/project-registry.md` §5).
///
/// The registry is the source of truth for structure; group metadata lives
/// *beside* it (keyed by the group's [EntityAddress]) rather than inside it,
/// because ordering and colour are cosmetic and the registry core stays
/// metadata-free. A [ProjectStore.load] hands one of these back; a
/// [ProjectStore.save] consumes one.
///
/// Only groups that carry something worth persisting appear in [groupMetadata];
/// a group absent from the map (or mapped to an empty [GroupMetadata]) simply has
/// no `_group.json`. The kind roots are not addressable, so their child order is
/// not persisted — top-level entities load alphabetically.
class ProjectSnapshot {
  /// Bundles the [manifest], the [registry] tree, and optional [groupMetadata].
  ProjectSnapshot({
    required this.manifest,
    required this.registry,
    this.groupMetadata = const {},
  });

  /// Project-wide state (format version, name, tempo, scene name).
  final ProjectManifest manifest;

  /// The in-memory tree of every group and entity.
  final ProjectRegistry registry;

  /// Cosmetic per-group metadata, keyed by the group's address. May be empty.
  final Map<EntityAddress, GroupMetadata> groupMetadata;
}
