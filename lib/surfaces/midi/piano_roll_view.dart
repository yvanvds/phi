import 'package:flutter/foundation.dart';

/// Session-local pan/zoom for one piano roll — the parametrised
/// pixels-per-beat and lane-height the design (`docs/design/midi-clips.md` §5)
/// calls for. Immutable: a zoom gesture produces a fresh instance the widget
/// swaps in. **Never persisted** — a loaded project always opens at the
/// fit-to-viewport default (a `null` view in [PianoRollGeometry]).
///
/// Horizontal state is `(pixelsPerBeat, scrollBeats)` — the beat at the left
/// edge; vertical state is `(laneHeight, scrollLanes)` — how many semitone
/// lanes below the top pitch sit above the top edge. [PianoRollGeometry],
/// [PianoRollPainter], the gesture layer and the velocity lane all read the
/// *same* view, so a note is drawn, hit-tested and velocity-edited with one
/// arithmetic — the classic source of "I clicked the note but nothing
/// happened" drift.
@immutable
class PianoRollView {
  const PianoRollView({
    required this.pixelsPerBeat,
    required this.laneHeight,
    this.scrollBeats = 0,
    this.scrollLanes = 0,
  });

  /// Horizontal zoom — pixels one beat occupies.
  final double pixelsPerBeat;

  /// Vertical zoom — pixels one semitone lane occupies.
  final double laneHeight;

  /// The beat at the left edge (x = 0); grows as you zoom in around a pointer
  /// to the right of the origin.
  final double scrollBeats;

  /// Lanes below the top pitch that sit above the top edge (y = 0).
  final double scrollLanes;

  /// Zoom ceilings — a beat / lane never balloons past these, so a stuck wheel
  /// can't blow the geometry up.
  static const double maxPixelsPerBeat = 600;
  static const double maxLaneHeight = 64;

  PianoRollView copyWith({
    double? pixelsPerBeat,
    double? laneHeight,
    double? scrollBeats,
    double? scrollLanes,
  }) => PianoRollView(
    pixelsPerBeat: pixelsPerBeat ?? this.pixelsPerBeat,
    laneHeight: laneHeight ?? this.laneHeight,
    scrollBeats: scrollBeats ?? this.scrollBeats,
    scrollLanes: scrollLanes ?? this.scrollLanes,
  );

  /// Horizontal zoom by [factor], anchored so the beat under [anchorX] (a local
  /// x in pixels) stays put — the pointer-anchored zoom the design requires.
  /// [minPixelsPerBeat] is the fit-to-viewport floor (you can't zoom out past
  /// the whole clip filling the width); [beatSpan] and [viewportWidth] bound the
  /// scroll so the content never pulls away from the edges.
  PianoRollView zoomedHorizontally({
    required double factor,
    required double anchorX,
    required double viewportWidth,
    required int beatSpan,
    required double minPixelsPerBeat,
  }) {
    final next = (pixelsPerBeat * factor)
        .clamp(minPixelsPerBeat, maxPixelsPerBeat)
        .toDouble();
    final beatAtAnchor = scrollBeats + anchorX / pixelsPerBeat;
    final rawScroll = beatAtAnchor - anchorX / next;
    final maxScroll = beatSpan - viewportWidth / next;
    return copyWith(
      pixelsPerBeat: next,
      scrollBeats: _clamp(rawScroll, maxScroll),
    );
  }

  /// Vertical zoom by [factor], anchored so the lane under [anchorY] (a local y
  /// in pixels) stays put. [minLaneHeight] is the fit-to-viewport floor;
  /// [laneSpan] and [viewportHeight] bound the scroll.
  PianoRollView zoomedVertically({
    required double factor,
    required double anchorY,
    required double viewportHeight,
    required int laneSpan,
    required double minLaneHeight,
  }) {
    final next = (laneHeight * factor)
        .clamp(minLaneHeight, maxLaneHeight)
        .toDouble();
    final laneAtAnchor = scrollLanes + anchorY / laneHeight;
    final rawScroll = laneAtAnchor - anchorY / next;
    final maxScroll = laneSpan - viewportHeight / next;
    return copyWith(
      laneHeight: next,
      scrollLanes: _clamp(rawScroll, maxScroll),
    );
  }

  /// Clamp a scroll offset into `[0, max]`, collapsing a negative [max] (content
  /// narrower/shorter than the viewport) to 0.
  static double _clamp(double value, double max) {
    if (max <= 0) return 0;
    if (value < 0) return 0;
    return value > max ? max : value;
  }

  @override
  bool operator ==(Object other) =>
      other is PianoRollView &&
      other.pixelsPerBeat == pixelsPerBeat &&
      other.laneHeight == laneHeight &&
      other.scrollBeats == scrollBeats &&
      other.scrollLanes == scrollLanes;

  @override
  int get hashCode =>
      Object.hash(pixelsPerBeat, laneHeight, scrollBeats, scrollLanes);

  @override
  String toString() =>
      'PianoRollView(ppb: $pixelsPerBeat, lane: $laneHeight, '
      'scrollBeats: $scrollBeats, scrollLanes: $scrollLanes)';
}
