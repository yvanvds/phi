import 'nslider_args.dart';

/// A vertical drag on an `.nslider` staff (issue #473): the pitch follows the
/// pointer a semitone per [pixelsPerSemitone], up for higher, from the pitch
/// the press found, inside the object's bounds.
class StaffDrag {
  StaffDrag({
    required this.start,
    required this.args,
    this.pixelsPerSemitone = 4,
  });

  /// The pitch the press found.
  final int start;

  /// The object's bounds.
  final NsliderArgs args;

  /// How far the pointer travels for one semitone.
  final double pixelsPerSemitone;

  /// The pitch after the pointer has moved [dy] pixels down since the press
  /// (negative is up).
  int pitchAfter(double dy) =>
      args.bound(start - (dy / pixelsPerSemitone).round());
}
