import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/staff_note.dart';

void main() {
  test('middle C sits on its own ledger line between the staves', () {
    final note = StaffNote.of(60, 0);
    expect(note.step, StaffNote.middleC);
    expect(note.ledgers, [StaffNote.middleC]);
    expect(note.ottava, 0);
  });

  test('a black key keeps its accidental; a white key drops one', () {
    expect(
      StaffNote.of(61, -1),
      const StaffNote(step: 36, accidental: -1, ottava: 0),
    );
    expect(StaffNote.of(61, 1).step, 35);
    expect(StaffNote.of(62, 1).accidental, 0);
  });

  test('a note on the staves needs no ledger lines', () {
    expect(StaffNote.of(64, 0).ledgers, isEmpty, reason: 'E4, bottom line');
    expect(StaffNote.of(57, 0).ledgers, isEmpty, reason: 'A3, top bass line');
  });

  test('notes past the staves take ledger lines out to them', () {
    expect(StaffNote.of(84, 0).ledgers, [47, 49], reason: 'C6');
    expect(StaffNote.of(81, 0).ledgers, [47], reason: 'A5');
    expect(StaffNote.of(36, 0).ledgers, [23, 21], reason: 'C2');
  });

  test('a note beyond the window is drawn octaves nearer, marked', () {
    final high = StaffNote.of(96, 0); // C7
    expect(high.step, 49, reason: 'drawn as C6');
    expect(high.ottava, 1);
    final low = StaffNote.of(12, 0); // C0
    expect(low.step, 21);
    expect(low.ottava, -2);
  });
}
