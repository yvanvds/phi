import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/surfaces/midi/piano_roll_geometry.dart';
import 'package:phi/surfaces/midi/piano_roll_view.dart';

/// A 400×200 area over a 4-bar 4/4 clip (16 beats, 21 lanes) — the fit scale is
/// 25 px/beat and ~9.52 px/lane, matching the geometry tests.
const _size = Size(400, 200);
const _bars = 4;
const _beatsPerBar = 4;
const _minPitch = 55;
const _maxPitch = 76;
const _beatSpan = _bars * _beatsPerBar; // 16
const _laneSpan = _maxPitch - _minPitch; // 21
const _fitPixelsPerBeat = 400 / _beatSpan; // 25
const _fitLaneHeight = 200 / _laneSpan;

PianoRollGeometry _geo(PianoRollView? view) => PianoRollGeometry(
  size: _size,
  bars: _bars,
  beatsPerBar: _beatsPerBar,
  minPitch: _minPitch,
  maxPitch: _maxPitch,
  view: view,
);

PianoRollView get _fit => const PianoRollView(
  pixelsPerBeat: _fitPixelsPerBeat,
  laneHeight: _fitLaneHeight,
);

void main() {
  group('PianoRollView — pointer-anchored horizontal zoom', () {
    test('the beat under the cursor stays put on zoom-in', () {
      const anchorX = 250.0;
      final before = _geo(_fit).beatForX(anchorX);

      final zoomed = _fit.zoomedHorizontally(
        factor: 1.5,
        anchorX: anchorX,
        viewportWidth: _size.width,
        beatSpan: _beatSpan,
        minPixelsPerBeat: _fitPixelsPerBeat,
      );

      // Magnified, and the beat under the pointer is unchanged.
      expect(zoomed.pixelsPerBeat, greaterThan(_fitPixelsPerBeat));
      expect(_geo(zoomed).beatForX(anchorX), closeTo(before, 1e-9));
    });

    test('the beat under the cursor stays put on zoom-out', () {
      const anchorX = 120.0;
      // Start already zoomed in so there is room to zoom back out.
      final zoomedIn = _fit.zoomedHorizontally(
        factor: 3,
        anchorX: anchorX,
        viewportWidth: _size.width,
        beatSpan: _beatSpan,
        minPixelsPerBeat: _fitPixelsPerBeat,
      );
      final before = _geo(zoomedIn).beatForX(anchorX);

      final zoomedOut = zoomedIn.zoomedHorizontally(
        factor: 1 / 1.5,
        anchorX: anchorX,
        viewportWidth: _size.width,
        beatSpan: _beatSpan,
        minPixelsPerBeat: _fitPixelsPerBeat,
      );

      expect(zoomedOut.pixelsPerBeat, lessThan(zoomedIn.pixelsPerBeat));
      expect(_geo(zoomedOut).beatForX(anchorX), closeTo(before, 1e-9));
    });

    test('cannot zoom out past the fit scale, and then sits at the origin', () {
      final zoomed = _fit.zoomedHorizontally(
        factor: 0.1,
        anchorX: 200,
        viewportWidth: _size.width,
        beatSpan: _beatSpan,
        minPixelsPerBeat: _fitPixelsPerBeat,
      );
      expect(zoomed.pixelsPerBeat, _fitPixelsPerBeat);
      expect(zoomed.scrollBeats, 0);
    });

    test('scroll never runs the content off the right edge', () {
      // Zoom hard, anchored at the far right — the clamp keeps the last beat in.
      final zoomed = _fit.zoomedHorizontally(
        factor: 4,
        anchorX: _size.width, // right edge
        viewportWidth: _size.width,
        beatSpan: _beatSpan,
        minPixelsPerBeat: _fitPixelsPerBeat,
      );
      final rightBeat = _geo(zoomed).beatForX(_size.width);
      expect(rightBeat, lessThanOrEqualTo(_beatSpan + 1e-9));
    });

    test('a stuck wheel cannot magnify past the ceiling', () {
      var view = _fit;
      for (var i = 0; i < 200; i++) {
        view = view.zoomedHorizontally(
          factor: 2,
          anchorX: 200,
          viewportWidth: _size.width,
          beatSpan: _beatSpan,
          minPixelsPerBeat: _fitPixelsPerBeat,
        );
      }
      expect(view.pixelsPerBeat, PianoRollView.maxPixelsPerBeat);
    });
  });

  group('PianoRollView — pointer-anchored vertical zoom', () {
    test('the pitch under the cursor stays put, horizontal untouched', () {
      const anchorY = 130.0;
      final before = _geo(_fit).pitchForY(anchorY);

      final zoomed = _fit.zoomedVertically(
        factor: 1.5,
        anchorY: anchorY,
        viewportHeight: _size.height,
        laneSpan: _laneSpan,
        minLaneHeight: _fitLaneHeight,
      );

      expect(zoomed.laneHeight, greaterThan(_fitLaneHeight));
      // Horizontal zoom is independent — untouched by a vertical gesture.
      expect(zoomed.pixelsPerBeat, _fitPixelsPerBeat);
      expect(zoomed.scrollBeats, 0);
      // The rounded lane under the cursor is unchanged.
      expect(_geo(zoomed).pitchForY(anchorY), before);
    });

    test('cannot zoom out past the fit lane height', () {
      final zoomed = _fit.zoomedVertically(
        factor: 0.2,
        anchorY: 100,
        viewportHeight: _size.height,
        laneSpan: _laneSpan,
        minLaneHeight: _fitLaneHeight,
      );
      expect(zoomed.laneHeight, _fitLaneHeight);
      expect(zoomed.scrollLanes, 0);
    });
  });

  group('PianoRollView — pan / scroll (issue #198)', () {
    // A view zoomed 4× on both axes, so there is real room to pan.
    PianoRollView zoomed() => _fit
        .zoomedHorizontally(
          factor: 4,
          anchorX: 0,
          viewportWidth: _size.width,
          beatSpan: _beatSpan,
          minPixelsPerBeat: _fitPixelsPerBeat,
        )
        .zoomedVertically(
          factor: 4,
          anchorY: 0,
          viewportHeight: _size.height,
          laneSpan: _laneSpan,
          minLaneHeight: _fitLaneHeight,
        );

    test('max scroll is the content minus what the viewport shows', () {
      final v = zoomed();
      expect(
        v.maxScrollBeats(viewportWidth: _size.width, beatSpan: _beatSpan),
        closeTo(_beatSpan - _size.width / v.pixelsPerBeat, 1e-9),
      );
      expect(
        v.maxScrollLanes(viewportHeight: _size.height, laneSpan: _laneSpan),
        closeTo(_laneSpan - _size.height / v.laneHeight, 1e-9),
      );
    });

    test('the fitted view has nothing to scroll on either axis', () {
      expect(
        _fit.maxScrollBeats(viewportWidth: _size.width, beatSpan: _beatSpan),
        0,
      );
      expect(
        _fit.maxScrollLanes(viewportHeight: _size.height, laneSpan: _laneSpan),
        0,
      );
    });

    test('dragging content right reveals earlier beats (scroll shrinks)', () {
      final v = zoomed().withScrollBeats(
        6,
        viewportWidth: _size.width,
        beatSpan: _beatSpan,
      );
      final panned = v.pannedBy(
        dxPixels: 50,
        dyPixels: 0,
        viewportWidth: _size.width,
        viewportHeight: _size.height,
        beatSpan: _beatSpan,
        laneSpan: _laneSpan,
      );
      expect(panned.scrollBeats, closeTo(6 - 50 / v.pixelsPerBeat, 1e-9));
      // A horizontal-only drag leaves the vertical scroll alone.
      expect(panned.scrollLanes, v.scrollLanes);
    });

    test('a pan cannot run off the leading edge (clamped at 0)', () {
      final panned = zoomed().pannedBy(
        dxPixels: 100000,
        dyPixels: 100000,
        viewportWidth: _size.width,
        viewportHeight: _size.height,
        beatSpan: _beatSpan,
        laneSpan: _laneSpan,
      );
      expect(panned.scrollBeats, 0);
      expect(panned.scrollLanes, 0);
    });

    test('a pan cannot run off the trailing edge (clamped at max)', () {
      final v = zoomed();
      final panned = v.pannedBy(
        dxPixels: -100000,
        dyPixels: -100000,
        viewportWidth: _size.width,
        viewportHeight: _size.height,
        beatSpan: _beatSpan,
        laneSpan: _laneSpan,
      );
      expect(
        panned.scrollBeats,
        closeTo(
          v.maxScrollBeats(viewportWidth: _size.width, beatSpan: _beatSpan),
          1e-9,
        ),
      );
      expect(
        panned.scrollLanes,
        closeTo(
          v.maxScrollLanes(viewportHeight: _size.height, laneSpan: _laneSpan),
          1e-9,
        ),
      );
    });

    test('withScrollBeats / withScrollLanes clamp into range', () {
      final v = zoomed();
      expect(
        v
            .withScrollBeats(
              -5,
              viewportWidth: _size.width,
              beatSpan: _beatSpan,
            )
            .scrollBeats,
        0,
      );
      final maxB = v.maxScrollBeats(
        viewportWidth: _size.width,
        beatSpan: _beatSpan,
      );
      expect(
        v
            .withScrollBeats(
              9999,
              viewportWidth: _size.width,
              beatSpan: _beatSpan,
            )
            .scrollBeats,
        maxB,
      );
      final maxL = v.maxScrollLanes(
        viewportHeight: _size.height,
        laneSpan: _laneSpan,
      );
      expect(
        v
            .withScrollLanes(
              9999,
              viewportHeight: _size.height,
              laneSpan: _laneSpan,
            )
            .scrollLanes,
        maxL,
      );
    });
  });

  test('value equality distinguishes zoom + scroll', () {
    const a = PianoRollView(pixelsPerBeat: 30, laneHeight: 10);
    const b = PianoRollView(pixelsPerBeat: 30, laneHeight: 10);
    const c = PianoRollView(pixelsPerBeat: 30, laneHeight: 10, scrollBeats: 1);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
