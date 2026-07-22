import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/bridge/code_evaluator.dart';
import 'package:phi/engine/bridge/state_current_mirror.dart';

import '../test_doubles/fake_code_evaluator.dart';

/// The `state.current` push seam (issue #246): live-state changes become
/// `phi._sync_state_current(...)` scripts on the shared evaluator, de-duped,
/// fire-and-forget, and silent while no evaluator is wired.
void main() {
  EntityAddress state(String path) =>
      EntityAddress(kind: 'state', segments: path.split('.'));

  late FakeCodeEvaluator evaluator;
  late StateCurrentMirror mirror;

  setUp(() {
    evaluator = FakeCodeEvaluator();
    mirror = StateCurrentMirror(() => evaluator);
  });

  tearDown(() => evaluator.dispose());

  test('a push evaluates the sync script with the path under state.', () {
    mirror.push(state('verse'));
    expect(evaluator.calls, ["phi._sync_state_current('verse')"]);
  });

  test('a grouped state pushes its dotted path', () {
    mirror.push(state('songs.verse'));
    expect(evaluator.calls, ["phi._sync_state_current('songs.verse')"]);
  });

  test('null pushes a clear', () {
    mirror.push(null);
    expect(evaluator.calls, ['phi._sync_state_current(None)']);
  });

  test('a repeat of the last pushed address is de-duped', () {
    mirror.push(state('verse'));
    mirror.push(state('verse'));
    mirror.push(state('intro'));
    mirror.push(state('intro'));
    expect(evaluator.calls, [
      "phi._sync_state_current('verse')",
      "phi._sync_state_current('intro')",
    ]);
  });

  test('reset lets an unchanged address through again (re-init re-seed)', () {
    mirror.push(state('verse'));
    mirror.reset();
    mirror.push(state('verse'));
    expect(evaluator.calls, hasLength(2));
  });

  test('no evaluator wired: the push is dropped, not memoised', () {
    CodeEvaluator? wired;
    final unwired = StateCurrentMirror(() => wired);
    unwired.push(state('verse'));

    // Wiring later and pushing the same address goes through — the dropped
    // push never counted as delivered.
    wired = evaluator;
    unwired.push(state('verse'));
    expect(evaluator.calls, ["phi._sync_state_current('verse')"]);
  });

  test('a rejected evaluation never surfaces as an error', () async {
    evaluator.nextOutcome = const EvalOutcome.failed('boom');
    mirror.push(state('verse'));
    await pumpEventQueue();
    expect(evaluator.calls, hasLength(1));
  });

  test('a throwing evaluator is swallowed, never an unhandled error', () async {
    final throwing = StateCurrentMirror(() => _ThrowingEvaluator());
    throwing.push(state('verse'));
    await pumpEventQueue(); // an unhandled async error would fail the test
  });
}

class _ThrowingEvaluator implements CodeEvaluator {
  @override
  Future<EvalOutcome> evaluate(String source) async =>
      throw StateError('interpreter gone');

  @override
  Stream<EvalEvent> get events => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
