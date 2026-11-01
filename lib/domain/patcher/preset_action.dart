/// What a click on a `.preset` slot does, by the modifier held (issue #477):
/// Max's convention, spelled as the message the object takes on inlet 0.
enum PresetAction {
  /// A plain click: push the slot's snapshot back into the patch.
  recall('recall'),

  /// Shift+click: capture the patch's controls into the slot.
  store('store'),

  /// Alt+click: empty the slot.
  clear('clear');

  const PresetAction(this.selector);

  /// The action a click with these modifiers performs. Alt wins over Shift,
  /// so a chord can never store over a slot by accident.
  factory PresetAction.forModifiers({required bool shift, required bool alt}) {
    if (alt) return PresetAction.clear;
    if (shift) return PresetAction.store;
    return PresetAction.recall;
  }

  /// The message's selector word.
  final String selector;

  /// The message that performs this action on [slot] (`store 3`).
  String messageFor(int slot) => '$selector $slot';

  /// The modifier hint a slot grid shows as its tooltip.
  static const String hint =
      'Click recalls a slot · Shift+click stores · Alt+click clears';
}
