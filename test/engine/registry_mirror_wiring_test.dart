import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_yse_gateway.dart';
import 'test_doubles/recording_registry_mirror.dart';

/// Proves the `RegistryMirror` seam is actually wired into [PhiEngine] end to
/// end (design §8, issue #125): channel edits and a project swap both reach the
/// injected mirror. The seam is a no-op in production; this exercises the
/// plumbing that the live-coding epic will hang a real mirror on.
void main() {
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late FakeYseGateway gateway;
  late RecordingRegistryMirror mirror;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    mirror = RecordingRegistryMirror();
    engine = PhiEngine(
      gateway,
      registryMirror: mirror,
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  test('addChannel reaches the mirror as onCreate', () async {
    engine.start();

    engine.addChannel(name: 'drums');
    await pumpEventQueue();

    expect(mirror.creates, [mix('drums')]);
  });

  test('removeChannel reaches the mirror as onDelete', () async {
    engine.start();
    final ch = engine.addChannel(name: 'drums');
    await pumpEventQueue();

    engine.removeChannel(ch);
    await pumpEventQueue();

    expect(mirror.deletes, [mix('drums')]);
  });

  test('the mirror follows a bindProject registry swap', () async {
    engine.start();
    final project = ProjectRegistry();
    addTearDown(project.dispose);
    engine.bindProject(project);

    // A create straight on the freshly bound registry reaches the mirror.
    project.createEntity(
      mix('bass'),
      payload: const MixStrip(voice: 4).toJson(),
    );
    await pumpEventQueue();

    expect(mirror.creates, [mix('bass')]);
  });

  test('start performs a boot full sync (issue #231)', () async {
    engine.start();
    await pumpEventQueue();

    // Exactly one full sync fired at boot — the empty default registry, so an
    // empty snapshot, but the re-sync path is proven present.
    expect(mirror.fullSyncs, hasLength(1));
    expect(mirror.fullSyncs.single, isEmpty);
  });

  test('a stop → start re-init re-pushes a full sync (issue #231)', () async {
    engine.start();
    engine.addChannel(name: 'drums');
    await pumpEventQueue();
    expect(mirror.fullSyncs, hasLength(1));

    // Restarting re-inits the engine's `System`, blanking the embedded Python —
    // the mirror must re-push the whole tree so the fresh table matches it.
    engine.stop();
    engine.start();
    await pumpEventQueue();

    expect(mirror.fullSyncs, hasLength(2));
    expect(mirror.fullSyncs.last, [mix('drums')]);
  });

  test('bindProject full-syncs the new tree (issue #231)', () async {
    engine.start();
    final project = ProjectRegistry();
    addTearDown(project.dispose);
    project.createEntity(
      mix('bass'),
      payload: const MixStrip(voice: 4).toJson(),
    );
    project.createEntity(
      mix('pads'),
      payload: const MixStrip(voice: 5).toJson(),
    );

    engine.bindProject(project);
    await pumpEventQueue();

    // The last full sync is the one bindProject pushed for the new tree.
    expect(mirror.fullSyncs.last, [mix('bass'), mix('pads')]);
  });
}
