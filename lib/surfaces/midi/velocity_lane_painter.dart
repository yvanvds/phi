import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/midi/midi_note.dart';
import 'piano_roll_geometry.dart';

/// Velocity lane painted *below* the piano roll, sharing its time axis: each
/// note gets a vertical stem at its start-x whose height encodes velocity, so
/// a column sits directly under the note it belongs to (DAW-standard layout).
///
/// Selected notes' stems brighten to match the roll's highlight.
class VelocityLanePainter extends CustomPainter {
  VelocityLanePainter({
    required this.notes,
    required this.selection,
    required this.bars,
    required this.beatsPerBar,
    required this.revision,
  });

  final List<MidiNote> notes;
  final Set<int> selection;
  final int bars;
  final int beatsPerBar;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = PianoRollGeometry(
      size: size,
      bars: bars,
      beatsPerBar: beatsPerBar,
    );

    // Baseline.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = PhiColors.line1,
    );

    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final selected = selection.contains(i);
      final x = geo.xForBeat(note.start);
      final top = size.height * (1 - note.velocity.clamp(0.0, 1.0));
      final color = selected
          ? PhiColors.voice1
          : PhiColors.voice1.withValues(alpha: 0.55);
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, top),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        Offset(x, top),
        selected ? 3.5 : 2.5,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant VelocityLanePainter old) =>
      old.revision != revision ||
      old.bars != bars ||
      old.beatsPerBar != beatsPerBar ||
      !setEquals(old.selection, selection) ||
      !listEquals(old.notes, notes);
}
