import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/smf/smf_exception.dart';
import 'package:phi/domain/midi/smf/smf_reader.dart';
import 'package:phi/domain/midi/smf/smf_writer.dart';

/// Notes compared modulo channel + meter (per issue #30's round-trip
/// property), and order-independent since export sorts by tick while the
/// source list is in authoring order.
List<MidiNote> _sorted(List<MidiNote> notes) {
  final copy = List<MidiNote>.of(notes)
    ..sort((a, b) {
      if (a.start != b.start) return a.start.compareTo(b.start);
      return a.pitch - b.pitch;
    });
  return copy;
}

void main() {
  const reader = SmfReader();
  const writer = SmfWriter();

  group('round-trip', () {
    test(
      'import(export(clip)).notes == clip.notes (modulo channel + meter)',
      () {
        // Velocities are multiples of 1/127 so they survive the 7-bit de/re-
        // normalisation exactly; starts/durations are on a 1/16 grid so
        // beat → tick → beat is exact at 480 PPQN.
        final clip = MidiClip(
          name: 'phrase A',
          bars: 4,
          beatsPerBar: 4,
          notes: const [
            MidiNote(
              pitch: 60,
              start: 0.00,
              duration: 0.25,
              velocity: 100 / 127,
            ),
            MidiNote(
              pitch: 63,
              start: 0.25,
              duration: 0.25,
              velocity: 76 / 127,
            ),
            MidiNote(
              pitch: 67,
              start: 0.50,
              duration: 0.50,
              velocity: 127 / 127,
            ),
            MidiNote(
              pitch: 70,
              start: 1.00,
              duration: 0.75,
              velocity: 64 / 127,
            ),
            MidiNote(
              pitch: 72,
              start: 3.50,
              duration: 0.50,
              velocity: 90 / 127,
            ),
          ],
        );

        final round = reader.read(writer.write(clip));

        expect(round.notes.length, clip.notes.length);
        expect(_sorted(round.notes), _sorted(clip.notes));
      },
    );

    test('preserves per-note channel through the round trip', () {
      final clip = MidiClip(
        name: 'multi',
        bars: 1,
        notes: const [
          MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1, channel: 0),
          MidiNote(pitch: 64, start: 0, duration: 1, velocity: 1, channel: 5),
          MidiNote(pitch: 67, start: 0, duration: 1, velocity: 1, channel: 9),
        ],
      );

      final round = reader.read(writer.write(clip));
      final channels = _sorted(round.notes).map((n) => n.channel).toList();
      expect(channels, [0, 5, 9]);
    });

    test('overlapping repeats of the same pitch stay paired (FIFO)', () {
      final clip = MidiClip(
        name: 'overlap',
        bars: 1,
        notes: const [
          MidiNote(pitch: 60, start: 0.0, duration: 1.0, velocity: 1),
          MidiNote(pitch: 60, start: 0.5, duration: 1.0, velocity: 1),
        ],
      );

      final round = _sorted(reader.read(writer.write(clip)).notes);
      expect(round.length, 2);
      expect(round[0].start, 0.0);
      expect(round[0].duration, 1.0);
      expect(round[1].start, 0.5);
      expect(round[1].duration, 1.0);
    });
  });

  group('reader', () {
    test('note-on with velocity 0 is treated as a note-off', () {
      // MThd + one MTrk: note-on 60, then note-on 60 vel 0 at delta 480.
      final bytes = _smf(
        division: 480,
        trackEvents: [
          0x00, 0x90, 60, 100, // note on
          0x83, 0x60, 0x90, 60, 0, // +480 ticks: note on vel 0 (== off)
          0x00, 0xFF, 0x2F, 0x00, // end of track
        ],
      );

      final clip = reader.read(bytes);
      expect(clip.notes.length, 1);
      expect(clip.notes.single.pitch, 60);
      expect(clip.notes.single.start, 0.0);
      expect(clip.notes.single.duration, 1.0); // 480 ticks / 480 PPQN
    });

    test('honours running status for consecutive note-ons', () {
      // One 0x90 status, then a bare data pair reusing it, then offs.
      final bytes = _smf(
        division: 480,
        trackEvents: [
          0x00, 0x90, 60, 100, // note on 60
          0x00, 64, 100, // running status: note on 64
          0x83, 0x60, 0x80, 60, 0, // +480: note off 60
          0x00, 0x80, 64, 0, // note off 64
          0x00, 0xFF, 0x2F, 0x00,
        ],
      );

      final clip = reader.read(bytes);
      expect(clip.notes.length, 2);
      expect(_sorted(clip.notes).map((n) => n.pitch), [60, 64]);
    });

    test('reads the track name and time signature', () {
      final name = 'bassline'.codeUnits;
      final bytes = _smf(
        division: 480,
        trackEvents: [
          0x00, 0xFF, 0x03, name.length, ...name, // track name
          0x00, 0xFF, 0x58, 0x04, 3, 2, 24, 8, // 3/4 time
          0x00, 0x90, 48, 80,
          0x83, 0x60, 0x80, 48, 0,
          0x00, 0xFF, 0x2F, 0x00,
        ],
      );

      final clip = reader.read(bytes);
      expect(clip.name, 'bassline');
      expect(clip.beatsPerBar, 3); // 3/4 → 3 quarter-note beats per bar
    });

    test('6/8 maps to 3 quarter-note beats per bar', () {
      final bytes = _smf(
        division: 480,
        trackEvents: [
          0x00, 0xFF, 0x58, 0x04, 6, 3, 24, 8, // 6/8
          0x00, 0x90, 48, 80,
          0x81, 0x70, 0x80, 48, 0,
          0x00, 0xFF, 0x2F, 0x00,
        ],
      );
      expect(reader.read(bytes).beatsPerBar, 3);
    });

    test('falls back to the given name when no name meta is present', () {
      final bytes = _smf(
        division: 480,
        trackEvents: [
          0x00,
          0x90,
          60,
          100,
          0x81,
          0x70,
          0x80,
          60,
          0,
          0x00,
          0xFF,
          0x2F,
          0x00,
        ],
      );
      expect(reader.read(bytes, fallbackName: 'dropped').name, 'dropped');
    });
  });

  group('malformed input', () {
    test('rejects a stream that does not start with MThd', () {
      expect(
        () => reader.read(Uint8List.fromList('NOPE'.codeUnits)),
        throwsA(isA<SmfFormatException>()),
      );
    });

    test('rejects SMPTE time division', () {
      final bytes = Uint8List.fromList([
        ...'MThd'.codeUnits,
        0, 0, 0, 6,
        0, 0, // format
        0, 1, // ntrks
        0xE8, 0x00, // negative division (SMPTE)
      ]);
      expect(() => reader.read(bytes), throwsA(isA<SmfFormatException>()));
    });

    test('rejects a truncated stream', () {
      final bytes = Uint8List.fromList('MThd'.codeUnits); // header cut short
      expect(() => reader.read(bytes), throwsA(isA<SmfFormatException>()));
    });
  });

  group('writer', () {
    test('emits a well-formed format-0 header', () {
      final bytes = writer.write(MidiClip(name: 'x', bars: 1, notes: const []));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'MThd');
      expect(bytes.sublist(4, 8), [0, 0, 0, 6]); // header length
      expect(bytes.sublist(8, 10), [0, 0]); // format 0
      expect(bytes.sublist(10, 12), [0, 1]); // one track
      expect(bytes.sublist(12, 14), [0x01, 0xE0]); // 480 PPQN
      expect(String.fromCharCodes(bytes.sublist(14, 18)), 'MTrk');
    });
  });
}

/// Builds a minimal single-track SMF from a raw [trackEvents] byte list
/// (delta-times included) so reader tests can exercise exact event streams.
Uint8List _smf({required int division, required List<int> trackEvents}) {
  final b = BytesBuilder();
  b.add('MThd'.codeUnits);
  b.add([0, 0, 0, 6]);
  b.add([0, 0]); // format 0
  b.add([0, 1]); // one track
  b.add([(division >> 8) & 0xFF, division & 0xFF]);
  b.add('MTrk'.codeUnits);
  final len = trackEvents.length;
  b.add([
    (len >> 24) & 0xFF,
    (len >> 16) & 0xFF,
    (len >> 8) & 0xFF,
    len & 0xFF,
  ]);
  b.add(trackEvents);
  return b.toBytes();
}
