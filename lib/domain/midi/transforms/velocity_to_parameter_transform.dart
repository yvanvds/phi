import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../parameter_event.dart';
import 'velocity_curve.dart';

/// Turns each note's velocity into a [ParameterEvent] for one engine
/// [parameter] — filter cutoff tracking accents, FM index opening up with
/// louder playing, and so on.
///
/// Notes themselves pass through [apply] untouched: this transform routes
/// *control* data, not note data, so toggling it never changes the piano
/// roll. Consumers pull the control stream with [eventsFor], feeding it the
/// same note list the chain handed to this stage.
///
/// [curve] is the mapping seam. It used to be a bare `double Function(double)`
/// callback, which nothing could edit or serialise; issue #108 replaces it with
/// a declarative [VelocityCurve] — a pure, immutable value model the typed curve
/// editor mutates in place. Like every transform the mapping stays pure — same
/// velocity, same value — so the chain stays memoisable.
class VelocityToParameterTransform extends MidiTransform {
  const VelocityToParameterTransform({
    required this.parameter,
    required this.curve,
    required this.label,
    this.active = true,
  });

  /// Engine parameter path this mapping drives (e.g. `filter.cutoff`).
  final String parameter;

  /// Declarative velocity-to-value mapping; see [VelocityCurve].
  final VelocityCurve curve;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.voice;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input;

  /// Carries [parameter] and [curve] alongside the base [active]/[label] so the
  /// typed curve editor (issue #108) can retarget the parameter or reshape the
  /// curve in place without losing the chip's toggle or name.
  @override
  VelocityToParameterTransform copyWith({
    bool? active,
    String? label,
    String? parameter,
    VelocityCurve? curve,
  }) => VelocityToParameterTransform(
    parameter: parameter ?? this.parameter,
    curve: curve ?? this.curve,
    label: label ?? this.label,
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
          value: curve.valueAt(n.velocity),
        ),
      )
      .toList(growable: false);
}
