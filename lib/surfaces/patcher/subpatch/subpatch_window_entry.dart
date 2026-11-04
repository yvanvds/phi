// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'package:flutter/src/widgets/_window.dart';

import '../../../domain/patcher/patch_node_id.dart';
import '../../../engine/state/patcher_controller.dart';

/// One open subpatch window (issue #481): the [box] of [editor] it shows, and
/// the native [window] it is drawn in. Since issue #553 it can also show a whole
/// patch: the definition behind an abstraction's instance.
class SubpatchWindowEntry {
  SubpatchWindowEntry({
    required this.editor,
    required this.box,
    required this.window,
    PatcherController? owner,
    this.root,
  }) : owner = owner ?? editor;

  /// The editor of the patch the subpatch belongs to, so the window shares its
  /// graph, journal and selection. The main window's editor unless the window
  /// shows a definition.
  final PatcherController editor;

  /// The patch open in the main window when this one was opened. The window
  /// lives no longer than that patch stays open.
  final PatcherController owner;

  /// The subpatch box whose contents the window shows, or null for the top
  /// level of [editor]'s patch.
  final PatchNodeId? box;

  /// The patch named at the head of the window's path when it is not the one in
  /// the main window (issue #553), or null.
  final String? root;

  /// The native window (Flutter's experimental windowing API, #478).
  final WindowController window;

  /// The title last given to [window], so a rename only re-titles on change.
  String title = '';
}
