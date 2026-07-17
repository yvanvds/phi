import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../domain/project/lifecycle/project_directory_picker.dart';

/// Production [ProjectDirectoryPicker] backed by the first-party `file_selector`
/// plugin's native folder dialogs.
///
/// "Open" picks an existing `.phi` folder directly. "New location" picks a
/// *parent* folder and appends `<name>.phi`, so a new or duplicated project
/// lands in a discoverable, suffixed folder (design
/// `docs/design/project-registry.md` §5). Constructing this touches no plugins —
/// the method channel is only reached when a dialog opens — so it is safe as the
/// shell's default even in headless widget tests.
class FileSelectorProjectDirectoryPicker implements ProjectDirectoryPicker {
  const FileSelectorProjectDirectoryPicker();

  /// The suffix that marks a project folder.
  static const String suffix = '.phi';

  @override
  Future<String?> pickProjectToOpen() =>
      getDirectoryPath(confirmButtonText: 'Open project');

  @override
  Future<String?> pickNewProjectLocation({
    required String suggestedName,
  }) async {
    final parent = await getDirectoryPath(confirmButtonText: 'Choose location');
    if (parent == null) return null;
    final folder = suggestedName.endsWith(suffix)
        ? suggestedName
        : '$suggestedName$suffix';
    return p.join(parent, folder);
  }
}
