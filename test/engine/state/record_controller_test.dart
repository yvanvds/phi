import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/edit/add_note_command.dart';
import 'package:phi/domain/midi/edit/composite_clip_command.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/undo_scope.dart';
import 'package:phi/engine/bridge/midi_input_event.dart';
import 'package:phi/engine/state/record_controller.dart';
import 'package:phi/engine/state/record_target.dart';

/// A hand-driven [RecordTarget]: a real [MidiClip] + [UndoScope] (so recorded
/// passes commit and undo for real), with [recordBeat], [autoExtend] and
/// [isPlaying] written directly — the "fake session" the flow records into.
class _FakeTarget implements RecordTarget {
  _FakeTarget({int bars = 2, int beatsPerBar = 4})
    : clip = MidiClip(bars: bars, beatsPerBar: beatsPerBar, notes: const []),
      undoScope = UndoScope(id: 'test-midi');

  @override
  final MidiClip clip;
  @override
  final UndoScope undoScope;
  @override
  bool autoExtend = false;
  @override
  final EntityAddress? address = EntityAddress.parse('clip.lead');
  @override
  double recordBeat = 0;
  @override
  bool isPlaying = false;
}

void main() {
  late _FakeTarget target;
  late StreamController<MidiInputEvent> input;
  late RecordController controller;
  String? armedVoice;

  setUp(() {
    target = _FakeTarget();
    armedVoice = null;
    // A synchronous broadcast controller so `add` delivers to the recorder in
    // line — the clock read on note-on is exactly the [recordBeat] just set.
    input = StreamController<MidiInputEvent>.broadcast(sync: true);
    controller = RecordController(
      input: input.stream,
      target: () => target,
      armedVoice: () => armedVoice,
    );
  });

  tearDown(() async {
    controller.dispose();
    await input.close();
    target.undoScope.dispose();
  });

  void noteOn(int note, int velocity, {required double at}) {
    target.recordBeat = at;
    input.add(
      MidiInputEvent(
        type: MidiInputEventType.noteOn,
        note: note,
        velocity: velocity,
        channel: 1,
        port: 'p',
      ),
    );
  }

  void noteOff(int note, {required double at}) {
    target.recordBeat = at;
    input.add(
      MidiInputEvent(
        type: MidiInputEventType.noteOff,
        note: note,
        velocity: 0,
        channel: 1,
        port: 'p',
      ),
    );
  }

  group('arm', () {
    test('arming while stopped does not start a take', () {
      controller.arm();
      expect(controller.armed, isTrue);
      expect(controller.isRecording, isFalse);
    });

    test('arm + play starts a take; stop ends it and keeps the note', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();
      expect(controller.isRecording, isTrue);

      noteOn(60, 100, at: 1.0);
      noteOff(60, at: 2.5);
      controller.onTransportStop();

      expect(controller.isRecording, isFalse);
      final note = target.clip.notes.single;
      expect(note.pitch, 60.0);
      expect(note.start, 1.0);
      expect(note.duration, 2.5 - 1.0);
      expect(note.velocity, closeTo(100 / 127.0, 1e-9));
    });

    test('play while disarmed captures nothing', () {
      target.isPlaying = true;
      controller.onTransportPlay();
      noteOn(60, 100, at: 0.0);
      noteOff(60, at: 1.0);
      controller.onTransportStop();
      expect(target.clip.notes, isEmpty);
    });

    test('toggleArm notifies listeners', () {
      var notified = 0;
      controller.addListener(() => notified++);
      controller.toggleArm();
      expect(controller.armed, isTrue);
      controller.toggleArm();
      expect(controller.armed, isFalse);
      expect(notified, 2);
    });

    test('disarming mid-take ends the take but keeps the notes', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();
      noteOn(60, 100, at: 0.0);
      noteOff(60, at: 1.0);
      controller.disarm();

      expect(controller.armed, isFalse);
      expect(controller.isRecording, isFalse);
      expect(target.clip.notes.single.pitch, 60.0);
    });
  });

  group('punch-in', () {
    test('arming while already playing punches in at the live beat', () {
      target.isPlaying = true;
      target.recordBeat = 3.0;
      controller.arm(); // punch-in
      expect(controller.isRecording, isTrue);

      noteOn(64, 100, at: 3.5);
      noteOff(64, at: 4.0);
      controller.onTransportStop();

      final note = target.clip.notes.single;
      expect(note.pitch, 64.0);
      expect(note.start, 3.5); // clip-relative, well inside the 8-beat loop
    });

    test('a punch-in mid-loop does not fire a stale wrap on the first tick', () {
      // 8-beat loop; punch in at beat 3, then a tick still inside the first lap.
      target.isPlaying = true;
      target.recordBeat = 3.0;
      controller.arm();
      noteOn(60, 100, at: 3.0);
      target.recordBeat = 3.9;
      controller.tick(); // still lap 0 — no wrap, nothing committed yet
      expect(target.clip.notes, isEmpty);
      noteOff(60, at: 3.9);
      controller.onTransportStop();
      expect(target.clip.notes.single.duration, closeTo(0.9, 1e-9));
    });
  });

  group('overdub passes (auto-extend off)', () {
    test('each loop pass is one undo step; Ctrl+Z peels newest-first', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();

      // Pass 1: note 60 at beats 1..2.
      noteOn(60, 100, at: 1.0);
      noteOff(60, at: 2.0);
      // Cross the 8-beat loop boundary → wrap commits pass 1.
      target.recordBeat = 8.1;
      controller.tick();
      expect(
        target.clip.notes.map((n) => n.pitch),
        [60.0],
        reason: 'pass 1 committed live at the wrap (ghost refresh mid-take)',
      );
      expect(controller.isRecording, isTrue);

      // Pass 2 (second lap): note 62 at clip-relative 1..2 (beats 9..10).
      noteOn(62, 100, at: 9.0);
      noteOff(62, at: 10.0);
      controller.onTransportStop();

      expect(target.clip.notes.map((n) => n.pitch).toList()..sort(), [
        60.0,
        62.0,
      ]);
      expect(target.clip.notes.firstWhere((n) => n.pitch == 62.0).start, 1.0);

      // Two passes → two undo steps, peeled newest-first.
      target.undoScope.undo();
      expect(target.clip.notes.map((n) => n.pitch), [60.0]);
      target.undoScope.undo();
      expect(target.clip.notes, isEmpty);
    });

    test('a note held across the wrap splits into two source notes', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();

      noteOn(72, 90, at: 6.0); // held into the wrap
      target.recordBeat = 8.2;
      controller.tick(); // wrap: close at 8, reopen at 0
      noteOff(72, at: 9.0); // 8 + 1 → clip-relative 1.0
      controller.onTransportStop();

      final byStart = target.clip.notes.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      expect(byStart.length, 2);
      expect(byStart[0].start, 0.0);
      expect(byStart[0].duration, 1.0);
      expect(byStart[1].start, 6.0);
      expect(byStart[1].duration, 2.0); // closed at the loop end (beat 8)
    });
  });

  group('auto-extend on (grow)', () {
    setUp(() => target.autoExtend = true);

    test('playing past the end grows the clip; the note is not wrapped', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();

      noteOn(60, 100, at: 2.0);
      // A tick well past the 8-beat end must NOT wrap in grow mode.
      target.recordBeat = 10.0;
      controller.tick();
      expect(target.clip.notes, isEmpty); // nothing committed until stop

      noteOff(60, at: 10.0);
      controller.onTransportStop();

      // One continuous note 2..10, and the clip grew to contain it (3 bars).
      final note = target.clip.notes.single;
      expect(note.start, 2.0);
      expect(note.duration, 8.0);
      expect(target.clip.bars, 3); // ceil(10 / 4) = 3 bars

      // Length grow + note are one undo step (composite): one undo restores both.
      target.undoScope.undo();
      expect(target.clip.notes, isEmpty);
      expect(target.clip.bars, 2);
    });

    test('a take that stays within the length does not grow or wrap', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();
      noteOn(60, 100, at: 1.0);
      noteOff(60, at: 3.0);
      controller.onTransportStop();

      expect(target.clip.bars, 2); // unchanged
      expect(target.clip.notes.single, isA<Object>());
      expect(target.undoScope.canUndo, isTrue);
    });
  });

  group('command shape', () {
    test('a single-note pass commits a bare AddNoteCommand', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();
      noteOn(60, 100, at: 0.0);
      noteOff(60, at: 1.0);
      controller.onTransportStop();
      expect(target.undoScope.lastCommand, isA<AddNoteCommand>());
    });

    test('a multi-note pass commits one CompositeClipCommand', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();
      noteOn(60, 100, at: 0.0);
      noteOff(60, at: 0.5);
      noteOn(62, 100, at: 0.5);
      noteOff(62, at: 1.0);
      controller.onTransportStop();
      expect(target.undoScope.lastCommand, isA<CompositeClipCommand>());
      expect(target.clip.notes.length, 2);
    });
  });

  group('armed voice', () {
    test('captured notes carry the armed voice', () {
      armedVoice = 'voice.bells';
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();
      noteOn(60, 100, at: 0.0);
      noteOff(60, at: 1.0);
      controller.onTransportStop();
      expect(target.clip.notes.single.voice, 'voice.bells');
    });

    test('re-arming mid-take tags subsequent notes, not held ones', () {
      armedVoice = 'voice.a';
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();
      noteOn(60, 100, at: 0.0); // voice.a
      armedVoice = 'voice.b';
      noteOn(64, 100, at: 0.5); // voice.b
      noteOff(60, at: 1.0);
      noteOff(64, at: 1.0);
      controller.onTransportStop();

      final byPitch = {for (final n in target.clip.notes) n.pitch: n.voice};
      expect(byPitch[60.0], 'voice.a');
      expect(byPitch[64.0], 'voice.b');
    });

    test('an unrouted take leaves the voice null', () {
      controller.arm();
      target.isPlaying = true;
      controller.onTransportPlay();
      noteOn(60, 100, at: 0.0);
      noteOff(60, at: 1.0);
      controller.onTransportStop();
      expect(target.clip.notes.single.voice, isNull);
    });
  });
}
