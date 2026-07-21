import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/edit/add_note_command.dart';
import 'package:phi/domain/midi/edit/clip_edit_command.dart';
import 'package:phi/domain/midi/edit/composite_clip_command.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/record/take_recorder.dart';
import 'package:phi/domain/project/entity_address.dart';

/// A hand-driven beat clock: the injected clock reader returns whatever [beat]
/// currently holds, so a test advances the transport by writing to it.
class _FakeClock {
  double beat = 0;
  double read() => beat;
}

/// Builds a recorder over a fresh clip, wiring the fake clock and collecting the
/// per-pass command batches it commits. Applying a batch mutates [clip] exactly
/// as the real undo scope would.
class _Harness {
  _Harness({int bars = 2, int beatsPerBar = 4, this.clipAddress}) {
    clip = MidiClip(bars: bars, beatsPerBar: beatsPerBar, notes: const []);
    recorder = TakeRecorder(
      clip: clip,
      clock: clock.read,
      commit: batches.add,
      clipAddress: clipAddress,
    );
  }

  final EntityAddress? clipAddress;
  final _FakeClock clock = _FakeClock();
  final List<ClipEditCommand> batches = [];
  late final MidiClip clip;
  late final TakeRecorder recorder;

  /// Apply every collected batch onto the clip (what running them through the
  /// undo scope would do), so assertions can read the resulting notes.
  void applyAll() {
    for (final b in batches) {
      b.apply();
    }
  }
}

void main() {
  group('TakeRecorder — pairing', () {
    test('an on/off pair becomes one note stamped from the clock', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 1.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 2.5;
      h.recorder.noteOff(60);
      h.recorder.stop();

      h.applyAll();
      final note = h.clip.notes.single;
      expect(note.pitch, 60.0);
      expect(note.start, 1.0);
      expect(note.duration, 1.5);
      // Velocity kept, normalised to [0, 1].
      expect(note.velocity, closeTo(100 / 127.0, 1e-9));
    });

    test('captures pitch and timings raw — no snapping or rounding', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.31;
      h.recorder.noteOn(61, 63);
      h.clock.beat = 0.7777;
      h.recorder.noteOff(61);
      h.recorder.stop();

      h.applyAll();
      final note = h.clip.notes.single;
      expect(note.start, 0.31);
      expect(note.duration, closeTo(0.4677, 1e-9));
      expect(note.pitch, 61.0);
    });

    test('overlapping notes pair by pitch independently', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 0.5;
      h.recorder.noteOn(64, 80);
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.clock.beat = 2.0;
      h.recorder.noteOff(64);
      h.recorder.stop();

      h.applyAll();
      final byPitch = {for (final n in h.clip.notes) n.pitch: n};
      expect(byPitch[60.0]!.start, 0.0);
      expect(byPitch[60.0]!.duration, 1.0);
      expect(byPitch[64.0]!.start, 0.5);
      expect(byPitch[64.0]!.duration, 1.5);
    });

    test('events before start and after stop are ignored', () {
      final h = _Harness();
      h.clock.beat = 0.5;
      h.recorder.noteOn(60, 100); // before start — ignored
      h.recorder.start();
      h.clock.beat = 1.0;
      h.recorder.noteOn(62, 100);
      h.clock.beat = 1.5;
      h.recorder.noteOff(62);
      h.recorder.stop();
      h.clock.beat = 2.0;
      h.recorder.noteOn(64, 100); // after stop — ignored
      h.recorder.noteOff(64);

      h.applyAll();
      expect(h.clip.notes.single.pitch, 62.0);
      expect(h.recorder.isRecording, isFalse);
    });
  });

  group('TakeRecorder — orphan-off handling', () {
    test('a note-off with no matching note-on is ignored', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 1.0;
      h.recorder.noteOff(60); // orphan — never turned on
      h.recorder.stop();

      expect(h.batches, isEmpty);
      h.applyAll();
      expect(h.clip.notes, isEmpty);
    });

    test('a double note-off closes once, the second is ignored', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.clock.beat = 2.0;
      h.recorder.noteOff(60); // orphan second off
      h.recorder.stop();

      h.applyAll();
      final note = h.clip.notes.single;
      expect(note.duration, 1.0);
    });

    test('a re-press of a held pitch closes the earlier segment', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 1.0;
      h.recorder.noteOn(60, 100); // re-press without an off
      h.clock.beat = 2.0;
      h.recorder.noteOff(60);
      h.recorder.stop();

      h.applyAll();
      expect(h.clip.notes.length, 2);
      final starts = h.clip.notes.map((n) => n.start).toList()..sort();
      expect(starts, [0.0, 1.0]);
    });
  });

  group('TakeRecorder — stop closing', () {
    test('a note held at stop closes at the stop beat', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.5;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 3.25;
      h.recorder.stop(); // never released

      h.applyAll();
      final note = h.clip.notes.single;
      expect(note.start, 0.5);
      expect(note.duration, closeTo(2.75, 1e-9));
    });
  });

  group('TakeRecorder — loop wrap closing', () {
    test(
      'a note crossing the wrap closes at the loop end and reopens at 0',
      () {
        // A 2-bar / 4-beat clip → loop end at beat 8.
        final h = _Harness();
        h.recorder.start();
        h.clock.beat = 6.0;
        h.recorder.noteOn(60, 100); // held into the wrap
        // Loop wraps at beat 8; the transport rolls back to ~0.
        h.recorder.wrap();
        h.clock.beat = 1.0;
        h.recorder.noteOff(60); // released early in the next pass
        h.recorder.stop();

        h.applyAll();
        final byStart = h.clip.notes.toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        expect(byStart.length, 2);
        // Reopened segment: 0 → 1, same pitch/velocity/voice.
        expect(byStart[0].start, 0.0);
        expect(byStart[0].duration, 1.0);
        expect(byStart[0].pitch, 60.0);
        // First segment: 6 → 8 (closed at the loop end).
        expect(byStart[1].start, 6.0);
        expect(byStart[1].duration, 2.0);
      },
    );

    test('a note released before the wrap does not reopen', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 2.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 3.0;
      h.recorder.noteOff(60);
      h.recorder.wrap();
      h.recorder.stop();

      h.applyAll();
      expect(h.clip.notes.single.start, 2.0);
      expect(h.clip.notes.single.duration, 1.0);
    });

    test('a note held across two wraps yields three source notes', () {
      final h = _Harness(); // loop end at beat 8
      h.recorder.start();
      h.clock.beat = 4.0;
      h.recorder.noteOn(72, 90); // held across the whole recording
      h.recorder.wrap(); // 4 → 8, reopen at 0
      h.recorder.wrap(); // 0 → 8, reopen at 0
      h.clock.beat = 2.0;
      h.recorder.stop(); // 0 → 2

      h.applyAll();
      final durations = h.clip.notes.map((n) => n.duration).toList()..sort();
      expect(durations, [2.0, 4.0, 8.0]);
      expect(h.clip.notes.every((n) => n.pitch == 72.0), isTrue);
    });
  });

  group('TakeRecorder — per-pass batches', () {
    test('all notes of one pass commit as a single batch', () {
      final h = _Harness();
      h.recorder.start();
      for (var i = 0; i < 3; i++) {
        h.clock.beat = i.toDouble();
        h.recorder.noteOn(60 + i, 100);
        h.clock.beat = i + 0.5;
        h.recorder.noteOff(60 + i);
      }
      h.recorder.stop();

      expect(h.batches.length, 1);
      expect(h.batches.single, isA<CompositeClipCommand>());
      h.applyAll();
      expect(h.clip.notes.length, 3);
    });

    test('each loop pass is its own batch', () {
      final h = _Harness();
      h.recorder.start();
      // Pass 1: two notes.
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.clock.beat = 2.0;
      h.recorder.noteOn(62, 100);
      h.clock.beat = 3.0;
      h.recorder.noteOff(62);
      h.recorder.wrap();
      // Pass 2: one note.
      h.clock.beat = 1.0;
      h.recorder.noteOn(64, 100);
      h.clock.beat = 1.5;
      h.recorder.noteOff(64);
      h.recorder.stop();

      expect(h.batches.length, 2);
      expect(h.batches[0], isA<CompositeClipCommand>());
      expect(h.batches[1], isA<AddNoteCommand>());
    });

    test('a single-note pass commits a bare AddNoteCommand', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.recorder.stop();

      expect(h.batches.single, isA<AddNoteCommand>());
    });

    test('an empty pass commits nothing', () {
      final h = _Harness();
      h.recorder.start();
      h.recorder.wrap(); // nothing played this pass
      h.recorder.stop(); // nothing held
      expect(h.batches, isEmpty);
    });

    test('a committed pass is undoable as one step', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 0.5;
      h.recorder.noteOff(60);
      h.clock.beat = 0.5;
      h.recorder.noteOn(62, 100);
      h.clock.beat = 1.0;
      h.recorder.noteOff(62);
      h.recorder.stop();

      final batch = h.batches.single;
      batch.apply();
      expect(h.clip.notes.length, 2);
      batch.revert(); // one Ctrl+Z removes the whole pass
      expect(h.clip.notes, isEmpty);
    });

    test('batches carry the clip address for dirty-tracking / journaling', () {
      final address = EntityAddress.parse('clip.lead');
      final h = _Harness(clipAddress: address);
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.recorder.stop();

      expect(h.batches.single.entitiesTouched, {address});
    });
  });

  group('TakeRecorder — armed-voice tagging', () {
    test('captured notes carry the armed voice', () {
      final h = _Harness();
      h.recorder.voice = 'voice.bells';
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.recorder.stop();

      h.applyAll();
      expect(h.clip.notes.single.voice, 'voice.bells');
    });

    test('an unrouted take leaves the voice null', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.recorder.stop();

      h.applyAll();
      expect(h.clip.notes.single.voice, isNull);
    });

    test('the voice is stamped at note-on; a re-arm mid-hold does not '
        'retag a held note', () {
      final h = _Harness();
      h.recorder.voice = 'voice.a';
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100); // stamped voice.a
      h.recorder.voice = 'voice.b'; // re-arm while held
      h.clock.beat = 0.5;
      h.recorder.noteOn(64, 100); // stamped voice.b
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.recorder.noteOff(64);
      h.recorder.stop();

      h.applyAll();
      final byPitch = {for (final n in h.clip.notes) n.pitch: n.voice};
      expect(byPitch[60.0], 'voice.a');
      expect(byPitch[64.0], 'voice.b');
    });

    test('a note reopened across the wrap keeps its original voice', () {
      final h = _Harness();
      h.recorder.voice = 'voice.a';
      h.recorder.start();
      h.clock.beat = 6.0;
      h.recorder.noteOn(60, 100);
      h.recorder.voice = 'voice.b'; // re-arm before the wrap
      h.recorder.wrap();
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.recorder.stop();

      h.applyAll();
      // Both segments of the same physical hold keep voice.a.
      expect(h.clip.notes.every((n) => n.voice == 'voice.a'), isTrue);
    });
  });

  group('TakeRecorder — lifecycle', () {
    test('hasPendingNotes tracks held and finished-but-uncommitted notes', () {
      final h = _Harness();
      expect(h.recorder.hasPendingNotes, isFalse);
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      expect(h.recorder.hasPendingNotes, isTrue); // held
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      expect(h.recorder.hasPendingNotes, isTrue); // finished, awaiting boundary
      h.recorder.stop();
      expect(h.recorder.hasPendingNotes, isFalse); // committed
    });

    test('start is a no-op while already recording', () {
      final h = _Harness();
      h.recorder.start();
      h.clock.beat = 0.0;
      h.recorder.noteOn(60, 100);
      h.recorder.start(); // must not wipe the held note
      h.clock.beat = 1.0;
      h.recorder.noteOff(60);
      h.recorder.stop();

      h.applyAll();
      expect(h.clip.notes.single.pitch, 60.0);
    });
  });
}
