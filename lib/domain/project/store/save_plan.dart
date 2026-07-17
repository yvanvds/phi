/// The filesystem-agnostic result of planning a save — *what* to change on
/// disk, computed purely by [ProjectSerializer] so the Real and Fake stores
/// share every byte of format logic and differ only in how they apply it.
///
/// A store applies a plan by writing each entry of [writes] (relative path →
/// pretty-printed JSON), removing each path in [deletes], and making sure each
/// directory in [ensureDirs] exists (the `assets/` folder, even when empty).
class SavePlan {
  /// Bundles the [writes], [deletes], and [ensureDirs] of one save.
  const SavePlan({
    required this.writes,
    required this.deletes,
    required this.ensureDirs,
  });

  /// Relative POSIX-style path → file contents to (over)write.
  final Map<String, String> writes;

  /// Relative POSIX-style paths to delete (removed entities/groups, and — on a
  /// full save — anything stale the registry no longer holds).
  final Set<String> deletes;

  /// Relative directories to ensure exist even when they hold no files yet.
  final Set<String> ensureDirs;
}
