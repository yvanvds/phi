import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/voice/channel_allocation.dart';
import 'package:phi/domain/voice/voice_channel_resolver.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_synth_gateway.dart';

MidiTransformChain _seedChain() => MidiTransformChain(
  source: MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
);

/// Audition path (design §7, issue #211): the immediate note-on / note-off that
/// arm-for-input, the test strip and the roll preview all sound through.
void main() {
  group('EngineMidiController — audition (#211)', () {
    test('internal voice plays its materialised synth directly', () {
      final gateway = FakeMidiGateway();
      final controller = EngineMidiController(
        chain: _seedChain(),
        gateway: gateway,
      );
      addTearDown(controller.dispose);
      final synth = FakeMaterialisedSynth(const SineSynth(), channel: 4);
      controller.bindVoices(VoiceChannelResolver.seededDefault(), {
        'voice.bells': synth,
      });

      controller.auditionNoteOn('voice.bells', 64, velocity: 127);
      expect(synth.noteLog, ['on:64@1.00']);
      expect(synth.heldNotes, contains(64));

      controller.auditionNoteOff('voice.bells', 64);
      expect(synth.noteLog, ['on:64@1.00', 'off:64']);
      expect(synth.heldNotes, isEmpty);
    });

    test('external voice sends to the open output on its wire channel', () {
      final gateway = FakeMidiGateway();
      final controller = EngineMidiController(
        chain: _seedChain(),
        gateway: gateway,
      );
      addTearDown(controller.dispose);
      controller.bindVoices(
        const VoiceChannelResolver(
          allocation: ChannelAllocation.empty(),
          externalChannels: {'voice.ext': 3},
        ),
        const {},
      );
      gateway.calls.clear();

      controller.auditionNoteOn('voice.ext', 60, velocity: 90);
      // Channel 3 (1-based voice channel) → wire channel 2.
      expect(gateway.calls, contains('sendNoteOn:2:60:90'));

      controller.auditionNoteOff('voice.ext', 60);
      expect(gateway.calls, contains('sendNoteOff:2:60'));
    });

    test('an unresolved voice sounds nothing (no throw)', () {
      final gateway = FakeMidiGateway();
      final controller = EngineMidiController(
        chain: _seedChain(),
        gateway: gateway,
      );
      addTearDown(controller.dispose);
      controller.bindVoices(VoiceChannelResolver.seededDefault(), const {});
      gateway.calls.clear();

      controller.auditionNoteOn('voice.nope', 50);
      controller.auditionNoteOff('voice.nope', 50);
      expect(gateway.calls, isEmpty);
    });

    test('auditionPreview sounds now and releases after the hold', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _seedChain(),
          gateway: gateway,
        );
        final synth = FakeMaterialisedSynth(const SineSynth(), channel: 1);
        controller.bindVoices(VoiceChannelResolver.seededDefault(), {
          'voice.default': synth,
        });

        controller.auditionPreview(
          'voice.default',
          60,
          hold: const Duration(milliseconds: 120),
        );
        // Sounds immediately…
        expect(synth.heldNotes, contains(60));
        // …and is released once the hold elapses.
        async.elapse(const Duration(milliseconds: 120));
        expect(synth.heldNotes, isEmpty);

        controller.dispose();
      });
    });
  });
}
