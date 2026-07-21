import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/bridge/code_evaluator.dart';
import 'package:phi/engine/bridge/real_registry_mirror.dart';

import '../test_doubles/fake_code_evaluator.dart';

/// The real mirror (issue #231) translates each registry lifecycle change into a
/// `phi._sync_*(...)` script and pushes it through the shared [CodeEvaluator].
/// These prove the exact script the library's own `_sync_*` functions (issue
/// #230) expect, and that pushes reach the evaluator in event order.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late FakeCodeEvaluator evaluator;
  late RealRegistryMirror mirror;

  setUp(() {
    evaluator = FakeCodeEvaluator();
    mirror = RealRegistryMirror(evaluator);
  });

  tearDown(() => evaluator.dispose());

  test('onCreate pushes _sync_create with the dotted address', () async {
    mirror.onCreate(addr('clip.drums.intro_fill'));
    await pumpEventQueue();

    expect(evaluator.calls, ["phi._sync_create('clip.drums.intro_fill')"]);
  });

  test('onDelete pushes _sync_delete', () async {
    mirror.onDelete(addr('clip.lead'));
    await pumpEventQueue();

    expect(evaluator.calls, ["phi._sync_delete('clip.lead')"]);
  });

  test('onRename pushes _sync_rename with both addresses', () async {
    mirror.onRename(addr('voice.bells'), addr('voice.chimes'));
    await pumpEventQueue();

    expect(evaluator.calls, [
      "phi._sync_rename('voice.bells', 'voice.chimes')",
    ]);
  });

  test('onRegroup pushes _sync_regroup with both addresses', () async {
    mirror.onRegroup(addr('clip.lead'), addr('clip.solos.lead'));
    await pumpEventQueue();

    expect(evaluator.calls, [
      "phi._sync_regroup('clip.lead', 'clip.solos.lead')",
    ]);
  });

  test('syncAll pushes _sync_replace with a quoted address list', () async {
    mirror.syncAll([
      addr('clip.drums'),
      addr('clip.drums.intro_fill'),
      addr('voice.bells'),
    ]);
    await pumpEventQueue();

    expect(evaluator.calls, [
      "phi._sync_replace(['clip.drums', 'clip.drums.intro_fill', 'voice.bells'])",
    ]);
  });

  test('an empty full sync pushes _sync_replace([])', () async {
    mirror.syncAll(const []);
    await pumpEventQueue();

    expect(evaluator.calls, ['phi._sync_replace([])']);
  });

  test('pushes reach the evaluator in event order', () async {
    // A create followed by a rename must enqueue create-before-rename, so a
    // script run right after sees the renamed table (design §3, ordering).
    mirror.onCreate(addr('voice.bells'));
    mirror.onRename(addr('voice.bells'), addr('voice.chimes'));
    await pumpEventQueue();

    expect(evaluator.calls, [
      "phi._sync_create('voice.bells')",
      "phi._sync_rename('voice.bells', 'voice.chimes')",
    ]);
  });

  test('a rejected push does not surface as an unhandled error', () async {
    evaluator.nextOutcome = const EvalOutcome.failed('boom');

    mirror.onCreate(addr('clip.lead'));

    // Completing the microtask queue must not throw despite the failed outcome.
    await expectLater(pumpEventQueue(), completes);
    expect(evaluator.calls, ["phi._sync_create('clip.lead')"]);
  });
}
