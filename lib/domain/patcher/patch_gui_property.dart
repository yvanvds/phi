/// The keys of the **decoration** an object carries in its engine-side GUI
/// properties — editor state saved with the patch (`"gui"` in a libYSE dump)
/// that the engine itself never reads.
///
/// Position (`x`/`y`) is not listed: it is every object's, has its own gateway
/// verb and its own `PatchNode.position`. What *is* listed is the per-object
/// decoration beyond it, held by the controller as a plain key → string map
/// and carried whole through delete/undo, duplicate, paste, retype and a
/// reload. Adding one is adding a key to [decoration]: the reload reads every
/// key named there, and everything else already travels as part of the map.
///
/// Pure Dart (no `package:yse`): the domain names the keys, the bridge only
/// moves strings.
abstract final class PatchGuiProperty {
  /// A note's wrap width in logical pixels (issue #488). Absent on a note
  /// that was never resized, which then shrink-wraps its text up to the
  /// default reading width.
  static const String width = 'w';

  /// Every decoration key a reload reads back from the engine.
  static const List<String> decoration = [width];
}
