import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// Writes a patch in the tutorial file format to disk — the dev-facing
/// "Export Patch as Tutorial…" authoring path (issue #489): build the patch in
/// Phi, export it, drop the file into `assets/tutorials/patcher/` and add its
/// types to `index.json`.
///
/// Constructing this touches no plugin; the dialog's method channel is only
/// reached by [save].
class PatchTutorialExport {
  const PatchTutorialExport();

  static const _group = XTypeGroup(label: 'Phi tutorial', extensions: ['json']);

  /// Ask where to save [json] (suggesting [suggestedName]) and write it.
  /// Returns whether a file was written (false when the dialog was cancelled).
  Future<bool> save(String suggestedName, String json) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_group],
    );
    if (location == null) return false;
    final file = XFile.fromData(
      utf8.encode(json),
      mimeType: 'application/json',
      name: suggestedName,
    );
    await file.saveTo(location.path);
    return true;
  }
}
