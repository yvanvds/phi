import '../entity_address.dart';
import 'project_snapshot.dart';

/// The persistence seam for a `.phi` project folder (design
/// `docs/design/project-registry.md` §5, §8) — the same Real/Fake split as
/// `YseGateway`.
///
/// `RealProjectStore` (`dart:io`) reads and writes an actual folder;
/// `FakeProjectStore` keeps the same bytes in memory for tests. Callers depend on
/// this interface, so the registry, the lifecycle UI (a later epic issue) and the
/// tests never touch the filesystem directly.
///
/// A store is bound to one project location. It writes the manifest and one
/// pretty-printed JSON file per entity (folders are groups; the file path mirrors
/// the entity's address), plus an optional `_group.json` per group and an
/// `assets/` folder for binaries.
abstract interface class ProjectStore {
  /// Whether a project already lives at this location — i.e. its `project.json`
  /// manifest is present.
  Future<bool> exists();

  /// Persists [snapshot] to the folder.
  ///
  /// With [dirty] `null` this is a full save: every entity is (re)written and
  /// anything the registry no longer holds is pruned. With [dirty] non-null only
  /// those addresses are touched — each still in the registry is rewritten, each
  /// now absent has its file (and, for a removed group, its subtree) deleted.
  /// This is the seam the command layer's `entitiesTouched` drives, so autosave
  /// rewrites exactly the entities that changed. The manifest is always written
  /// (it is tiny and holds project-wide state).
  Future<void> save(ProjectSnapshot snapshot, {Set<EntityAddress>? dirty});

  /// Reads the folder back into a fresh [ProjectSnapshot] — a new registry,
  /// the manifest, and any `_group.json` metadata.
  Future<ProjectSnapshot> load();
}
