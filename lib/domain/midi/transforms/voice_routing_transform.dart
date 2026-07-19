import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import 'voice_routing_rule.dart';

/// Assigns each note's [MidiNote.voice] from an ordered list of [rules].
///
/// Rules are tried in list order and the **first match wins**, so specific
/// rules (an accent range, a single scale degree) go before broad
/// catch-alls. A note no rule matches keeps its incoming voice — the
/// transform routes, it never drops.
///
/// The voice is a `voice.` registry address; the flatten step maps it onto the
/// voice's allocated engine channel (design `docs/design/racks-and-voices.md`
/// §6). Keeping that mapping out of the domain keeps this transform pure Dart.
class VoiceRoutingTransform extends MidiTransform {
  const VoiceRoutingTransform({
    required this.rules,
    required this.label,
    this.active = true,
  });

  /// Tried in order; first match assigns the note's voice.
  final List<VoiceRoutingRule> rules;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.voice;

  @override
  List<MidiNote> apply(List<MidiNote> input) =>
      input.map(_route).toList(growable: false);

  /// Carries [rules] alongside the base [active]/[label] so the typed
  /// rule-list editor (issue #95) can replace the routing table in place
  /// without losing the chip's toggle or name.
  @override
  VoiceRoutingTransform copyWith({
    bool? active,
    String? label,
    List<VoiceRoutingRule>? rules,
  }) => VoiceRoutingTransform(
    rules: rules ?? this.rules,
    label: label ?? this.label,
    active: active ?? this.active,
  );

  MidiNote _route(MidiNote note) {
    for (final rule in rules) {
      if (rule.matches(note)) return note.copyWith(voice: rule.voice);
    }
    return note;
  }
}
