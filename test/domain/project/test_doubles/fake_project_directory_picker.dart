import 'package:phi/domain/project/lifecycle/project_directory_picker.dart';

/// In-memory [ProjectDirectoryPicker] for tests — the native folder dialogs are
/// an un-fakeable OS surface, so tests inject this to return canned paths.
///
/// Set [openPath] for what "Open" resolves to and [newLocationPath] for a
/// save/duplicate location; leave either `null` to simulate the performer
/// cancelling the dialog. The call counters and [lastSuggestedName] let a test
/// assert the picker was reached.
class FakeProjectDirectoryPicker implements ProjectDirectoryPicker {
  FakeProjectDirectoryPicker({this.openPath, this.newLocationPath});

  /// What [pickProjectToOpen] returns; `null` simulates a cancel.
  String? openPath;

  /// What [pickNewProjectLocation] returns; `null` simulates a cancel.
  String? newLocationPath;

  /// The suggested name passed to the last [pickNewProjectLocation] call.
  String? lastSuggestedName;

  int openCallCount = 0;
  int newLocationCallCount = 0;

  @override
  Future<String?> pickProjectToOpen() async {
    openCallCount++;
    return openPath;
  }

  @override
  Future<String?> pickNewProjectLocation({
    required String suggestedName,
  }) async {
    newLocationCallCount++;
    lastSuggestedName = suggestedName;
    return newLocationPath;
  }
}
