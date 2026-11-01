import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/preset_slots.dart';

void main() {
  Map<String, Object?> slot(int n, {int objects = 1}) => {
    'slot': n,
    'objects': [
      for (var i = 0; i < objects; i++)
        {'object': i, 'type': '.slider', 'value': '0.5'},
    ],
  };

  test('nothing saved is every slot empty', () {
    expect(PresetSlots.fromState(null).stored, isEmpty);
    expect(PresetSlots.fromState({'active': 3}).stored, isEmpty);
  });

  test('each listed slot with captured objects is stored', () {
    final slots = PresetSlots.fromState({
      'active': 2,
      'slots': [slot(0), slot(2, objects: 3), slot(7)],
    });
    expect(slots.stored, {0, 2, 7});
    expect(slots.isStored(2), isTrue);
    expect(slots.isStored(1), isFalse);
  });

  test('malformed or empty entries are skipped', () {
    final slots = PresetSlots.fromState({
      'slots': [
        slot(1, objects: 0),
        {'slot': -1, 'objects': const <Object?>[]},
        {
          'objects': const [1],
        },
        'junk',
        {'slot': 4, 'objects': 'junk'},
        slot(5),
      ],
    });
    expect(slots.stored, {5});
  });
}
