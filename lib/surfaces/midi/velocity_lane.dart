import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_note.dart';
import 'piano_roll_geometry.dart';
import 'velocity_lane_painter.dart';

/// Interactive velocity strip under the roll. Click a column to set that
/// note's velocity from the pointer height; drag horizontally to paint across
/// several notes. The whole drag commits as one undoable edit.
class VelocityLane extends StatefulWidget {
  const VelocityLane({
    required this.editor,
    required this.notes,
    required this.bars,
    required this.beatsPerBar,
    this.height = 72,
    super.key,
  });

  final ClipEditor editor;
  final List<MidiNote> notes;
  final int bars;
  final int beatsPerBar;
  final double height;

  @override
  State<VelocityLane> createState() => _VelocityLaneState();
}

class _VelocityLaneState extends State<VelocityLane> {
  /// Live velocities during a drag, keyed by note index. Committed on pan end.
  final Map<int, double> _preview = {};
  Size _size = Size.zero;

  static const double _hitTolPx = 8;

  double _velAt(double localY) =>
      (1 - localY / _size.height).clamp(0.0, 1.0).toDouble();

  int? _noteAt(double localX) {
    if (_size.isEmpty) return null;
    final geo = PianoRollGeometry(
      size: _size,
      bars: widget.bars,
      beatsPerBar: widget.beatsPerBar,
    );
    int? best;
    var bestDx = _hitTolPx;
    for (var i = 0; i < widget.notes.length; i++) {
      final dx = (geo.xForBeat(widget.notes[i].start) - localX).abs();
      if (dx <= bestDx) {
        best = i;
        bestDx = dx;
      }
    }
    return best;
  }

  void _paint(Offset local) {
    final i = _noteAt(local.dx);
    if (i == null) return;
    setState(() => _preview[i] = _velAt(local.dy));
  }

  void _commit() {
    if (_preview.isNotEmpty) {
      widget.editor.setVelocities(Map<int, double>.of(_preview));
    }
    setState(_preview.clear);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, widget.height);
        final display = [
          for (var i = 0; i < widget.notes.length; i++)
            _preview.containsKey(i)
                ? widget.notes[i].copyWith(velocity: _preview[i])
                : widget.notes[i],
        ];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final i = _noteAt(d.localPosition.dx);
            if (i != null) {
              widget.editor.setVelocities({i: _velAt(d.localPosition.dy)});
            }
          },
          onPanStart: (d) => _paint(d.localPosition),
          onPanUpdate: (d) => _paint(d.localPosition),
          onPanEnd: (_) => _commit(),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: PhiColors.bg0,
              border: Border.all(color: PhiColors.line1),
              borderRadius: PhiRadii.all2,
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              size: Size.infinite,
              painter: VelocityLanePainter(
                notes: display,
                selection: widget.editor.selection,
                bars: widget.bars,
                beatsPerBar: widget.beatsPerBar,
                revision: widget.editor.revision,
              ),
            ),
          ),
        );
      },
    );
  }
}
