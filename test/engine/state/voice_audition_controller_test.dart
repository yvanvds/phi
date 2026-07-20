import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/voice/voice_channel_resolver.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';
import 'package:phi/engine/state/voice_audition_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_synth_gateway.dart';

MidiTransformChain _seedChain() => MidiTransformChain(
  source: MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
);

/// Flush the microtask/timer queue so a broadcast MIDI-in event reaches the
/// controller's subscription before the assertion.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('VoiceAuditionController (#211)', () {
    late FakeMidiGateway gateway;
    late EngineMidiController midi;
    late FakeMaterialisedSynth synthA;
    late FakeMaterialisedSynth synthB;
    late VoiceAuditionController arm;

    final voiceA = EntityAddress.parse('voice.a');
    final voiceB = EntityAddress.parse('voice.b');

    setUp(() {
      gateway = FakeMidiGateway();
      midi = EngineMidiController(chain: _seedChain(), gateway: gateway);
      synthA = FakeMaterialisedSynth(const SineSynth(), channel: 1);
      synthB = FakeMaterialisedSynth(const SineSynth(), channel: 2);
      midi.bindVoices(VoiceChannelResolver.seededDefault(), {
        'voice.a': synthA,
        'voice.b': synthB,
      });
      arm = VoiceAuditionController(midi: midi);
    });

    tearDown(() async {
      arm.dispose();
      midi.dispose();
      await gateway.dispose();
    });

    test('single-arm invariant: arming one voice disarms the other', () {
      arm.arm(voiceA);
      expect(arm.armed, voiceA);
      expect(arm.isArmed(voiceA), isTrue);

      arm.arm(voiceB);
      expect(arm.armed, voiceB);
      expect(arm.isArmed(voiceA), isFalse);
      expect(arm.isArmed(voiceB), isTrue);

      // Toggling the armed voice disarms it.
      arm.toggleArm(voiceB);
      expect(arm.armed, isNull);
    });

    test('MIDI-in plays the armed voice through the fake gateway', () async {
      arm.arm(voiceA);
      gateway.emitNoteOn('port', 60, 100);
      await _pump();
      // 100 / 127 ≈ 0.79.
      expect(synthA.noteLog, ['on:60@0.79']);

      gateway.emitNoteOff('port', 60);
      await _pump();
      expect(synthA.heldNotes, isEmpty);
      // The unarmed voice never sounded.
      expect(synthB.noteLog, isEmpty);
    });

    test('MIDI-in with nothing armed sounds nothing', () async {
      gateway.emitNoteOn('port', 60, 100);
      await _pump();
      expect(synthA.noteLog, isEmpty);
      expect(synthB.noteLog, isEmpty);
    });

    test('incoming channel is ignored — arm overrides routing', () async {
      arm.arm(voiceB);
      // A note on any channel plays the armed voice.
      gateway.emitNoteOn('port', 67, 80, channel: 9);
      await _pump();
      expect(synthB.heldNotes, contains(67));
      expect(synthA.noteLog, isEmpty);
    });

    test('the test strip presses / releases the armed voice', () {
      arm.arm(voiceB);
      arm.pressKey(64);
      expect(synthB.heldNotes, contains(64));
      arm.releaseKey(64);
      expect(synthB.heldNotes, isEmpty);
    });

    test('the test strip is silent with nothing armed', () {
      arm.pressKey(64);
      expect(synthA.heldNotes, isEmpty);
      expect(synthB.heldNotes, isEmpty);
    });

    test('disarming releases any held note', () {
      arm.arm(voiceA);
      arm.pressKey(62);
      expect(synthA.heldNotes, contains(62));

      arm.disarm();
      expect(synthA.heldNotes, isEmpty);
    });

    test('re-arming mid-hold releases the previous voice', () async {
      arm.arm(voiceA);
      gateway.emitNoteOn('port', 65, 100);
      await _pump();
      expect(synthA.heldNotes, contains(65));

      arm.arm(voiceB); // switch while a note is held
      expect(synthA.heldNotes, isEmpty);
    });

    test('notifies listeners on arm changes', () {
      var notifications = 0;
      arm.addListener(() => notifications++);
      arm.arm(voiceA);
      arm.arm(voiceB);
      arm.disarm();
      expect(notifications, 3);
    });
  });
}
