import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/midi/midi_note.dart';
import 'piano_roll_painter.dart';

/// Bg0 panel that hosts the [PianoRollPainter] plus the small "p55–76 ·
/// N bars" caption from the mockup.
class PianoRollView extends StatelessWidget {
  const PianoRollView({
    required this.notes,
    required this.bars,
    required this.beatsPerBar,
    required this.version,
    super.key,
  });

  final List<MidiNote> notes;
  final int bars;
  final int beatsPerBar;
  final int version;

  @override
  Widget build(BuildContext context) {
    const minPitch = 55;
    const maxPitch = 76;
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
                notes: notes,
                bars: bars,
                beatsPerBar: beatsPerBar,
                version: version,
                minPitch: minPitch,
                maxPitch: maxPitch,
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 8,
            child: Text(
              'p$minPitch–$maxPitch · $bars bars'.toUpperCase(),
              style: PhiType.caption().copyWith(color: PhiColors.fg3),
            ),
          ),
        ],
      ),
    );
  }
}
