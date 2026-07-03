import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_note.dart';
import '../piano_roll_painter.dart';

/// A slim, read-only piano roll showing the notes the graph currently yields
/// for the live context — the active subgraph's output. Reuses
/// [PianoRollPainter] (source layer only, no ghost, no selection) so the graph
/// preview and the chain roll read identically.
///
/// Rebuilt by the surface whenever the graph structure, the active state, or
/// the source clip changes, so it always reflects `evaluate(context)`.
class GraphPreviewStrip extends StatelessWidget {
  const GraphPreviewStrip({
    required this.notes,
    required this.bars,
    required this.beatsPerBar,
    super.key,
  });

  final List<MidiNote> notes;
  final int bars;
  final int beatsPerBar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PhiColors.bg0,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all2,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: PianoRollPainter(
                sourceNotes: notes,
                ghostNotes: const [],
                selection: const {},
                bars: bars,
                beatsPerBar: beatsPerBar,
                // The painter's list-equality shouldRepaint drives redraws; the
                // revision only needs to stay stable within a single note set.
                revision: 0,
                showGhost: false,
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 6,
            child: IgnorePointer(
              child: Text(
                'preview · ${notes.length} notes'.toUpperCase(),
                style: PhiType.caption().copyWith(color: PhiColors.fg3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
