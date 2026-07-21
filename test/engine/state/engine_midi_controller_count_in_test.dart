import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_midi_transport.dart';

/// A clip with the given meter and no notes — a blank take target.
MidiTransformChain _chain({int bars = 2, int beatsPerBar = 4}) =>
    MidiTransformChain(
      source: MidiClip(bars: bars, beatsPerBar: beatsPerBar, notes: const []),
    );

/// The reserved count-in clock the controller minted, or a failure if none.
FakeMidiTransport countClockOf(FakeMidiGateway gateway) {
  final t = gateway.transports
      .where((t) => t.clockName == EngineMidiController.countInClockName)
      .lastOrNull;
  expect(t, isNotNull, reason: 'a count-in clock should have been minted');
  return t!;
}

void main() {
  group('EngineMidiController — count-in against the engine clock (#263)', () {
    // At the 120-BPM default, one beat is 500ms; a 4/4 bar is 2000ms.

    test('a fresh play waits the count-in, then starts on the downbeat', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _chain(),
          gateway: gateway,
        )..countIn.bars = 1;

        controller.play();
        // Immediately: counting on a running clock, but the session has NOT
        // started — no playhead motion, no transport yet.
        expect(controller.countIn.isCounting, isTrue);
        expect(controller.isPlaying, isFalse);
        expect(controller.playhead.value, 0);
        final countClock = countClockOf(gateway);
        expect(countClock.isPlaying, isTrue);
        expect(countClock.tempo, 120);

        // Halfway through the bar (2 of 4 beats): still counting.
        async.elapse(const Duration(seconds: 1));
        expect(controller.countIn.isCounting, isTrue);
        expect(controller.isPlaying, isFalse);

        // Past the downbeat: the session starts and the count clock idles.
        async.elapse(const Duration(milliseconds: 1100));
        expect(controller.countIn.isCounting, isFalse);
        expect(controller.isPlaying, isTrue);
        expect(countClock.isPlaying, isFalse);

        controller.stop();
        controller.dispose();
      });
    });

    test('record is deferred, and capture begins on the downbeat', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _chain(),
          gateway: gateway,
        )..countIn.bars = 1;

        controller.record.arm();
        controller.play();
        // Armed, but the take waits for the downbeat with playback.
        expect(controller.record.isRecording, isFalse);

        async.elapse(const Duration(milliseconds: 2100)); // past one bar
        expect(controller.isPlaying, isTrue);
        expect(controller.record.isRecording, isTrue);

        // Play a note one beat (500ms) after the downbeat, released half a beat
        // later. It must land ~1 beat in — measured from the downbeat, NOT from
        // the count-in origin (which would be ~5 beats).
        async.elapse(const Duration(milliseconds: 500));
        gateway.emitNoteOn('Fake MIDI In', 60, 100);
        async.elapse(const Duration(milliseconds: 250));
        gateway.emitNoteOff('Fake MIDI In', 60);
        controller.stop();

        final note = controller.editedSession.clip.notes.single;
        expect(note.pitch, 60.0);
        expect(note.start, greaterThan(0.0));
        expect(
          note.start,
          lessThan(2.0),
          reason: 'capture began on the downbeat, not during the count',
        );

        controller.dispose();
      });
    });

    test('a stop during the count aborts cleanly — nothing ever starts', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _chain(),
          gateway: gateway,
        )..countIn.bars = 2;

        controller.play();
        expect(controller.countIn.isCounting, isTrue);
        async.elapse(const Duration(milliseconds: 500));

        controller.stop();
        expect(controller.countIn.isCounting, isFalse);
        expect(controller.isPlaying, isFalse);
        expect(countClockOf(gateway).isPlaying, isFalse);

        // Elapsing long past the old target never sneaks playback in.
        async.elapse(const Duration(seconds: 6));
        expect(controller.isPlaying, isFalse);

        controller.dispose();
      });
    });

    test('a punch-in into an already-running session ignores the count-in', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _chain(),
          gateway: gateway,
        );

        // Start playing with no count set.
        controller.play();
        async.elapse(const Duration(milliseconds: 40));
        expect(controller.isPlaying, isTrue);

        // Now raise the count-in and arm: arming while already playing punches in
        // at once — the count-in is bypassed (design §5).
        controller.countIn.bars = 2;
        controller.record.arm();
        expect(controller.countIn.isCounting, isFalse);
        expect(controller.record.isRecording, isTrue);

        controller.stop();
        controller.dispose();
      });
    });

    test('a 0-bar setting plays immediately with no count clock', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _chain(),
          gateway: gateway,
        );
        // bars defaults to 0.
        controller.play();
        async.elapse(const Duration(milliseconds: 40));

        expect(controller.isPlaying, isTrue);
        expect(controller.countIn.isCounting, isFalse);
        expect(
          gateway.transports.any(
            (t) => t.clockName == EngineMidiController.countInClockName,
          ),
          isFalse,
        );

        controller.stop();
        controller.dispose();
      });
    });

    test('the count length follows the edited clip meter', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        // 3/4 → one bar is 3 beats = 1500ms at 120 BPM.
        final controller = EngineMidiController(
          chain: _chain(beatsPerBar: 3),
          gateway: gateway,
        )..countIn.bars = 1;

        controller.play();
        async.elapse(const Duration(milliseconds: 1400)); // < 3 beats
        expect(controller.isPlaying, isFalse);
        async.elapse(const Duration(milliseconds: 200)); // now > 3 beats
        expect(controller.isPlaying, isTrue);

        controller.stop();
        controller.dispose();
      });
    });

    test('a repeated play press while counting does not restart the count', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _chain(),
          gateway: gateway,
        )..countIn.bars = 2;

        controller.play();
        async.elapse(
          const Duration(seconds: 1),
        ); // 2 beats into an 8-beat count
        final remainingBefore = controller.countIn.beatsRemaining;

        controller.play(); // a second press mid-count is ignored
        expect(controller.countIn.beatsRemaining, remainingBefore);
        expect(controller.isPlaying, isFalse);

        controller.stop();
        controller.dispose();
      });
    });
  });
}
