/// A single "set [parameter] to [value] at [beat]" instruction derived from
/// note data — the domain-side currency of velocity-to-parameter mappings.
///
/// [parameter] is an engine parameter path (e.g. `filter.cutoff`,
/// `fm.index`); the domain never interprets it, it just carries the string
/// to whoever owns the engine bridge. [beat] is measured from the clip
/// origin, same clock as [MidiNote.start]. [value] is whatever the mapping
/// curve produced — units belong to the target parameter.
class ParameterEvent {
  const ParameterEvent({
    required this.parameter,
    required this.beat,
    required this.value,
  });

  final String parameter;
  final double beat;
  final double value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParameterEvent &&
          other.parameter == parameter &&
          other.beat == beat &&
          other.value == value;

  @override
  int get hashCode => Object.hash(parameter, beat, value);

  @override
  String toString() => 'ParameterEvent($parameter @ $beat = $value)';
}
