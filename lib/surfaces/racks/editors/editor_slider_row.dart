import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';

/// A labelled horizontal parameter slider with a live readout — the continuous
/// control the VA / sampler / fx panels are built from (design
/// `docs/design/racks-and-voices.md` §8).
///
/// **Gesture coalescing lives here.** The whole drag is one edit: while the
/// thumb moves the row holds a transient value and repaints itself, but it only
/// calls [onCommit] **once**, on pointer-up (and on a track tap). So a slider
/// sweep becomes a single journaled payload command rather than one per frame —
/// the "continuous controls gesture-coalesce" the design calls for. The
/// optional [onChanged] fires continuously for a caller that wants a live
/// preview (unused today — voice re-application lands with the engine slice).
///
/// [value] is in real units within `[min, max]`; the row maps it to the track
/// internally. [format] renders the readout (defaulting to a trimmed number);
/// [asInt] rounds committed values to whole numbers (voice counts, tap indices).
class EditorSliderRow extends StatefulWidget {
  const EditorSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    this.onChanged,
    this.asInt = false,
    this.format,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;

  /// Called once when a drag ends or the track is tapped — the commit point.
  final ValueChanged<double> onCommit;

  /// Called on every drag update for an optional live preview. Never the commit.
  final ValueChanged<double>? onChanged;

  /// Round committed / displayed values to integers.
  final bool asInt;

  /// Renders the readout from the current value. Defaults to a trimmed number.
  final String Function(double value)? format;

  @override
  State<EditorSliderRow> createState() => _EditorSliderRowState();
}

class _EditorSliderRowState extends State<EditorSliderRow> {
  /// The transient value shown while a drag is live; `null` when at rest (the
  /// row then shows the committed [EditorSliderRow.value]).
  double? _dragValue;

  double get _shown => _dragValue ?? widget.value;

  double get _span =>
      (widget.max - widget.min).abs() < 1e-12 ? 1.0 : widget.max - widget.min;

  double _fraction(double v) =>
      ((v - widget.min) / _span).clamp(0.0, 1.0).toDouble();

  double _valueAt(double localX, double width) {
    final f = width <= 0 ? 0.0 : (localX / width).clamp(0.0, 1.0);
    final raw = widget.min + f * _span;
    return widget.asInt ? raw.roundToDouble() : raw;
  }

  String get _readout {
    final v = widget.asInt ? _shown.roundToDouble() : _shown;
    if (widget.format != null) return widget.format!(v);
    return v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: PhiType.monoS().copyWith(color: PhiColors.fg1),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                void update(double localX) {
                  final v = _valueAt(localX, width);
                  setState(() => _dragValue = v);
                  widget.onChanged?.call(v);
                }

                void commit() {
                  final v = _dragValue;
                  if (v != null) widget.onCommit(v);
                  setState(() => _dragValue = null);
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => update(d.localPosition.dx),
                  onTapUp: (_) => commit(),
                  onHorizontalDragStart: (d) => update(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
                  onHorizontalDragEnd: (_) => commit(),
                  child: _Track(fraction: _fraction(_shown)),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              _readout,
              textAlign: TextAlign.right,
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            ),
          ),
        ],
      ),
    );
  }
}

/// The slider track: a thin bar with a voice-coloured fill up to [fraction].
class _Track extends StatelessWidget {
  const _Track({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: PhiColors.bg3,
              borderRadius: PhiRadii.allPill,
              border: Border.all(color: PhiColors.line1),
            ),
          ),
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              height: 6,
              decoration: const BoxDecoration(
                color: PhiColors.voice1,
                borderRadius: PhiRadii.allPill,
              ),
            ),
          ),
          Align(
            alignment: Alignment(fraction * 2 - 1, 0),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: PhiColors.bg4,
                shape: BoxShape.circle,
                border: Border.all(color: PhiColors.lineHot),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
