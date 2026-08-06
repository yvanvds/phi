import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/time_domains/fader_tempo_source.dart';
import 'package:phi/domain/time_domains/tempo_source.dart';
import 'package:phi/domain/time_domains/tempo_source_stack.dart';

/// A hand-controllable [TempoSource] for asserting the seam's summing and
/// idle-gating without leaning on the fader's clamping.
class _FakeSource extends ChangeNotifier implements TempoSource {
  _FakeSource({this._offset = 0, this._modulating = false});

  double _offset;
  bool _modulating;

  @override
  double get offset => _offset;

  @override
  bool get isModulating => _modulating;

  void set({double? offset, bool? modulating}) {
    if (offset != null) _offset = offset;
    if (modulating != null) _modulating = modulating;
    notifyListeners();
  }
}

void main() {
  group('TempoSourceStack', () {
    test('an empty stack is the identity — nothing modulates', () {
      final stack = TempoSourceStack();
      expect(stack.isModulating, isFalse);
      expect(stack.offset, 0);
      expect(stack.apply(120), 120);
    });

    test('a resting source adds nothing (zero idle cost)', () {
      final fader = FaderTempoSource();
      final stack = TempoSourceStack([fader]);
      expect(stack.isModulating, isFalse);
      expect(stack.offset, 0);
      // apply returns the base *unchanged* — no clamp, no recompute.
      expect(stack.apply(120), 120);
    });

    test('sums every modulating source onto the base tempo', () {
      final a = _FakeSource(offset: 10, modulating: true);
      final b = _FakeSource(offset: -4, modulating: true);
      final stack = TempoSourceStack([a, b]);
      expect(stack.isModulating, isTrue);
      expect(stack.offset, 6);
      expect(stack.apply(120), 126);
    });

    test('skips idle sources when summing', () {
      final live = _FakeSource(offset: 10, modulating: true);
      final idle = _FakeSource(offset: 999, modulating: false);
      final stack = TempoSourceStack([live, idle]);
      expect(stack.offset, 10);
      expect(stack.apply(120), 130);
    });

    test('floors the bent tempo at a positive minimum', () {
      final hardDown = _FakeSource(offset: -500, modulating: true);
      final stack = TempoSourceStack([hardDown]);
      expect(stack.apply(120), 1);
    });

    test('forwards a source notification to its own listeners', () {
      final source = _FakeSource(modulating: true);
      final stack = TempoSourceStack([source]);
      var notifications = 0;
      stack.addListener(() => notifications++);

      source.set(offset: 5);
      expect(notifications, 1);
      expect(stack.offset, 5);
    });

    test('add and remove track the source and notify', () {
      final stack = TempoSourceStack();
      var notifications = 0;
      stack.addListener(() => notifications++);

      final source = _FakeSource(offset: 8, modulating: true);
      stack.add(source);
      expect(notifications, 1);
      expect(stack.apply(100), 108);

      // Once added, the source's own changes flow through.
      source.set(offset: 3);
      expect(notifications, 2);
      expect(stack.apply(100), 103);

      expect(stack.remove(source), isTrue);
      expect(notifications, 3);
      expect(stack.apply(100), 100);

      // A removed source no longer drives the stack.
      source.set(offset: 50);
      expect(notifications, 3);
    });

    test('remove returns false for a source that was never added', () {
      final stack = TempoSourceStack();
      expect(stack.remove(_FakeSource()), isFalse);
    });

    test('a fader in the stack bends the base tempo as it moves', () {
      final fader = FaderTempoSource(bendRange: 40);
      final stack = TempoSourceStack([fader]);
      expect(stack.apply(120), 120);

      fader.position = 0.5; // +20 BPM
      expect(stack.apply(120), 140);

      fader.position = -0.25; // -10 BPM
      expect(stack.apply(120), 110);

      fader.position = 0; // back to rest
      expect(stack.apply(120), 120);
    });
  });
}
