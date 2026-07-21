import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/metronome_controller.dart';

import 'test_doubles/fake_fx_gateway.dart';
import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_synth_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// `PhiEngine.panic` wiring (issue #264, design §6): the engine composes the
/// MIDI subsystem's panic (sessions + take + voice synths + port + scene) with
/// stopping the click and silencing the reserved click voice. Exercised through
/// the fakes.
void main() {
  late FakeYseGateway yse;
  late FakeSynthGateway synths;
  late FakeFxGateway fxs;
  late FakeMidiGateway midi;
  late PhiEngine engine;

  setUp(() {
    yse = FakeYseGateway();
    synths = FakeSynthGateway();
    fxs = FakeFxGateway();
    midi = FakeMidiGateway();
    engine = PhiEngine(
      yse,
      midiGateway: midi,
      synthGateway: synths,
      fxGateway: fxs,
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await midi.dispose();
    await yse.dispose();
  });

  ProjectRegistry registryWithDrum() {
    final registry = ProjectRegistry();
    registry.createEntity(
      EntityAddress(kind: RegistryKinds.domain, segments: const ['drum']),
      payload: const TimeDomain(name: 'drum', tempo: 124),
    );
    return registry;
  }

  test('panic stops the click and silences the reserved click voice', () {
    final registry = registryWithDrum();
    addTearDown(registry.dispose);

    engine.start();
    engine.bindProject(registry);
    final metronome = engine.metronome;
    metronome.domainName = 'drum';
    metronome.setEnabled(true);

    final clickSynth = synths.synths.single;
    final click = midi.transports.firstWhere(
      (t) => t.clockName == MetronomeController.defaultClockName,
    );
    expect(click.isPlaying, isTrue);

    engine.panic();

    // The click stopped (step 4) and its reserved voice got the all-notes-off
    // safety net (step 2 covers *every* materialised synth).
    expect(metronome.enabled, isFalse);
    expect(click.isPlaying, isFalse);
    expect(clickSynth.noteLog, contains('allNotesOff'));
  });

  test('panic stops a playing clip session and all-notes-off the port', () {
    engine.start();
    engine.midi.play();
    expect(engine.midi.isPlaying, isTrue);

    engine.panic();

    expect(engine.midi.isPlaying, isFalse);
    expect(midi.calls, contains('allNotesOff:all'));
  });

  test('panic is idempotent — a second panic changes nothing', () {
    final registry = registryWithDrum();
    addTearDown(registry.dispose);

    engine.start();
    engine.bindProject(registry);
    engine.metronome.setEnabled(true);
    engine.midi.play();

    engine.panic();
    expect(engine.metronome.enabled, isFalse);
    expect(engine.midi.isPlaying, isFalse);

    // Safe to mash: the second call does not throw and leaves everything stopped.
    engine.panic();
    expect(engine.metronome.enabled, isFalse);
    expect(engine.midi.isPlaying, isFalse);
  });

  test('panic before start is a harmless no-op', () {
    expect(engine.isStarted, isFalse);
    engine.panic(); // no throw
    expect(engine.isStarted, isFalse);
  });
}
