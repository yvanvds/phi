import '../../project/entity_address.dart';
import '../edit/add_note_command.dart';
import '../edit/clip_edit_command.dart';
import '../edit/composite_clip_command.dart';
import '../midi_clip.dart';
import '../midi_note.dart';

/// Sink for the per-pass command batch a [TakeRecorder] produces (issue #260,
/// design `docs/design/midi-recording.md` §2 / §8 decision 1).
///
/// The recorder never mutates the clip itself: it hands each finished loop pass
/// here as one [ClipEditCommand]. The recording flow (issue #261) runs it
/// through the clip's `UndoScope` — so a pass is undoable exactly like a drawn
/// note — while unit tests can collect the batches and apply them by hand.
typedef ClipCommandSink = void Function(ClipEditCommand batch);

/// Turns live MIDI-in into the *source* notes of a clip — the capture spine of
/// the midi-recording epic (design `docs/design/midi-recording.md` §2, §8).
///
/// Pure Dart, driven entirely by injected input + an injected clock reader, so
/// it is exercised against a fake keyboard and a fake transport. It does not
/// touch the engine, the transport, or the UI — the recording *flow* (arm,
/// punch-in, loop detection) that feeds it is issue #261.
///
/// **Record raw, always** (§8 decision 1): captured notes land exactly as
/// played — pitch as the note number, velocity kept (normalised to `[0, 1]`),
/// timings straight off the clock with no snapping or rounding beyond float
/// representation. Interpretation is the transform chain's job.
///
/// The clock reader returns the transport's **clip-relative** beat position (the
/// value that maps onto [MidiNote.start]); each note-on stamps its start from it
/// and each note-off its end. Notes still held at a boundary are edge-closed:
///
/// - **Stop** ([stop]) closes every held note at the current beat.
/// - **Loop wrap** ([wrap]) closes every held note at the loop end
///   ([MidiClip.totalBeats]) and **reopens** the still-held ones at beat `0`, so
///   a note sustained across the wrap becomes two source notes.
///
/// Each loop pass (the span between [start]/[wrap] and the next [wrap]/[stop])
/// commits as **one** command batch through [ClipCommandSink] — the journal
/// treats a pass as authored content, so Ctrl+Z removes a whole pass (§2, design
/// decision: per-pass batches). Recorded notes carry the **armed [voice]** — what
/// you heard while playing is what's stored (§8 decision 3).
class TakeRecorder {
  TakeRecorder({
    required this.clip,
    required double Function() clock,
    required ClipCommandSink commit,
    EntityAddress? clipAddress,
    this.voice,
  }) : _clock = clock,
       _commit = commit,
       _clipAddress = clipAddress;

  /// The clip captured notes are appended to. Held by the [AddNoteCommand]s the
  /// recorder builds; the recorder never mutates it directly.
  final MidiClip clip;

  /// Reads the transport's current clip-relative beat position — the injected
  /// clock every timestamp comes from (design §2). Rides the UI isolate in
  /// production; a plain closure in tests.
  final double Function() _clock;

  final ClipCommandSink _commit;
  final EntityAddress? _clipAddress;

  /// The armed voice address stamped onto captured notes at note-on (§8
  /// decision 3). Mutable so a re-arm mid-take tags subsequent notes with the
  /// new voice; notes already held keep the voice they started sounding on.
  String? voice;

  bool _recording = false;

  /// Whether a take is in progress (between [start] and [stop]).
  bool get isRecording => _recording;

  /// Notes currently held (a note-on awaiting its note-off), keyed by MIDI note
  /// number so a note-off pairs with the matching on and a re-press is caught.
  final Map<int, _OpenNote> _held = {};

  /// Notes finished in the current pass, awaiting the pass boundary ([wrap] /
  /// [stop]) to commit as one batch.
  final List<MidiNote> _pass = [];

  /// Whether anything is captured but not yet committed — held notes or finished
  /// notes waiting on the next pass boundary.
  bool get hasPendingNotes => _pass.isNotEmpty || _held.isNotEmpty;

  /// Whether any note is currently held (a note-on awaiting its note-off) — so
  /// the recording flow (issue #261) can tell whether a [stop] will close a note
  /// at the current beat, and grow an auto-extending clip to contain it.
  bool get hasHeldNotes => _held.isNotEmpty;

  /// Begin a take. Clears any prior capture state. A no-op while already
  /// recording (arming again mid-take does not restart the pass).
  void start() {
    if (_recording) return;
    _recording = true;
    _held.clear();
    _pass.clear();
  }

  /// A note-on: open a held note at the current beat with [note] as the pitch and
  /// [velocity] (`0..127`) normalised. A no-op when not recording. A re-press of
  /// an already-held pitch first closes the previous segment (raw, no flooring),
  /// so a stuck on/on sequence never loses the earlier press.
  void noteOn(int note, int velocity) {
    if (!_recording) return;
    final at = _clock();
    final existing = _held.remove(note);
    if (existing != null) _pass.add(existing.close(at));
    _held[note] = _OpenNote(
      pitch: note.toDouble(),
      start: at,
      velocity: (velocity / 127.0).clamp(0.0, 1.0).toDouble(),
      voice: voice,
    );
  }

  /// A note-off: close the held note of [note] at the current beat and add the
  /// finished [MidiNote] to the current pass. A note-off with no matching held
  /// note (an orphan off — the on arrived before [start], or a double off) is
  /// ignored. A no-op when not recording.
  void noteOff(int note) {
    if (!_recording) return;
    final open = _held.remove(note);
    if (open == null) return;
    _pass.add(open.close(_clock()));
  }

  /// The loop wrapped: close every held note at the loop end
  /// ([MidiClip.totalBeats]), commit the pass, and reopen the still-held notes
  /// at beat `0` for the next pass — so a note sustained across the wrap becomes
  /// two source notes (design §2). A no-op when not recording.
  void wrap() {
    if (!_recording) return;
    final loopEnd = clip.totalBeats;
    final carried = <int, _OpenNote>{};
    _held.forEach((note, open) {
      _pass.add(open.close(loopEnd));
      carried[note] = _OpenNote(
        pitch: open.pitch,
        start: 0,
        velocity: open.velocity,
        voice: open.voice,
      );
    });
    _held
      ..clear()
      ..addAll(carried);
    _commitPass();
  }

  /// Stop the take: close every held note at the current beat (design §2 — held
  /// notes close at the stop beat), commit the final pass, and end recording. A
  /// no-op when not recording.
  void stop() {
    if (!_recording) return;
    final at = _clock();
    for (final open in _held.values) {
      _pass.add(open.close(at));
    }
    _held.clear();
    _commitPass();
    _recording = false;
  }

  /// Emit the current pass as one command batch and reset the accumulator. An
  /// empty pass commits nothing. A single note is a bare [AddNoteCommand]; two or
  /// more are bundled into one [CompositeClipCommand] so the whole pass is one
  /// undo step.
  void _commitPass() {
    if (_pass.isEmpty) return;
    final adds = [
      for (final note in _pass)
        AddNoteCommand(clip, note, clipAddress: _clipAddress),
    ];
    _pass.clear();
    _commit(
      adds.length == 1
          ? adds.first
          : CompositeClipCommand(clip, adds, clipAddress: _clipAddress),
    );
  }
}

/// A note-on awaiting its note-off. Carries everything the finished [MidiNote]
/// needs so [close] can stamp its end beat.
class _OpenNote {
  _OpenNote({
    required this.pitch,
    required this.start,
    required this.velocity,
    required this.voice,
  });

  final double pitch;
  final double start;
  final double velocity;
  final String? voice;

  /// Build the finished note ending at [end]. Duration is raw (§8 decision 1) —
  /// no snapping — but never negative, so an out-of-order end can't yield a
  /// nonsensical note.
  MidiNote close(double end) => MidiNote(
    pitch: pitch,
    start: start,
    duration: end > start ? end - start : 0.0,
    velocity: velocity,
    voice: voice,
  );
}
