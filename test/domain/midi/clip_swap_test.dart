import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';

/// The in-place clip-swap seam that SMF import relies on (#30): the chain,
/// editor and engine player all share one [MidiClip] reference, so import
/// mutates it rather than replacing it.
void main() {
  MidiClip clipOf(String name, List<MidiNote> notes, {int bars = 1}) =>
      MidiClip(name: name, notes: notes, bars: bars, beatsPerBar: 4);

  group('MidiClip.replaceWith', () {
    test('overwrites name, meter and notes in place', () {
      final target = clipOf('old', const [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
      ]);
      final identity = target.notes; // same list instance must be reused

      target.replaceWith(
        clipOf('new', const [
          MidiNote(pitch: 48, start: 0, duration: 0.5, velocity: 0.5),
          MidiNote(pitch: 55, start: 1, duration: 0.5, velocity: 0.5),
        ], bars: 3),
      );

      expect(target.name, 'new');
      expect(target.bars, 3);
      expect(target.notes.length, 2);
      expect(target.notes.first.pitch, 48);
      expect(identical(target.notes, identity), isTrue);
    });
  });

  group('ClipEditor.reset', () {
    test('clears history and selection after the clip is swapped', () {
      final clip = clipOf('c', const [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
      ]);
      final editor = ClipEditor(clip);
      editor
        ..selectOnly(0)
        ..addNote(
          const MidiNote(pitch: 64, start: 1, duration: 1, velocity: 1),
        );
      expect(editor.canUndo, isTrue);
      expect(editor.selection, isNotEmpty);

      var notified = 0;
      editor.addListener(() => notified++);
      editor.reset();

      expect(editor.canUndo, isFalse);
      expect(editor.canRedo, isFalse);
      expect(editor.selection, isEmpty);
      expect(notified, 1);

      editor.dispose();
    });
  });

  group('MidiTransformChain.notifySourceChanged', () {
    test('bumps version and notifies so bound painters recompute', () {
      final chain = MidiTransformChain(
        source: clipOf('c', const [
          MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        ]),
      );
      final before = chain.version;
      var notified = 0;
      chain.addListener(() => notified++);

      chain.notifySourceChanged();

      expect(chain.version, greaterThan(before));
      expect(notified, 1);

      chain.dispose();
    });
  });
}
