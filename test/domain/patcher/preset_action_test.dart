import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/preset_action.dart';

void main() {
  test('a plain click recalls, Shift stores and Alt clears', () {
    expect(
      PresetAction.forModifiers(shift: false, alt: false),
      PresetAction.recall,
    );
    expect(
      PresetAction.forModifiers(shift: true, alt: false),
      PresetAction.store,
    );
    expect(
      PresetAction.forModifiers(shift: false, alt: true),
      PresetAction.clear,
    );
  });

  test('Alt wins over Shift, so a chord never stores', () {
    expect(
      PresetAction.forModifiers(shift: true, alt: true),
      PresetAction.clear,
    );
  });

  test('each action is the message the object takes', () {
    expect(PresetAction.recall.messageFor(3), 'recall 3');
    expect(PresetAction.store.messageFor(0), 'store 0');
    expect(PresetAction.clear.messageFor(31), 'clear 31');
  });
}
