/// What the reference panel says about a selected subpatch box (issue #481):
/// the name it was given and the pins its boundary objects give it.
class PatchSubpatchSummary {
  const PatchSubpatchSummary({
    required this.name,
    required this.inlets,
    required this.outlets,
    this.definition,
    this.definitionFollowed = true,
  });

  /// The box's name — its arguments — or `''` for an unnamed one.
  final String name;

  /// How many inlets the box shows (one past the highest `.inlet` /
  /// `~inlet` index inside it).
  final int inlets;

  /// How many outlets the box shows.
  final int outlets;

  /// The `patch.` address the box is an instance of (issue #553), or null for
  /// an ordinary subpatch.
  final String? definition;

  /// Whether the box actually follows [definition]: false when that patch is
  /// gone, or when using it would make a patch contain itself.
  final bool definitionFollowed;
}
