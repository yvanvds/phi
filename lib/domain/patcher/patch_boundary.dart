import 'patch_object_types.dart';
import 'patch_port.dart';

/// The vocabulary of **subpatches** (issue #481): the `patcher` container and
/// the four boundary objects that give it its pins.
///
/// A subpatch is not a separate patcher. Its contents are ordinary objects of
/// the same native patcher, each marked as being *inside* the box. The box owns
/// no pins of its own: every `.inlet` / `~inlet` directly inside it is one of
/// its inlets, and every `.outlet` / `~outlet` one of its outlets, numbered by
/// the boundary object's one creation argument. Messages and signals share one
/// numbering per side, so `.inlet 0` and `~inlet 1` make a two-inlet box.
///
/// A boundary object has a pin on each side of the wall. An inlet's **input 0**
/// is the box's inlet seen from the parent, and its output 0 carries what
/// arrives into the subpatch; an outlet is the mirror image. The engine records
/// a cable the parent wires to the box *on the boundary object itself*, so the
/// editor does the same: such a cable's end is the boundary object's
/// [isParentFacing] pin, drawn on the box in the parent's window and not at all
/// inside the subpatch.
abstract final class PatchBoundary {
  /// Whether [type] is the subpatch container.
  static bool isSubpatch(String type) => type == PatchObjectTypes.patcher;

  /// Whether [type] is a message or signal inlet of its subpatch.
  static bool isInlet(String type) =>
      type == PatchObjectTypes.gInlet || type == PatchObjectTypes.dInlet;

  /// Whether [type] is a message or signal outlet of its subpatch.
  static bool isOutlet(String type) =>
      type == PatchObjectTypes.gOutlet || type == PatchObjectTypes.dOutlet;

  /// Whether [type] is one of the four boundary objects.
  static bool isBoundary(String type) => isInlet(type) || isOutlet(type);

  /// The side of the enclosing box a boundary object of [type] is a pin on —
  /// `input` for an inlet, `output` for an outlet — or null for any other type.
  static PatchPortSide? boxSideOf(String type) {
    if (isInlet(type)) return PatchPortSide.input;
    if (isOutlet(type)) return PatchPortSide.output;
    return null;
  }

  /// The box pin a boundary object made with [args] claims: its first argument
  /// as a whole number, or 0 when it has none or it does not parse — the
  /// engine's own default (`.inlet` alone is inlet 0).
  static int indexOf(String args) {
    final first = args.trim().split(RegExp(r'\s+')).first;
    final parsed = int.tryParse(first);
    return parsed == null || parsed < 0 ? 0 : parsed;
  }

  /// Whether pin [index] on [side] of an object of [type] is the one that faces
  /// the **parent** — an inlet's input 0 or an outlet's output 0.
  ///
  /// Inside the subpatch that pin is not drawn and cannot be wired: the parent
  /// reaches it through the box. A boundary object at the top level of a patch
  /// has no parent at all, so the pin is hidden there too.
  static bool isParentFacing(String type, PatchPortSide side, int index) =>
      index == 0 && boxSideOf(type) == side;
}
