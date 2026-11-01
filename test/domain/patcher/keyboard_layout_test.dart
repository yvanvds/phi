import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/keyboard_layout.dart';

void main() {
  test('the range widens out to white keys, in either order', () {
    final layout = KeyboardLayout(73, 61);
    expect(layout.low, 60);
    expect(layout.high, 74);
    expect(layout.whiteCount, 9);
  });

  test('the range stays inside MIDI', () {
    final layout = KeyboardLayout(-5, 200);
    expect(layout.low, 0);
    expect(layout.high, 127);
  });

  test('an unset GUI range is the default three octaves', () {
    final layout = KeyboardLayout.fromGui('', 'x');
    expect(layout.low, KeyboardLayout.defaultLow);
    expect(layout.high, KeyboardLayout.defaultHigh);
    expect(KeyboardLayout.fromGui('36', '48').low, 36);
  });

  test('white keys share the width; a black key straddles its seam', () {
    final layout = KeyboardLayout(60, 71); // one octave, 7 white keys
    final c = layout.boundsOf(60);
    expect(c.left, 0);
    expect(c.right, closeTo(1 / 7, 1e-12));
    expect(c.bottom, 1);
    final cSharp = layout.boundsOf(61);
    expect((cSharp.left + cSharp.right) / 2, closeTo(1 / 7, 1e-12));
    expect(cSharp.bottom, KeyboardLayout.blackDepth);
  });

  test('a point finds its key, a black key winning where it overlaps', () {
    final layout = KeyboardLayout(60, 71);
    expect(layout.keyAt(0.02, 0.9), 60);
    expect(layout.keyAt(1 / 7, 0.3), 61, reason: 'on the black key');
    expect(layout.keyAt(1 / 7 + 0.001, 0.9), 62, reason: 'below it');
    expect(layout.keyAt(0.99, 0.5), 71);
    expect(layout.keyAt(1.2, 0.5), isNull);
    expect(layout.keyAt(0.5, -0.1), isNull);
  });

  test('a press lower down a key plays louder', () {
    final layout = KeyboardLayout(60, 71);
    expect(layout.velocityAt(60, 0), 1);
    expect(layout.velocityAt(60, 1), 127);
    expect(layout.velocityAt(60, 0.5), 64);
    expect(
      layout.velocityAt(61, KeyboardLayout.blackDepth),
      127,
      reason: 'the bottom of a black key is its loudest',
    );
  });
}
