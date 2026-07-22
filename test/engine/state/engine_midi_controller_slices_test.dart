import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// The clips half of capture-from-live (issue #242):
/// [EngineMidiController.playingClipEntries] lists exactly the playing
/// sessions with clip entity addresses, carrying their live loop flags.
void main() {
  MidiTransformChain seedChain() => MidiTransformChain(
    source: MidiClip(
      bars: 1,
      notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
    ),
  );

  EntityAddress clip(String name) =>
      EntityAddress(kind: 'clip', segments: [name]);

  ClipDocument doc({bool loop = true}) => ClipDocument(
    source: MidiClip(
      bars: 1,
      notes: const [MidiNote(pitch: 64, start: 0, duration: 1, velocity: 1)],
    ),
    loop: loop,
  );

  test('lists playing sessions with their addresses and live loop flags', () {
    fakeAsync((async) {
      final controller = EngineMidiController(
        chain: seedChain(),
        gateway: FakeMidiGateway(),
      );

      // Nothing plays yet.
      expect(controller.playingClipEntries, isEmpty);

      // The boot session has no entity address — playing it contributes
      // nothing to the clips slice.
      controller.play();
      async.elapse(const Duration(milliseconds: 20));
      expect(controller.isPlaying, isTrue);
      expect(controller.playingClipEntries, isEmpty);

      // Two library sessions playing side by side both capture, with their
      // own loop flags.
      controller.ensureSession(clip('drums'), doc(loop: false));
      controller.ensureSession(clip('bass'), doc());
      controller.playSession(clip('drums'));
      controller.playSession(clip('bass'));
      async.elapse(const Duration(milliseconds: 20));
      expect(controller.playingClipEntries, [
        ClipSliceEntry(clip: clip('drums'), loop: false),
        ClipSliceEntry(clip: clip('bass')),
      ]);

      // The loop flag is read live, not at session-open time.
      controller.setSessionLoop(clip('drums'), true);
      expect(controller.playingClipEntries.first.loop, isTrue);

      // A stopped session drops out of the capture; the other keeps playing.
      controller.stopSession(clip('drums'));
      expect(controller.playingClipEntries, [
        ClipSliceEntry(clip: clip('bass')),
      ]);

      controller.dispose();
    });
  });
}
