import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/surfaces/midi/piano_roll_geometry.dart';
import 'package:phi/surfaces/midi/piano_roll_view.dart';

void main() {
  const geo = PianoRollGeometry(
    size: Size(400, 200),
    bars: 4,
    beatsPerBar: 4,
    minPitch: 55,
    maxPitch: 76,
  );

  group('PianoRollGeometry', () {
    test('beat ↔ x round-trips', () {
      expect(geo.beatSpan, 16);
      expect(geo.xForBeat(8), 200);
      expect(geo.beatForX(200), 8);
      expect(geo.widthForBeats(4), 100);
    });

    test('pitch ↔ y maps the window to the height', () {
      expect(geo.yForPitch(76), 0);
      expect(geo.yForPitch(55), 200);
      expect(geo.pitchForY(0), 76);
      expect(geo.pitchForY(200), 55);
    });

    test('a fractional pitch lands between two lanes (issue #36)', () {
      // laneHeight = 200 / 21 ≈ 9.524. Pitch 60 and 61 are one lane apart;
      // 60.5 sits exactly halfway between their lane lines.
      final y60 = geo.yForPitch(60);
      final y61 = geo.yForPitch(61);
      expect(geo.yForPitch(60.5), closeTo((y60 + y61) / 2, 1e-9));
    });

    test('out-of-window pitch clamps into the visible band', () {
      expect(geo.yForPitch(200), 0);
      expect(geo.pitchForY(10000), 55);
    });

    test('empty meter never divides by zero', () {
      const degenerate = PianoRollGeometry(
        size: Size(100, 100),
        bars: 0,
        beatsPerBar: 0,
      );
      expect(degenerate.beatSpan, 1);
      expect(degenerate.xForBeat(0), 0);
    });

    test('hitTest resolves body / left / right zones', () {
      const note = MidiNote(pitch: 65, start: 4, duration: 4, velocity: 1);
      final left = geo.xForBeat(4);
      final right = geo.xForBeat(8);
      final y = geo.yForPitch(65);

      expect(
        geo.hitTest(const [note], Offset((left + right) / 2, y))?.edge,
        NoteEdge.body,
      );
      expect(
        geo.hitTest(const [note], Offset(left + 1, y))?.edge,
        NoteEdge.left,
      );
      expect(
        geo.hitTest(const [note], Offset(right - 1, y))?.edge,
        NoteEdge.right,
      );
    });

    test('hitTest misses empty space and returns the topmost note', () {
      const a = MidiNote(pitch: 60, start: 0, duration: 2, velocity: 1);
      const b = MidiNote(pitch: 60, start: 0, duration: 2, velocity: 1);
      // Same lane + span: the later note in the list wins (drawn on top).
      final hit = geo.hitTest(const [
        a,
        b,
      ], Offset(geo.xForBeat(1), geo.yForPitch(60)));
      expect(hit?.index, 1);
      expect(geo.hitTest(const [a], const Offset(399, 5)), isNull);
    });
  });

  group('PianoRollGeometry — with a zoom view (issue #189)', () {
    test('a null view fits the clip to the area (unchanged default)', () {
      // Same numbers as the fit-to-size group above.
      expect(geo.pixelsPerBeat, 400 / 16);
      expect(geo.xForBeat(8), 200);
      expect(geo.beatForX(200), 8);
    });

    test('pixels-per-beat + scroll parametrise the horizontal axis', () {
      const view = PianoRollView(
        pixelsPerBeat: 40,
        laneHeight: 12,
        scrollBeats: 3,
      );
      const zoomed = PianoRollGeometry(
        size: Size(400, 200),
        bars: 4,
        beatsPerBar: 4,
        view: view,
      );
      expect(zoomed.pixelsPerBeat, 40);
      // Beat 3 sits at the left edge; each beat is 40px wide.
      expect(zoomed.xForBeat(3), 0);
      expect(zoomed.xForBeat(5), 80);
      expect(zoomed.beatForX(0), 3);
      expect(zoomed.widthForBeats(2), 80);
    });

    test('lane-height + scroll parametrise the vertical axis', () {
      const view = PianoRollView(
        pixelsPerBeat: 40,
        laneHeight: 12,
        scrollLanes: 2,
      );
      const zoomed = PianoRollGeometry(
        size: Size(400, 200),
        bars: 4,
        beatsPerBar: 4,
        view: view,
      );
      expect(zoomed.laneHeight, 12);
      // maxPitch (76) is scrolled 2 lanes above the top edge → its line is at
      // y = -24; the pitch two lanes down (74) sits at the top edge.
      expect(zoomed.yForPitch(76), -24);
      expect(zoomed.yForPitch(74), 0);
      expect(zoomed.pitchForY(0), 74);
      expect(zoomed.laneLineY(2), 0);
    });
  });
}
