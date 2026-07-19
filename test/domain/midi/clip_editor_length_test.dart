import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';

/// Length authority + auto-extend on the [ClipEditor] (issue #190, design §5).
void main() {
  MidiClip clip({int bars = 2, int beatsPerBar = 4, List<MidiNote>? notes}) =>
      MidiClip(bars: bars, beatsPerBar: beatsPerBar, notes: notes ?? const []);

  group('ClipEditor — setLength', () {
    test('changes bars and beats-per-bar as one undoable step', () {
      final editor = ClipEditor(clip());
      var notifications = 0;
      editor.addListener(() => notifications++);

      editor.setLength(bars: 8, beatsPerBar: 3);

      expect(editor.clip.bars, 8);
      expect(editor.clip.beatsPerBar, 3);
      expect(editor.clip.totalBeats, 24);
      expect(editor.canUndo, isTrue);
      expect(notifications, 1);
    });

    test('undo restores the previous length, redo re-applies it', () {
      final editor = ClipEditor(clip(bars: 4, beatsPerBar: 4));

      editor.setLength(bars: 2);
      expect(editor.clip.bars, 2);

      editor.undo();
      expect(editor.clip.bars, 4);
      expect(editor.clip.beatsPerBar, 4);

      editor.redo();
      expect(editor.clip.bars, 2);
    });

    test('floors both dimensions at 1', () {
      final editor = ClipEditor(clip(bars: 4, beatsPerBar: 4));
      editor.setLength(bars: 0, beatsPerBar: -3);
      expect(editor.clip.bars, 1);
      expect(editor.clip.beatsPerBar, 1);
    });

    test('a no-op length change pushes nothing onto the undo stack', () {
      final editor = ClipEditor(clip(bars: 4, beatsPerBar: 4));
      editor.setLength(bars: 4, beatsPerBar: 4);
      expect(editor.canUndo, isFalse);
    });
  });

  group('ClipEditor — auto-extend', () {
    test('adding a note past the end grows bars to fit (rounded up)', () {
      // 2 bars × 4 = 8 beats. A note ending at beat 10 needs 3 bars (12 beats).
      final editor = ClipEditor(clip(bars: 2, beatsPerBar: 4));
      editor.addNote(
        const MidiNote(pitch: 60, start: 9, duration: 1, velocity: 0.8),
      );
      expect(editor.clip.notes, hasLength(1));
      expect(editor.clip.bars, 3);
      expect(editor.clip.totalBeats, 12);
    });

    test('the grow + add is one undo step that restores the old length', () {
      final editor = ClipEditor(clip(bars: 2, beatsPerBar: 4));
      editor.addNote(
        const MidiNote(pitch: 60, start: 9, duration: 1, velocity: 0.8),
      );
      expect(editor.clip.bars, 3);

      editor.undo();
      expect(editor.clip.notes, isEmpty);
      expect(editor.clip.bars, 2); // length restored together with the note
      expect(editor.canUndo, isFalse);

      editor.redo();
      expect(editor.clip.notes, hasLength(1));
      expect(editor.clip.bars, 3);
    });

    test('a note landing exactly on the end does not grow', () {
      final editor = ClipEditor(clip(bars: 2, beatsPerBar: 4));
      editor.addNote(
        const MidiNote(pitch: 60, start: 7, duration: 1, velocity: 0.8),
      );
      expect(editor.clip.bars, 2);
    });

    test('a note within the clip does not grow', () {
      final editor = ClipEditor(clip(bars: 4, beatsPerBar: 4));
      editor.addNote(
        const MidiNote(pitch: 60, start: 2, duration: 1, velocity: 0.8),
      );
      expect(editor.clip.bars, 4);
    });

    test('auto-extend off keeps the length and just adds the note', () {
      final editor = ClipEditor(
        clip(bars: 2, beatsPerBar: 4),
        autoExtend: false,
      );
      editor.addNote(
        const MidiNote(pitch: 60, start: 9, duration: 1, velocity: 0.8),
      );
      expect(editor.clip.notes, hasLength(1));
      expect(editor.clip.bars, 2);
      // A single plain add — one undo removes just the note.
      editor.undo();
      expect(editor.clip.notes, isEmpty);
      expect(editor.canUndo, isFalse);
    });

    test('dragging a note past the end grows too (move)', () {
      final editor = ClipEditor(
        clip(
          bars: 2,
          beatsPerBar: 4,
          notes: const [
            MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
          ],
        ),
      )..selectOnly(0);
      editor.moveSelection(dBeats: 9); // start 0 → 9, end 10 → needs 3 bars
      expect(editor.clip.bars, 3);
      editor.undo();
      expect(editor.clip.bars, 2);
      expect(editor.clip.notes.single.start, 0);
    });

    test('resizing a note past the end grows too', () {
      final editor = ClipEditor(
        clip(
          bars: 2,
          beatsPerBar: 4,
          notes: const [
            MidiNote(pitch: 60, start: 6, duration: 1, velocity: 1),
          ],
        ),
      )..selectOnly(0);
      editor.resizeSelection(3); // duration 1 → 4, end 6→10 → needs 3 bars
      expect(editor.clip.bars, 3);
    });

    test('a velocity edit on a note parked past the end never re-grows', () {
      // Add a note past the end (grows to 3), then shrink back to 2 so the note
      // is now outside; a velocity paint must not silently re-extend the clip.
      final editor = ClipEditor(clip(bars: 2, beatsPerBar: 4));
      editor.addNote(
        const MidiNote(pitch: 60, start: 9, duration: 1, velocity: 0.5),
      );
      editor.setLength(bars: 2);
      expect(editor.clip.bars, 2);

      editor.setVelocities({0: 0.9});
      expect(editor.clip.bars, 2);
      expect(editor.clip.notes.single.velocity, closeTo(0.9, 1e-9));
    });
  });
}
