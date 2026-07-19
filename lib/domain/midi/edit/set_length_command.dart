import 'clip_edit_command.dart';

/// Changes a clip's declared length — its `bars` and `beats-per-bar` (issue
/// #190, design `docs/design/midi-clips.md` §5).
///
/// Length is authority: the loop window is the clip's declared
/// [MidiClip.totalBeats], not the transformed output's extent. Editing the
/// header length fields runs one of these; auto-extend bundles it *with* the
/// note edit that overran the end (see [CompositeClipCommand]) so a single undo
/// restores both the note and the old length.
///
/// It leaves the note list — and therefore any live selection — untouched, so
/// [affectedIndices] is empty. It does **not** [MidiClip.touch] the clip: the
/// transformed pipeline never depends on the meter, so a length change forces no
/// chain recompute; the editor's own notification repaints the roll and re-lays
/// the grid.
class SetLengthCommand extends ClipEditCommand {
  SetLengthCommand(
    super.clip, {
    required this.bars,
    required this.beatsPerBar,
    super.clipAddress,
  }) : _prevBars = clip.bars,
       _prevBeatsPerBar = clip.beatsPerBar;

  /// The new declared bar count.
  final int bars;

  /// The new beats-per-bar (meter numerator).
  final int beatsPerBar;

  final int _prevBars;
  final int _prevBeatsPerBar;

  @override
  String get label => 'set length';

  @override
  Set<int> get affectedIndices => const {};

  @override
  void apply() {
    clip.bars = bars;
    clip.beatsPerBar = beatsPerBar;
  }

  @override
  void revert() {
    clip.bars = _prevBars;
    clip.beatsPerBar = _prevBeatsPerBar;
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'set_length',
    'bars': bars,
    'beatsPerBar': beatsPerBar,
    'prevBars': _prevBars,
    'prevBeatsPerBar': _prevBeatsPerBar,
  };
}
