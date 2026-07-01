import 'dart:typed_data';

import '../midi_clip.dart';

/// Encodes a [MidiClip] as a Standard MIDI File (format 0, single track).
///
/// The inverse of [SmfReader]. Pure Dart — the surface layer takes the bytes
/// and writes them to disk. Timing round-trips through the same quarter-note
/// convention: a note's `start`/`duration` beats become `beat * [ticksPerBeat]`
/// ticks. With the default 480 PPQN every 1/480-of-a-quarter grid position is
/// representable exactly, so any sane editor grid survives export → import.
///
/// The track carries a name meta (from [MidiClip.name]), an `x/4` time
/// signature derived from [MidiClip.beatsPerBar], a 120 BPM tempo (Phi has no
/// clip-level tempo yet), then the paired note-on/note-off events and an
/// end-of-track meta. Velocity is de-normalised to `1..127` (0 is reserved for
/// note-off, so a note never encodes as silent).
class SmfWriter {
  const SmfWriter({this.ticksPerBeat = 480});

  /// Pulses per quarter note written into the header division field.
  final int ticksPerBeat;

  Uint8List write(MidiClip clip) {
    final track = _buildTrack(clip);
    final out = BytesBuilder();

    // ── Header chunk ───────────────────────────────────────────────────────
    out.add(_ascii('MThd'));
    _addUint32(out, 6);
    _addUint16(out, 0); // format 0 — single multi-channel track
    _addUint16(out, 1); // one track
    _addUint16(out, ticksPerBeat);

    // ── Track chunk ────────────────────────────────────────────────────────
    out.add(_ascii('MTrk'));
    _addUint32(out, track.length);
    out.add(track);

    return out.toBytes();
  }

  Uint8List _buildTrack(MidiClip clip) {
    // Flatten notes into timed events, then delta-encode. Note-offs sort
    // before note-ons at the same tick so a re-struck pitch isn't silenced by
    // the previous note's release.
    final events = <_Event>[];
    for (final note in clip.notes) {
      final onTick = (note.start * ticksPerBeat).round();
      final offTick = ((note.start + note.duration) * ticksPerBeat).round();
      final channel = note.channel & 0x0F;
      final velocity = (note.velocity * 127).round().clamp(1, 127);
      events.add(_Event(onTick, false, channel, note.pitch, velocity));
      events.add(
        _Event(
          offTick < onTick ? onTick : offTick,
          true,
          channel,
          note.pitch,
          0,
        ),
      );
    }
    events.sort(_Event.compare);

    final body = BytesBuilder();

    // Meta: track name.
    _addDelta(body, 0);
    body.add([0xFF, 0x03]);
    final name = _ascii(clip.name);
    _addVarLen(body, name.length);
    body.add(name);

    // Meta: time signature (beatsPerBar / 4) and 120 BPM tempo.
    _addDelta(body, 0);
    body.add([0xFF, 0x58, 0x04, clip.beatsPerBar & 0xFF, 2, 24, 8]);
    _addDelta(body, 0);
    body.add([0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]); // 500000 µs/quarter

    // Note events.
    var prevTick = 0;
    for (final e in events) {
      _addDelta(body, e.tick - prevTick);
      prevTick = e.tick;
      if (e.isOff) {
        body.add([0x80 | e.channel, e.pitch & 0x7F, 0]);
      } else {
        body.add([0x90 | e.channel, e.pitch & 0x7F, e.velocity]);
      }
    }

    // Meta: end of track.
    _addDelta(body, 0);
    body.add([0xFF, 0x2F, 0x00]);

    return body.toBytes();
  }

  static List<int> _ascii(String s) =>
      s.codeUnits.map((c) => c & 0x7F).toList();

  static void _addUint16(BytesBuilder b, int v) =>
      b.add([(v >> 8) & 0xFF, v & 0xFF]);

  static void _addUint32(BytesBuilder b, int v) =>
      b.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);

  static void _addDelta(BytesBuilder b, int ticks) =>
      _addVarLen(b, ticks < 0 ? 0 : ticks);

  /// SMF variable-length quantity: 7 bits per byte, high bit set on all but
  /// the last.
  static void _addVarLen(BytesBuilder b, int value) {
    final buffer = <int>[value & 0x7F];
    var v = value >> 7;
    while (v > 0) {
      buffer.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    b.add(buffer.reversed.toList());
  }
}

class _Event {
  const _Event(this.tick, this.isOff, this.channel, this.pitch, this.velocity);
  final int tick;
  final bool isOff;
  final int channel;
  final int pitch;
  final int velocity;

  /// Order by tick, then note-off before note-on, then by pitch for a stable,
  /// reproducible byte stream.
  static int compare(_Event a, _Event b) {
    if (a.tick != b.tick) return a.tick - b.tick;
    if (a.isOff != b.isOff) return a.isOff ? -1 : 1;
    return a.pitch - b.pitch;
  }
}
