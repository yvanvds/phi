import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/voice/voice_definition.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/metronome_controller.dart';

import 'test_doubles/fake_fx_gateway.dart';
import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_midi_transport.dart';
import 'test_doubles/fake_patcher_gateway.dart';
import 'test_doubles/fake_synth_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// A live sample-rate change restarts the native audio session **in place**
/// (issue #448): the session rate is locked from init to close (yse 0.2.0), so
/// a new rate needs `close()` + a fresh session — which frees every native
/// object — but the engine-side controllers the shell holds from its
/// `initState` (`midi.chain` / `midi.editor`, the state machine, the patch
/// library, …) must survive it, and the project must sound again afterwards.
void main() {
  EntityAddress at(String kind, String name) =>
      EntityAddress(kind: kind, segments: [name]);

  final master = at(RegistryKinds.mix, 'master');
  const picked96k = AudioSettings(
    outputHost: 'WASAPI',
    outputDevice: 'Fake Interface',
    sampleRate: 96000,
  );

  late FakeYseGateway yse;
  late FakeSynthGateway synths;
  late FakeFxGateway fxs;
  late FakeMidiGateway midi;
  late FakePatcherGateway patcher;
  late PhiEngine engine;
  late ProjectRegistry registry;

  setUp(() {
    yse = FakeYseGateway();
    synths = FakeSynthGateway();
    fxs = FakeFxGateway();
    midi = FakeMidiGateway();
    patcher = FakePatcherGateway();
    // Listed from boot: the enumeration is a snapshot nothing can rescan while
    // a stream is open (issues #412, #445).
    yse.devices = [
      ...yse.devices,
      const AudioDeviceDescriptor(
        name: 'Old Card',
        hostName: 'MME',
        sampleRates: [44100.0],
        bufferSizes: [512],
        defaultBufferSize: 512,
      ),
      const AudioDeviceDescriptor(
        name: 'Flaky',
        hostName: 'ASIO',
        sampleRates: [96000.0],
        bufferSizes: [256],
        defaultBufferSize: 256,
      ),
    ];
    yse.unopenableDeviceNames.add('Flaky');
    engine = PhiEngine(
      yse,
      midiGateway: midi,
      synthGateway: synths,
      fxGateway: fxs,
      patcherGateway: patcher,
      telemetryInterval: const Duration(days: 1),
    );
    registry = ProjectRegistry()
      ..createEntity(
        at(RegistryKinds.synth, 'sine'),
        payload: const SineSynth().toJson(),
      )
      ..createEntity(
        at(RegistryKinds.mix, 'drums'),
        payload: const MixStrip(voice: 1, volume: 0.4).toJson(),
      )
      ..createEntity(
        at(RegistryKinds.voice, 'default'),
        payload: VoiceDefinition.internal(
          synth: at(RegistryKinds.synth, 'sine'),
          output: master,
        ).toJson(),
      );
    engine.start();
    engine.bindProject(registry);
  });

  tearDown(() async {
    await engine.dispose();
    registry.dispose();
    await midi.dispose();
    await yse.dispose();
  });

  FakeMidiTransport transportOn(String clockName) =>
      midi.transports.lastWhere((t) => t.clockName == clockName);

  test('a picked rate restarts the session at it — before #448 the running '
      'session kept 48 kHz until the next launch', () {
    expect(engine.sessionSampleRate, 48000);

    final ok = engine.switchAudioDevice(picked96k);

    expect(ok, isTrue);
    expect(yse.calls, containsAllInOrder(<String>['close', 'initOffline']));
    expect(engine.sessionSampleRate, 96000);
    expect(engine.activeAudioState().sampleRate, 96000);
    expect(engine.activeAudioSettings, picked96k);
    expect(engine.lastAudioNotice.value, isNull);
  });

  test('the controllers the shell holds survive the restart', () {
    final midiController = engine.midi;
    final chain = engine.midi.chain;
    final editor = engine.midi.editor;
    final stateMachine = engine.stateMachine;
    final runtimeVariables = engine.runtimeVariables;
    final metronome = engine.metronome;
    final library = engine.patchLibrary;

    engine.switchAudioDevice(picked96k);

    expect(engine.midi, same(midiController));
    expect(engine.midi.chain, same(chain));
    expect(engine.midi.editor, same(editor));
    expect(engine.stateMachine, same(stateMachine));
    expect(engine.runtimeVariables, same(runtimeVariables));
    expect(engine.metronome, same(metronome));
    expect(engine.patchLibrary, same(library));
    // Still usable, not merely still referenced: an edit through the editor
    // the shell captured lands in the chain playback reads.
    final before = chain.source.notes.length;
    editor.addNote(
      const MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.8),
    );
    expect(engine.midi.chain.source.notes, hasLength(before + 1));
    expect(editor.canUndo, isTrue);
  });

  test('the mix and the racks re-materialise on the new session', () {
    final oldSynth = engine.midi.synthForVoice('voice.default')!;

    engine.switchAudioDevice(picked96k);

    // `close()` destroyed every channel; the strip is back, at its level.
    expect(yse.channels.values.map((c) => c.name), contains('drums'));
    final drums = engine.channels.value.singleWhere((c) => c.name == 'drums');
    expect(yse.channels[drums.id], isNotNull);
    expect(drums.volume, 0.4);
    // The voice got a fresh engine synth; the old handle was released.
    final newSynth = engine.midi.synthForVoice('voice.default')!;
    expect(newSynth, isNot(same(oldSynth)));
    expect((oldSynth as FakeMaterialisedSynth).isDisposed, isTrue);
    expect((newSynth as FakeMaterialisedSynth).isDisposed, isFalse);
  });

  test('playback, the click and a running patch come back on fresh native '
      'objects', () {
    engine.midi.play();
    final clip = transportOn(engine.midi.editedSession.clockName);
    engine.metronome.setEnabled(true);
    final click = transportOn(MetronomeController.defaultClockName);
    final patch = engine.patchLibrary.openAddress!;
    engine.patchLibrary.place(patch, master);
    expect(engine.patchLibrary.start(patch), isTrue);
    final oldEditor = engine.patcher;
    final oldInstance = engine.patches.instanceIdOf(patch);

    engine.switchAudioDevice(picked96k);

    // The old transports were released before `close()` freed them …
    expect(clip.calls, contains('dispose'));
    expect(click.calls, contains('dispose'));
    // … and fresh ones play on the new session.
    final newClip = transportOn(engine.midi.editedSession.clockName);
    expect(newClip, isNot(same(clip)));
    expect(newClip.isPlaying, isTrue);
    expect(engine.midi.isPlaying, isTrue);
    final newClick = transportOn(MetronomeController.defaultClockName);
    expect(newClick, isNot(same(click)));
    expect(newClick.isPlaying, isTrue);
    expect(engine.metronome.enabled, isTrue);
    // The patch was re-created with its name, re-opened on a fresh editor, and
    // is sounding again.
    expect(engine.patches.instanceIdOf(patch), isNot(oldInstance));
    expect(patcher.instances.containsKey(oldInstance), isFalse);
    expect(engine.patcher, isNot(same(oldEditor)));
    expect(engine.patchLibrary.openAddress, patch);
    expect(engine.patchLibrary.isRunning(patch), isTrue);
  });

  test('the master level and the test signal are re-asserted', () {
    engine.setMasterVolume(0.3);
    engine.setTestSignal(on: true);

    engine.switchAudioDevice(picked96k);

    expect(yse.appliedMasterVolume, closeTo(0.3, 1e-9));
    expect(yse.audioTestOn, isTrue);
  });

  test('a device that cannot run the session rate restarts it at one it '
      'offers, with its own notice', () {
    final ok = engine.switchAudioDevice(
      const AudioSettings(outputHost: 'MME', outputDevice: 'Old Card'),
    );

    expect(ok, isTrue);
    expect(engine.sessionSampleRate, 44100);
    expect(engine.activeAudioSettings?.outputDevice, 'Old Card');
    expect(
      engine.lastAudioNotice.value?.kind,
      AudioNoticeKind.sessionRateUnsupported,
    );
    expect(yse.channels.values.map((c) => c.name), contains('drums'));
  });

  test('a restart whose device refuses reverts and still re-materialises', () {
    engine.switchAudioDevice(
      const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
    );

    final ok = engine.switchAudioDevice(
      const AudioSettings(
        outputHost: 'ASIO',
        outputDevice: 'Flaky',
        sampleRate: 96000,
      ),
    );

    expect(ok, isFalse);
    expect(engine.activeAudioSettings?.outputHost, 'ASIO');
    expect(engine.activeAudioSettings?.outputDevice, 'Fake Interface');
    expect(engine.sessionSampleRate, 48000);
    expect(engine.lastAudioNotice.value?.kind, AudioNoticeKind.switchReverted);
    // The session the revert landed on carries the project too.
    expect(yse.channels.values.map((c) => c.name), contains('drums'));
  });
}
