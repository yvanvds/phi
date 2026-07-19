import 'clip_edit_command.dart';

/// Bundles several [ClipEditCommand]s into one undo step (issue #190).
///
/// The auto-extend path uses it to journal a length grow *together* with the
/// note edit that overran the clip's end: the parts apply in list order and
/// revert in the exact reverse, so undoing the note re-inserts nothing beyond
/// the end before the length shrinks back — one Ctrl+Z restores both.
///
/// [affectedIndices] defers to the **last** part (the note edit is placed last),
/// so the editor reselects exactly what a bare note command would have.
class CompositeClipCommand extends ClipEditCommand {
  CompositeClipCommand(super.clip, this.parts, {super.clipAddress})
    : assert(parts.isNotEmpty, 'a composite needs at least one part');

  /// The ordered parts. [apply] runs them front-to-back; [revert] back-to-front.
  final List<ClipEditCommand> parts;

  @override
  String get label => parts.last.label;

  @override
  Set<int> get affectedIndices => parts.last.affectedIndices;

  @override
  void apply() {
    for (final part in parts) {
      part.apply();
    }
  }

  @override
  void revert() {
    for (final part in parts.reversed) {
      part.revert();
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'composite',
    'parts': [for (final part in parts) part.toJson()],
  };
}
