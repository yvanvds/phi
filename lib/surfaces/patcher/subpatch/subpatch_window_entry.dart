// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'package:flutter/src/widgets/_window.dart';

import '../../../domain/patcher/patch_node_id.dart';
import '../../../engine/state/patcher_controller.dart';

/// One open subpatch window (issue #481): the [box] of [editor] it shows, and
/// the native [window] it is drawn in.
class SubpatchWindowEntry {
  SubpatchWindowEntry({
    required this.editor,
    required this.box,
    required this.window,
  });

  /// The editor of the patch the subpatch belongs to — the same one the main
  /// window edits, so both share its graph, journal and selection.
  final PatcherController editor;

  /// The subpatch box whose contents the window shows.
  final PatchNodeId box;

  /// The native window (Flutter's experimental windowing API, #478).
  final WindowController window;

  /// The title last given to [window], so a rename only re-titles on change.
  String title = '';
}
