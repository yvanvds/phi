// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/widgets.dart';

import 'subpatch_window_entry.dart';
import 'subpatch_windows.dart';

/// Renders every open subpatch window (issue #481) next to [child], which
/// stays where it is in the main window.
///
/// The windows hang off a [ViewAnchor]: each is a [Window] — a view of its
/// own, drawn into its native window — but its widgets stay descendants of
/// this host, so they read the main window's theme, localizations and engine
/// like any other part of the surface.
class SubpatchWindowsHost extends StatelessWidget {
  const SubpatchWindowsHost({
    required this.windows,
    required this.builder,
    required this.child,
    super.key,
  });

  final SubpatchWindows windows;

  /// Builds one window's content.
  final Widget Function(BuildContext context, SubpatchWindowEntry entry)
  builder;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: windows,
      builder: (context, child) {
        final entries = windows.entries;
        return ViewAnchor(
          view: entries.isEmpty
              ? null
              : ViewCollection(
                  views: [
                    for (final e in entries)
                      Window(
                        key: ObjectKey(e),
                        controller: e.window,
                        child: builder(context, e),
                      ),
                  ],
                ),
          child: child!,
        );
      },
      child: child,
    );
  }
}
