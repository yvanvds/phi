import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/keyboard_gesture.dart';

void main() {
  test('a press plays, a slide releases then plays, a lift releases', () {
    final g = KeyboardGesture();
    expect(g.moveTo(60, 90), [(pitch: 60, velocity: 90)]);
    expect(g.moveTo(60, 20), isEmpty, reason: 'still on the same key');
    expect(g.moveTo(62, 70), [
      (pitch: 60, velocity: 0),
      (pitch: 62, velocity: 70),
    ]);
    expect(g.held, 62);
    expect(g.release(), [(pitch: 62, velocity: 0)]);
    expect(g.release(), isEmpty);
    expect(g.held, isNull);
  });

  test('sliding off the keyboard releases, and a note-on is never 0', () {
    final g = KeyboardGesture();
    g.moveTo(60, 50);
    expect(g.moveTo(null, 0), [(pitch: 60, velocity: 0)]);
    expect(g.moveTo(64, 0), [(pitch: 64, velocity: 1)]);
  });
}
