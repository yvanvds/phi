import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/spawn_axis.dart';
import 'package:phi/domain/midi/spawn_source.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/voice/voice_channel_resolver.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_scene_renderer.dart';
import '../test_doubles/fake_synth_gateway.dart';

/// A blank 2-bar clip (8 beats) — a take target with no notes yet.
MidiTransformChain _blankChain({int bars = 2, int beatsPerBar = 4}) =>
    MidiTransformChain(
      source: MidiClip(bars: bars, beatsPerBar: beatsPerBar, notes: const []),
    );

/// A one-bar clip whose single note fills the whole bar and drives a spawn — so
/// a playing session has a live scene agent for panic to clear.
MidiTransformChain _spawnChain() => MidiTransformChain(
  source: MidiClip(
    bars: 1,
    notes: const [
      MidiNote(pitch: 60, start: 0.0, duration: 4.0, velocity: 1.0),
    ],
  ),
  transforms: [
    AgentSpawnTransform(
      x: SpawnAxis.of(SpawnSource.pitch, outMin: 0, outMax: 127),
      y: SpawnAxis.of(SpawnSource.velocity, outMin: 0, outMax: 1),
      z: SpawnAxis.of(SpawnSource.time, outMin: 0, outMax: 4),
      label: 'spawn',
    ),
  ],
);

void main() {
  group('EngineMidiController — panic (issue #264, design §6)', () {
    test('stops the playing session (rewind) and all-notes-off the port', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _blankChain(),
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 500)); // 1 beat in
        expect(controller.isPlaying, isTrue);
        expect(controller.playhead.value, greaterThan(0));

        controller.panic();

        // Step 1: every session stopped and rewound.
        expect(controller.isPlaying, isFalse);
        expect(controller.playhead.value, 0);
        expect(gateway.transport!.isPlaying, isFalse);
        // Step 2: the MIDI-out port silenced on all channels.
        expect(gateway.calls, contains('allNotesOff:all'));

        controller.dispose();
      });
    });

    test('ends the armed take but keeps its notes (survival)', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _blankChain(),
          gateway: gateway,
        );

        controller.record.arm();
        controller.play(); // no count-in → take starts at once
        expect(controller.record.isRecording, isTrue);

        // Play a note ~1 beat in, released half a beat later.
        async.elapse(const Duration(milliseconds: 500));
        gateway.emitNoteOn('Fake MIDI In', 60, 100);
        async.elapse(const Duration(milliseconds: 250));
        gateway.emitNoteOff('Fake MIDI In', 60);

        controller.panic();

        // The take ended, but its note survived as authored content.
        expect(controller.record.isRecording, isFalse);
        expect(controller.isPlaying, isFalse);
        final note = controller.editedSession.clip.notes.single;
        expect(note.pitch, 60.0);
        expect(note.start, greaterThan(0.0));

        controller.dispose();
      });
    });

    test('all-notes-off every materialised voice synth', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _blankChain(),
          gateway: gateway,
        );

        // A materialised voice synth holding an audition note (the arm-for-input /
        // test-strip path presses notes on the synth directly, outside any
        // transport — exactly what needs releasing on panic).
        final synth = FakeMaterialisedSynth(
          const SineSynth(voiceCount: 1),
          channel: 1,
        );
        controller.bindVoices(VoiceChannelResolver.seededDefault(), {
          'voice.lead': synth,
        });
        synth.noteOn(72);
        expect(synth.heldNotes, isNotEmpty);

        controller.panic();

        expect(synth.heldNotes, isEmpty);
        expect(synth.noteLog, contains('allNotesOff'));

        controller.dispose();
      });
    });

    test('clears every live scene agent (pending spawns despawn)', () {
      fakeAsync((async) {
        final renderer = FakeSceneRenderer();
        final controller = EngineMidiController(
          chain: _spawnChain(),
          gateway: FakeMidiGateway(),
          agentSink: renderer,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 300)); // the note-on spawned
        expect(renderer.lastAgents, isNotEmpty);

        // A demo agent lives outside any session's band — panic must clear the
        // whole field, not just the playing session's own agents.
        controller.loadSceneDemo();
        expect(renderer.lastAgents, isNotEmpty);

        controller.panic();

        expect(renderer.lastAgents, isEmpty);
        expect(controller.field.isEmpty, isTrue);
        expect(controller.isSceneDemoLoaded, isFalse);

        controller.dispose();
      });
    });

    test('double-panic is a no-op (idempotent, safe to mash)', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _blankChain(),
          gateway: gateway,
        );

        controller.record.arm();
        controller.play();
        async.elapse(const Duration(milliseconds: 500));
        gateway.emitNoteOn('Fake MIDI In', 64, 100);
        async.elapse(const Duration(milliseconds: 250));
        gateway.emitNoteOff('Fake MIDI In', 64);

        controller.panic();
        final notesAfterFirst = controller.editedSession.clip.notes.length;
        expect(notesAfterFirst, 1);

        // A second panic changes nothing: the take is not re-committed, the
        // session stays stopped, the scene stays empty.
        controller.panic();
        expect(controller.editedSession.clip.notes.length, notesAfterFirst);
        expect(controller.isPlaying, isFalse);
        expect(controller.record.isRecording, isFalse);
        expect(controller.field.isEmpty, isTrue);

        controller.dispose();
      });
    });

    test('panic on an idle controller is a harmless no-op', () {
      fakeAsync((async) {
        final controller = EngineMidiController(
          chain: _blankChain(),
          gateway: FakeMidiGateway(),
        );

        controller.panic();
        expect(controller.isPlaying, isFalse);
        expect(controller.record.isRecording, isFalse);

        controller.dispose();
      });
    });
  });
}
