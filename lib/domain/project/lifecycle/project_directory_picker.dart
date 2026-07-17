/// Abstraction over the native folder dialogs the project menu uses to open an
/// existing `.phi` project or choose a location for a new one (design
/// `docs/design/project-registry.md` §9).
///
/// Mirrors `MidiFileIo`: the native dialogs are an un-fakeable OS surface, so
/// this interface is injected into the shell and a fake returns canned paths in
/// tests. The lifecycle logic (load/save/recents) lives in `ProjectController`;
/// this only owns the folder pick.
abstract interface class ProjectDirectoryPicker {
  /// Prompt for an existing project folder to open. Returns the chosen `.phi`
  /// folder's absolute path, or `null` if the user cancelled.
  Future<String?> pickProjectToOpen();

  /// Prompt for where to write a new (or duplicated) project named
  /// [suggestedName]. Returns the absolute path of the target `.phi` folder to
  /// create, or `null` if the user cancelled.
  Future<String?> pickNewProjectLocation({required String suggestedName});
}
