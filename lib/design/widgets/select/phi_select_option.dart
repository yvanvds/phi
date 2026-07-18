/// One selectable row in a `PhiSelect<T>`: a [value] and the [label] shown for
/// it. Purely presentational — the widget carries no domain knowledge, so a
/// "device default" first entry is just an ordinary option whose [value] the
/// consumer chooses (e.g. `null` for an `int?` sample rate).
class PhiSelectOption<T> {
  const PhiSelectOption({required this.value, required this.label});

  /// The value emitted through `PhiSelect.onChanged` when this row is picked.
  final T value;

  /// The text rendered for this row, in the closed control and the open list.
  final String label;
}
