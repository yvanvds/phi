/// What the reference panel says about a selected subpatch box (issue #481):
/// the name it was given and the pins its boundary objects give it.
class PatchSubpatchSummary {
  const PatchSubpatchSummary({
    required this.name,
    required this.inlets,
    required this.outlets,
  });

  /// The box's name — its arguments — or `''` for an unnamed one.
  final String name;

  /// How many inlets the box shows (one past the highest `.inlet` /
  /// `~inlet` index inside it).
  final int inlets;

  /// How many outlets the box shows.
  final int outlets;
}
