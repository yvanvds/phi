import '../../domain/midi/midi_clip.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/undo_scope.dart';

/// The live clip a [RecordController] captures a take into (issue #261, design
/// `docs/design/midi-recording.md` §3).
///
/// The recording *flow* never reaches into the engine's session internals: it
/// reads exactly this much through the seam — the source clip to append to, the
/// undo scope each pass commits through (so a pass is undoable like a drawn
/// note), the auto-extend flag that chooses grow-vs-overdub, the clip address
/// stamped onto the recorded commands, and the transport's play-relative beat.
///
/// [ClipSession] implements it directly, so the engine records into the edited
/// session; a test backs it with a plain [MidiClip] + [UndoScope] and a
/// hand-driven [recordBeat], which is why the flow is exercised against a "fake
/// session".
abstract interface class RecordTarget {
  /// The source clip captured notes are appended to.
  MidiClip get clip;

  /// The undo/redo stack each finished pass is committed through — one pass is
  /// one undo step, so Ctrl+Z peels passes newest-first.
  UndoScope get undoScope;

  /// Whether playing past the clip's declared end **grows** it (auto-extend on),
  /// as opposed to the loop wrapping and passes overdubbing (auto-extend off).
  bool get autoExtend;

  /// The clip's registry address, stamped onto the recorded commands for
  /// dirty-tracking / journaling. `null` for the engine's boot session.
  EntityAddress? get address;

  /// The transport's **play-relative** beat position — beats elapsed since play
  /// started, monotonically increasing across loop boundaries; `0` while
  /// stopped. Each captured note's start/end is stamped from it.
  double get recordBeat;

  /// Whether this target's transport is currently running.
  bool get isPlaying;
}
