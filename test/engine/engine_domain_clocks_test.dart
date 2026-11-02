import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/state_machine/slices/state_slices.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_patch_clock.dart';
import 'test_doubles/fake_patcher_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// The engine publishes a clock per time domain, named by its address, for
/// patches to follow (issue #529): created before any patch, paced at the
/// domain's played tempo, and living exactly as long as the domain.
void main() {
  late FakeYseGateway yse;
  late FakeMidiGateway midi;
  late FakePatcherGateway patcher;
  late PhiEngine engine;
  late ProjectRegistry registry;

  final drum = EntityAddress(kind: RegistryKinds.domain, segments: ['drum']);

  setUp(() {
    yse = FakeYseGateway();
    midi = FakeMidiGateway();
    patcher = FakePatcherGateway();
    engine = PhiEngine(
      yse,
      midiGateway: midi,
      patcherGateway: patcher,
      telemetryInterval: const Duration(days: 1),
    );
    registry = ProjectRegistry()
      ..createEntity(drum, payload: const TimeDomain(name: 'drum', tempo: 124));
    engine.start();
    engine.bindProject(registry);
  });

  tearDown(() async {
    await engine.dispose();
    registry.dispose();
    await midi.dispose();
    await yse.dispose();
  });

  FakePatchClock drumClock() => patcher.clockNamed('domain.drum')!;

  test('a domain\'s clock is published under its address, at its tempo', () {
    expect(engine.domainClockName(drum), 'domain.drum');
    expect(drumClock().tempos, [124]);
  });

  test(
    'the clock is published before any patch is created, so a patch '
    'object naming domain.drum binds to it rather than making its own',
    () async {
      final gateway = FakePatcherGateway();
      final project = ProjectRegistry()
        ..createEntity(
          drum,
          payload: const TimeDomain(name: 'drum', tempo: 124),
        );
      final early = PhiEngine(
        FakeYseGateway(),
        midiGateway: FakeMidiGateway(),
        patcherGateway: gateway,
        telemetryInterval: const Duration(days: 1),
      )..bindProject(project);
      addTearDown(() async {
        await early.dispose();
        project.dispose();
      });
      early.start();
      final firstPatch = gateway.calls.indexWhere(
        (c) => c.startsWith('createInstance'),
      );
      expect(firstPatch, isNonNegative);
      expect(
        gateway.clockNamed('domain.drum')!.publishedAt,
        lessThanOrEqualTo(firstPatch),
      );
    },
  );

  test('an authored tempo change reaches the clock', () {
    registry.updateEntityPayload(
      drum,
      const TimeDomain(name: 'drum', tempo: 100),
    );
    expect(drumClock().tempos.last, 100);
  });

  test('a state\'s tempo override and the tempo fader reach the clock', () {
    final intro = introStateDocument();
    final verse = verseStateDocument().copyWith(
      slices: StateSlices(tempos: [TempoSliceEntry(domain: drum, bpm: 90)]),
    );
    registry
      ..createEntity(
        introStateAddress,
        payload: intro.toJson(),
        references: intro.references,
      )
      ..createEntity(
        verseStateAddress,
        payload: verse.toJson(),
        references: verse.references,
      );
    engine.stateMachine.setLive(verseStateAddress);
    expect(drumClock().tempos.last, 90, reason: 'the state override');

    engine.midi.tempoFader.position = 0.5;
    expect(
      drumClock().tempos.last,
      90 + 0.5 * engine.midi.tempoFader.bendRange,
      reason: 'the played tempo, bent by the fader',
    );
  });

  test('the clock lives as long as its domain', () {
    final clock = drumClock();
    registry.remove(drum);
    expect(clock.disposed, isTrue);
    expect(patcher.clockNamed('domain.drum'), isNull);

    registry.createEntity(
      drum,
      payload: const TimeDomain(name: 'drum', tempo: 80),
    );
    expect(drumClock().tempos, [80]);
  });

  test('an audio-session restart publishes the clock again', () {
    final before = drumClock();
    engine.switchAudioDevice(
      const AudioSettings(
        outputHost: 'WASAPI',
        outputDevice: 'Fake Interface',
        sampleRate: 96000,
      ),
    );
    expect(before.disposed, isTrue);
    expect(drumClock(), isNot(same(before)));
    expect(drumClock().tempos, [124]);
  });

  test('a new project publishes a new clock, even under the same name', () {
    final before = drumClock();
    final next = ProjectRegistry()
      ..createEntity(drum, payload: const TimeDomain(name: 'drum', tempo: 96));
    addTearDown(next.dispose);
    engine.bindProject(next);
    expect(before.disposed, isTrue);
    expect(drumClock(), isNot(same(before)));
    expect(drumClock().tempos, [96]);
  });

  test('stop destroys the clock', () {
    final clock = drumClock();
    engine.stop();
    expect(clock.disposed, isTrue);
  });
}
