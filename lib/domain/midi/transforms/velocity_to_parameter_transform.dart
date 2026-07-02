import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../parameter_event.dart';

/// Maps a normalised velocity in `[0, 1]` onto a parameter value. The
/// signature is deliberately minimal so a live-coded Python function can
/// stand behind it later: the `CodeEvaluator` side only has to produce
/// something callable as `double → double`.
typedef VelocityCurve = double Function(double velocity);

/// Turns each note's velocity into a [ParameterEvent] for one engine
/// [parameter] — filter cutoff tracking accents, FM index opening up with
/// louder playing, and so on.
///
/// Notes themselves pass through [apply] untouched: this transform routes
/// *control* data, not note data, so toggling it never changes the piano
/// roll. Consumers pull the control stream with [eventsFor], feeding it the
/// same note list the chain handed to this stage.
///
/// [curve] is the mapping seam. It is a plain Dart callback today; the
/// vision is that a `CodeEvaluator`-hosted function slots in behind the
/// same [VelocityCurve] shape without this class changing. Like every
/// transform, the curve must be pure — same velocity, same value — so the
/// chain stays memoisable.
class VelocityToParameterTransform extends MidiTransform {
  const VelocityToParameterTransform({
    required this.parameter,
    required this.curve,
    required this.label,
    this.active = true,
  });

  /// Engine parameter path this mapping drives (e.g. `filter.cutoff`).
  final String parameter;

  /// Pure velocity-to-value mapping; see [VelocityCurve].
  final VelocityCurve curve;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.voice;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input;

  @override
  VelocityToParameterTransform copyWith({bool? active}) =>
      VelocityToParameterTransform(
        parameter: parameter,
        curve: curve,
        label: label,
        active: active ?? this.active,
      );

  /// One [ParameterEvent] per note, at the note's start beat, in input
  /// order. The caller decides what "input" means — typically the note list
  /// at this transform's position in the chain.
  List<ParameterEvent> eventsFor(List<MidiNote> input) => input
      .map(
        (n) => ParameterEvent(
          parameter: parameter,
          beat: n.start,
          value: curve(n.velocity),
        ),
      )
      .toList(growable: false);
}
