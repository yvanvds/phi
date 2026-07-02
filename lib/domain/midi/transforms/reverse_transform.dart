import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Inverts time direction across a fixed window: the note that used to end
/// last now starts first. [lengthBeats] is the window the reversal mirrors
/// around — typically the host clip's total length — since [apply] only
/// sees notes, not the clip that owns them.
///
/// Durations are preserved; only `start` moves, via
/// `newStart = lengthBeats - start - duration`. Applying the same
/// [ReverseTransform] twice to its own output restores the original notes.
///
/// A non-positive [lengthBeats] is treated as "no window" and the input
/// passes through unchanged rather than mirroring around zero.
class ReverseTransform extends MidiTransform {
  const ReverseTransform({
    required this.lengthBeats,
    required this.label,
    this.active = true,
  });

  /// The window, in beats, that notes are mirrored within.
  final double lengthBeats;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.struct;

  @override
  List<MidiNote> apply(List<MidiNote> input) {
    if (lengthBeats <= 0) return input;
    return input
        .map((n) => n.copyWith(start: lengthBeats - n.start - n.duration))
        .toList(growable: false);
  }

  @override
  ReverseTransform copyWith({bool? active}) => ReverseTransform(
    lengthBeats: lengthBeats,
    label: label,
    active: active ?? this.active,
  );
}
