import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../project/entity_address.dart';
import '../project/undo_scope.dart';
import 'edit/add_note_command.dart';
import 'edit/clip_edit_command.dart';
import 'edit/composite_clip_command.dart';
import 'edit/delete_notes_command.dart';
import 'edit/edit_notes_command.dart';
import 'edit/set_length_command.dart';
import 'midi_clip.dart';
import 'midi_note.dart';

/// Authoring controller for a single [MidiClip].
///
/// Owns the editable clip, the current selection (a set of note **indices**
/// into [MidiClip.notes]), and an [UndoScope] of [ClipEditCommand]s. Every
/// mutation is a command so it can be undone; gestures build a net edit and hand
/// it here, never poking the note list directly.
///
/// Since issue #119 the undo/redo stack is a shared [UndoScope] — the MIDI
/// surface's scope in the *undo-follows-focus* router (design §6). The editor
/// listens to that scope, so an undo triggered directly (`undo()`) or routed
/// through the shell's Ctrl+Z both land here: on every scope change it updates
/// the selection (redo reselects what the command touched; undo clears it) and
/// repaints. Expose the scope via [undoScope] for the shell to register.
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
    this.autoExtend = true,
    this.minPitch = 55,
    this.maxPitch = 76,
    String undoScopeId = 'midi',
    this._clipAddress,
  }) : _scope = UndoScope(id: undoScopeId, label: 'MIDI editor') {
    _scope.addListener(_onScopeChanged);
  }

  final MidiClip clip;

  /// Snap resolution in beats, driven by the header snap picker (issue #189).
  /// 0.25 = sixteenth-note grid (the painter's finest line). **0 disables
  /// snapping** — add / drag / resize / nudge run free. Duration still floors at
  /// [durationFloor] so a note is never zero-length even with snapping off.
  double gridDivision;

  /// Whether entering or dragging a note past the clip's declared end grows
  /// [MidiClip.bars] to fit (issue #190, design §5 / decision 2). **On by
  /// default.** The grow is journaled together with the note edit (a
  /// [CompositeClipCommand]), so one undo restores both the note and the old
  /// length. A header toggle drives this; it is view state, not persisted.
  bool autoExtend;

  /// The safety floor a note's duration is held to when snapping is off — a
  /// 1/64 note, small enough never to get in the way, large enough never to
  /// vanish.
  static const double minDuration = 0.0625;

  final int minPitch;
  final int maxPitch;

  final EntityAddress? _clipAddress;
  final UndoScope _scope;
  Set<int> _selection = const {};
  int _revision = 0;

  /// This editor's undo/redo stack, exposed so the shell can register it as the
  /// MIDI surface's scope in the undo-follows-focus router (#119).
  UndoScope get undoScope => _scope;

  /// Monotonic repaint key — bumps on any edit or selection change.
  int get revision => _revision;

  Set<int> get selection => Set.unmodifiable(_selection);
  bool isSelected(int index) => _selection.contains(index);

  bool get canUndo => _scope.canUndo;
  bool get canRedo => _scope.canRedo;

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

  /// The floor a note's duration is held to: the snap step when snapping is on,
  /// else [minDuration] so a note is never zero-length.
  double get durationFloor => gridDivision > 0 ? gridDivision : minDuration;

  /// Adds a note (clamped + floored to domain bounds) and selects it. When the
  /// note runs past the clip's declared end and [autoExtend] is on, the clip
  /// grows to fit — journaled with the add so one undo restores both.
  void addNote(MidiNote note) {
    final clamped = note.copyWith(
      pitch: note.pitch.clamp(minPitch.toDouble(), maxPitch.toDouble()),
      start: note.start < 0 ? 0 : note.start,
      duration: _floorDuration(note.duration),
    );
    _runNoteEdit(
      AddNoteCommand(clip, clamped, clipAddress: _clipAddress),
      endBeat: clamped.start + clamped.duration,
    );
  }

  /// Set the clip's declared length — its [MidiClip.bars] and beats-per-bar — as
  /// one undoable step (issue #190). Both are floored to `1`; a no-op change
  /// pushes nothing onto the undo stack. Callers own any "notes fall outside"
  /// warning before shrinking; this applies the length unconditionally.
  void setLength({int? bars, int? beatsPerBar}) {
    final nextBars = math.max(1, bars ?? clip.bars);
    final nextBeatsPerBar = math.max(1, beatsPerBar ?? clip.beatsPerBar);
    if (nextBars == clip.bars && nextBeatsPerBar == clip.beatsPerBar) return;
    _run(
      SetLengthCommand(
        clip,
        bars: nextBars,
        beatsPerBar: nextBeatsPerBar,
        clipAddress: _clipAddress,
      ),
    );
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    _run(DeleteNotesCommand(clip, _selection, clipAddress: _clipAddress));
  }

  /// Moves the selection by whole semitones and/or beats. Pitch clamps to the
  /// visible window; start floors at 0. A pure no-op (everything clamped away)
  /// pushes nothing onto the undo stack.
  void moveSelection({int dPitch = 0, double dBeats = 0}) {
    if (dPitch == 0 && dBeats == 0) return;
    _edit(
      (n) => n.copyWith(
        pitch: (n.pitch + dPitch).clamp(
          minPitch.toDouble(),
          maxPitch.toDouble(),
        ),
        start: _floor0(n.start + dBeats),
      ),
    );
  }

  /// Right-edge resize: changes duration, keeps start. Floors at one grid step
  /// (or [minDuration] when snapping is off).
  void resizeSelection(double dBeats) {
    if (dBeats == 0) return;
    _edit((n) => n.copyWith(duration: _floorDuration(n.duration + dBeats)));
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
    // A velocity edit never moves a note in time, so it must not auto-extend —
    // otherwise re-touching a note already parked past the end would re-grow the
    // clip after a deliberate shrink.
    _commit(before, after, grow: false);
  }

  /// Drops the undo/redo history and clears the selection, then notifies.
  ///
  /// Called after the underlying [clip] is rewritten out from under the editor
  /// (e.g. a file import via [MidiClip.replaceWith]): the old commands index
  /// into note positions that no longer exist, so they can't be replayed. The
  /// scope's notification clears the selection and repaints.
  void reset() => _scope.clear();

  void undo() => _scope.undo();

  void redo() => _scope.redo();

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

  void _commit(
    Map<int, MidiNote> before,
    Map<int, MidiNote> after, {
    bool grow = true,
  }) {
    if (_mapEquals(before, after)) return;
    final command = EditNotesCommand(
      clip,
      before: before,
      after: after,
      clipAddress: _clipAddress,
    );
    if (!grow) {
      _run(command);
      return;
    }
    final maxEnd = after.values.fold<double>(
      0,
      (m, n) => math.max(m, n.start + n.duration),
    );
    _runNoteEdit(command, endBeat: maxEnd);
  }

  /// Run [command], first bundling in a length grow when [autoExtend] is on and
  /// the edit's furthest note end ([endBeat]) overruns the clip — journaled as
  /// one [CompositeClipCommand] so a single undo restores note and length both.
  void _runNoteEdit(ClipEditCommand command, {required double endBeat}) {
    if (autoExtend) {
      final grownBars = _barsToFit(endBeat);
      if (grownBars > clip.bars) {
        _run(
          CompositeClipCommand(clip, [
            SetLengthCommand(
              clip,
              bars: grownBars,
              beatsPerBar: clip.beatsPerBar,
              clipAddress: _clipAddress,
            ),
            command,
          ], clipAddress: _clipAddress),
        );
        return;
      }
    }
    _run(command);
  }

  /// The bar count needed to contain a note ending at [endBeat] (rounded up to a
  /// whole bar), never below the clip's current [MidiClip.bars].
  int _barsToFit(double endBeat) {
    final beatsPerBar = clip.beatsPerBar;
    if (beatsPerBar <= 0) return clip.bars;
    final needed = (endBeat / beatsPerBar - _epsilon).ceil();
    return needed > clip.bars ? needed : clip.bars;
  }

  /// Slack so a note landing exactly on the clip's end doesn't spuriously grow.
  static const double _epsilon = 1e-9;

  void _run(ClipEditCommand command) => _scope.run(command);

  /// Mirrors the scope's state into the selection and repaints. A forward
  /// apply (`run`/`redo`) reselects the notes the command touched; an undo or a
  /// [reset] clears the selection.
  void _onScopeChanged() {
    final command = _scope.lastCommand;
    _selection =
        _scope.lastEvent == UndoEvent.applied && command is ClipEditCommand
        ? command.affectedIndices
        : const {};
    _bump();
  }

  void _bump() {
    _revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _scope.removeListener(_onScopeChanged);
    _scope.dispose();
    super.dispose();
  }

  double _floor0(double v) => v < 0 ? 0 : v;
  double _floorDuration(double v) => v < durationFloor ? durationFloor : v;

  bool _mapEquals(Map<int, MidiNote> a, Map<int, MidiNote> b) {
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}
