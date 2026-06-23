import 'package:flutter/foundation.dart';

import 'edit/add_note_command.dart';
import 'edit/clip_edit_command.dart';
import 'edit/delete_notes_command.dart';
import 'edit/edit_notes_command.dart';
import 'midi_clip.dart';
import 'midi_note.dart';

/// Authoring controller for a single [MidiClip].
///
/// Owns the editable clip, the current selection (a set of note **indices**
/// into [MidiClip.notes]), and the undo/redo stacks. Every mutation is a
/// [ClipEditCommand] so it can be undone; gestures build a net edit and hand
/// it here, never poking the note list directly.
///
/// Notifies (and bumps [revision]) on every edit *and* every selection change
/// so the piano roll repaints both the notes and the highlight. The editor
/// enforces domain invariants — pitch stays in `[minPitch, maxPitch]`, start
/// never goes negative, duration never drops below one grid step — while the
/// widget layer owns pixel↔beat snapping.
class ClipEditor extends ChangeNotifier {
  ClipEditor(
    this.clip, {
    this.gridDivision = 0.25,
    this.minPitch = 55,
    this.maxPitch = 76,
  });

  final MidiClip clip;

  /// Snap resolution in beats. 0.25 = sixteenth-note grid (the painter's
  /// finest line). The editor clamps duration to this minimum.
  double gridDivision;

  final int minPitch;
  final int maxPitch;

  final List<ClipEditCommand> _undo = [];
  final List<ClipEditCommand> _redo = [];
  Set<int> _selection = const {};
  int _revision = 0;

  /// Monotonic repaint key — bumps on any edit or selection change.
  int get revision => _revision;

  Set<int> get selection => Set.unmodifiable(_selection);
  bool isSelected(int index) => _selection.contains(index);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ── Selection ────────────────────────────────────────────────────────────

  void clearSelection() => _setSelection(const {});

  void selectOnly(int index) => _setSelection({index});

  void toggle(int index) {
    final next = Set<int>.of(_selection);
    next.contains(index) ? next.remove(index) : next.add(index);
    _setSelection(next);
  }

  /// Replaces the selection wholesale — used by marquee select and
  /// shift-extend (the caller unions with the prior set as needed).
  void setSelection(Set<int> indices) => _setSelection(Set<int>.of(indices));

  void _setSelection(Set<int> next) {
    if (setEquals(_selection, next)) return;
    _selection = next;
    _bump();
  }

  // ── Edits ────────────────────────────────────────────────────────────────

  /// Adds a note (clamped + floored to domain bounds) and selects it.
  void addNote(MidiNote note) {
    final clamped = note.copyWith(
      pitch: note.pitch.clamp(minPitch, maxPitch),
      start: note.start < 0 ? 0 : note.start,
      duration: note.duration < gridDivision ? gridDivision : note.duration,
    );
    _run(AddNoteCommand(clamped));
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    _run(DeleteNotesCommand(_selection));
  }

  /// Moves the selection by whole semitones and/or beats. Pitch clamps to the
  /// visible window; start floors at 0. A pure no-op (everything clamped away)
  /// pushes nothing onto the undo stack.
  void moveSelection({int dPitch = 0, double dBeats = 0}) {
    if (dPitch == 0 && dBeats == 0) return;
    _edit(
      (n) => n.copyWith(
        pitch: (n.pitch + dPitch).clamp(minPitch, maxPitch),
        start: _floor0(n.start + dBeats),
      ),
    );
  }

  /// Right-edge resize: changes duration, keeps start. Floors at one grid step.
  void resizeSelection(double dBeats) {
    if (dBeats == 0) return;
    _edit((n) => n.copyWith(duration: _floorGrid(n.duration + dBeats)));
  }

  /// Sets velocity for specific notes (velocity-lane click / paint), one
  /// undoable command for the whole gesture.
  void setVelocities(Map<int, double> velocities) {
    if (velocities.isEmpty) return;
    final before = <int, MidiNote>{};
    final after = <int, MidiNote>{};
    velocities.forEach((i, v) {
      final n = clip.notes[i];
      before[i] = n;
      after[i] = n.copyWith(velocity: v.clamp(0.0, 1.0));
    });
    _commit(before, after);
  }

  void undo() {
    if (_undo.isEmpty) return;
    final cmd = _undo.removeLast();
    cmd.revert(clip);
    _redo.add(cmd);
    _selection = const {};
    _bump();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final cmd = _redo.removeLast();
    cmd.applyTo(clip);
    _undo.add(cmd);
    _selection = cmd.affectedIndices;
    _bump();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  /// Applies [transform] to every selected note, building one [EditNotesCommand].
  void _edit(MidiNote Function(MidiNote) transform) {
    if (_selection.isEmpty) return;
    final before = <int, MidiNote>{};
    final after = <int, MidiNote>{};
    for (final i in _selection) {
      final n = clip.notes[i];
      before[i] = n;
      after[i] = transform(n);
    }
    _commit(before, after);
  }

  void _commit(Map<int, MidiNote> before, Map<int, MidiNote> after) {
    if (_mapEquals(before, after)) return;
    _run(EditNotesCommand(before: before, after: after));
  }

  void _run(ClipEditCommand command) {
    command.applyTo(clip);
    _undo.add(command);
    _redo.clear();
    _selection = command.affectedIndices;
    _bump();
  }

  void _bump() {
    _revision++;
    notifyListeners();
  }

  double _floor0(double v) => v < 0 ? 0 : v;
  double _floorGrid(double v) => v < gridDivision ? gridDivision : v;

  bool _mapEquals(Map<int, MidiNote> a, Map<int, MidiNote> b) {
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}
