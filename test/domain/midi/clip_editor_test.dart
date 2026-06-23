import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';

MidiClip _clip([List<MidiNote>? notes]) => MidiClip(
  name: 't',
  bars: 4,
  notes:
      notes ??
      const [
        MidiNote(pitch: 60, start: 0, duration: 0.5, velocity: 0.5),
        MidiNote(pitch: 64, start: 1, duration: 0.5, velocity: 0.5),
      ],
);

void main() {
  group('ClipEditor — add', () {
    test('addNote appends, selects it, and bumps revision', () {
      final editor = ClipEditor(_clip(const []));
      var notifications = 0;
      editor.addListener(() => notifications++);

      editor.addNote(
        const MidiNote(pitch: 60, start: 0.3, duration: 0.5, velocity: 0.8),
      );

      expect(editor.clip.notes.single.pitch, 60);
      expect(editor.selection, {0});
      expect(notifications, 1);
      expect(editor.canUndo, isTrue);
    });

    test('addNote clamps pitch to the window and floors start/duration', () {
      final editor = ClipEditor(_clip(const []), minPitch: 55, maxPitch: 76);
      editor.addNote(
        const MidiNote(pitch: 200, start: -3, duration: 0.01, velocity: 0.5),
      );
      final n = editor.clip.notes.single;
      expect(n.pitch, 76);
      expect(n.start, 0);
      expect(n.duration, editor.gridDivision);
    });

    test('undo removes the added note and clears selection', () {
      final editor = ClipEditor(_clip(const []));
      editor.addNote(
        const MidiNote(pitch: 60, start: 0, duration: 0.5, velocity: 0.8),
      );
      editor.undo();
      expect(editor.clip.notes, isEmpty);
      expect(editor.selection, isEmpty);
      expect(editor.canUndo, isFalse);
      expect(editor.canRedo, isTrue);
    });

    test('redo re-adds the note and reselects it', () {
      final editor = ClipEditor(_clip(const []));
      editor.addNote(
        const MidiNote(pitch: 60, start: 0, duration: 0.5, velocity: 0.8),
      );
      editor.undo();
      editor.redo();
      expect(editor.clip.notes.single.pitch, 60);
      expect(editor.selection, {0});
    });
  });

  group('ClipEditor — move / resize', () {
    test('moveSelection shifts pitch and time of selected notes only', () {
      final editor = ClipEditor(_clip())..selectOnly(0);
      editor.moveSelection(dPitch: 2, dBeats: 0.5);
      expect(editor.clip.notes[0].pitch, 62);
      expect(editor.clip.notes[0].start, 0.5);
      expect(editor.clip.notes[1].pitch, 64); // untouched
    });

    test('moveSelection clamps pitch to the window and floors start at 0', () {
      final editor = ClipEditor(_clip(), minPitch: 55, maxPitch: 76)
        ..selectOnly(0);
      editor.moveSelection(dPitch: -20, dBeats: -5);
      expect(editor.clip.notes[0].pitch, 55);
      expect(editor.clip.notes[0].start, 0);
    });

    test('a fully clamped move pushes nothing onto the undo stack', () {
      final editor = ClipEditor(_clip())..selectOnly(0);
      // Note already at start 0, moving left clamps to 0 → no change.
      editor.moveSelection(dBeats: -1);
      expect(editor.canUndo, isFalse);
    });

    test(
      'resizeSelection changes duration, keeps start, floors at one grid',
      () {
        final editor = ClipEditor(_clip())..selectOnly(1);
        editor.resizeSelection(0.5);
        expect(editor.clip.notes[1].duration, 1.0);
        expect(editor.clip.notes[1].start, 1);

        editor.resizeSelection(-10); // floors at gridDivision
        expect(editor.clip.notes[1].duration, editor.gridDivision);
      },
    );

    test('undo restores the exact pre-move note', () {
      final editor = ClipEditor(_clip())..selectOnly(0);
      final before = editor.clip.notes[0];
      editor.moveSelection(dPitch: 3, dBeats: 1);
      editor.undo();
      expect(editor.clip.notes[0], before);
    });
  });

  group('ClipEditor — delete', () {
    test('deleteSelection removes selected notes and clears selection', () {
      final editor = ClipEditor(_clip())..setSelection({0});
      editor.deleteSelection();
      expect(editor.clip.notes.length, 1);
      expect(editor.clip.notes.single.pitch, 64);
      expect(editor.selection, isEmpty);
    });

    test('undo reinserts deleted notes at their original index', () {
      final editor = ClipEditor(_clip())..setSelection({0, 1});
      final original = List.of(editor.clip.notes);
      editor.deleteSelection();
      expect(editor.clip.notes, isEmpty);
      editor.undo();
      expect(editor.clip.notes, original);
    });

    test('deleting with an empty selection is a no-op', () {
      final editor = ClipEditor(_clip());
      editor.deleteSelection();
      expect(editor.clip.notes.length, 2);
      expect(editor.canUndo, isFalse);
    });
  });

  group('ClipEditor — velocity', () {
    test('setVelocities updates only the given notes, clamped to [0,1]', () {
      final editor = ClipEditor(_clip());
      editor.setVelocities({0: 0.9, 1: 2.0});
      expect(editor.clip.notes[0].velocity, 0.9);
      expect(editor.clip.notes[1].velocity, 1.0);
    });

    test('one setVelocities call is a single undo step', () {
      final editor = ClipEditor(_clip());
      editor.setVelocities({0: 0.2, 1: 0.3});
      editor.undo();
      expect(editor.clip.notes[0].velocity, 0.5);
      expect(editor.clip.notes[1].velocity, 0.5);
    });
  });

  group('ClipEditor — selection', () {
    test('toggle adds then removes an index', () {
      final editor = ClipEditor(_clip());
      editor.toggle(1);
      expect(editor.selection, {1});
      editor.toggle(1);
      expect(editor.selection, isEmpty);
    });

    test('selection changes notify but do not push undo', () {
      final editor = ClipEditor(_clip());
      var notifications = 0;
      editor.addListener(() => notifications++);
      editor.selectOnly(0);
      expect(notifications, 1);
      expect(editor.canUndo, isFalse);
    });

    test('an idempotent selection change does not notify', () {
      final editor = ClipEditor(_clip())..selectOnly(0);
      var notifications = 0;
      editor.addListener(() => notifications++);
      editor.selectOnly(0);
      expect(notifications, 0);
    });
  });

  test('a new edit clears the redo stack', () {
    final editor = ClipEditor(_clip())..selectOnly(0);
    editor.moveSelection(dPitch: 1);
    editor.undo();
    expect(editor.canRedo, isTrue);
    editor.selectOnly(0);
    editor.moveSelection(dPitch: 2);
    expect(editor.canRedo, isFalse);
  });
}
