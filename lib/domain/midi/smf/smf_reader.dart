import 'dart:typed_data';

import '../midi_clip.dart';
import '../midi_note.dart';
import 'smf_exception.dart';

/// Decodes a Standard MIDI File (SMF, `.mid`) byte stream into a [MidiClip].
///
/// Pure Dart — depends only on `dart:typed_data`, so it lives in the domain
/// layer next to the clip model it produces. The engine/surface layers own
/// the file IO that hands raw bytes here; this class never touches disk.
///
/// Supported: format 0/1/2 files with a metrical (ticks-per-quarter) division.
/// All tracks are merged into a single flat clip — Phi has no multi-track
/// model — with note-on/note-off events paired into [MidiNote]s. Timing is
/// expressed in **quarter-note beats** (`ticks / division`), matching the rest
/// of the MIDI domain where a "beat" is a quarter note. Velocity is normalised
/// to `[0, 1]`. Channel and the first time signature are preserved; other
/// channel-voice and meta events (CC, pitch-bend, tempo, …) are skipped — Phi
/// interprets clips through transforms, not raw controller streams.
class SmfReader {
  const SmfReader();

  /// Parse [bytes] into a [MidiClip]. [fallbackName] is used only when the
  /// file carries no track-name meta event. Throws [SmfFormatException] on a
  /// malformed or unsupported stream.
  MidiClip read(Uint8List bytes, {String fallbackName = 'imported'}) {
    final cursor = _Cursor(bytes);

    // ── Header chunk (MThd) ────────────────────────────────────────────────
    if (!cursor.matchTag('MThd')) {
      throw const SmfFormatException('missing MThd header', 0);
    }
    final headerLen = cursor.readUint32();
    final headerEnd = cursor.offset + headerLen;
    if (headerLen < 6) {
      throw SmfFormatException('MThd length $headerLen too short', 4);
    }
    cursor.readUint16(); // format — accepted but unused; all tracks merge.
    final trackCount = cursor.readUint16();
    final division = cursor.readInt16();
    if (division <= 0) {
      throw const SmfFormatException(
        'SMPTE time division is not supported',
        12,
      );
    }
    // Tolerate a header longer than 6 bytes (some writers pad it).
    cursor.offset = headerEnd;

    // ── Track chunks (MTrk) ────────────────────────────────────────────────
    final notes = <MidiNote>[];
    String? clipName;
    int? tsNumerator;
    int? tsDenominator;

    for (var t = 0; t < trackCount && !cursor.atEnd; t++) {
      if (!cursor.matchTag('MTrk')) {
        // A non-MTrk chunk (matchTag left the cursor on the tag): skip the
        // whole chunk by its length prefix, per the SMF spec, without
        // counting it against the track budget.
        cursor.readTag();
        final skipLen = cursor.readUint32();
        cursor.offset += skipLen;
        t--;
        continue;
      }
      final trackLen = cursor.readUint32();
      final trackEnd = cursor.offset + trackLen;

      var absTick = 0;
      var runningStatus = 0;
      // Pending note-ons keyed by (channel, pitch); FIFO so overlapping
      // repeats of the same pitch pair oldest-on to next-off.
      final pending = <int, List<_PendingNote>>{};

      while (cursor.offset < trackEnd) {
        absTick += cursor.readVarLen();
        var status = cursor.peekByte();

        if (status < 0x80) {
          // Running status: reuse the previous channel-voice status byte.
          if (runningStatus == 0) {
            throw SmfFormatException(
              'running status with no prior status byte',
              cursor.offset,
            );
          }
          status = runningStatus;
        } else {
          cursor.readByte();
          if (status < 0xF0) runningStatus = status;
        }

        if (status == 0xFF) {
          // Meta event.
          final metaType = cursor.readByte();
          final len = cursor.readVarLen();
          final data = cursor.readBytes(len);
          switch (metaType) {
            case 0x03: // track / sequence name
              clipName ??= _decodeText(data);
            case 0x58 when data.length >= 2: // time signature
              tsNumerator ??= data[0];
              tsDenominator ??= 1 << data[1];
          }
          continue;
        }

        if (status == 0xF0 || status == 0xF7) {
          // SysEx — length-prefixed, skipped.
          final len = cursor.readVarLen();
          cursor.offset += len;
          continue;
        }

        final command = status & 0xF0;
        final channel = status & 0x0F;
        switch (command) {
          case 0x90: // note on (velocity 0 == note off)
            final pitch = cursor.readByte();
            final velocity = cursor.readByte();
            if (velocity == 0) {
              _closeNote(notes, pending, channel, pitch, absTick, division);
            } else {
              (pending[_voiceKey(channel, pitch)] ??= []).add(
                _PendingNote(channel, pitch, absTick, velocity),
              );
            }
          case 0x80: // note off
            final pitch = cursor.readByte();
            cursor.readByte(); // release velocity — unused
            _closeNote(notes, pending, channel, pitch, absTick, division);
          case 0xC0: // program change — 1 data byte
          case 0xD0: // channel pressure — 1 data byte
            cursor.readByte();
          case 0xA0: // poly aftertouch — 2 data bytes
          case 0xB0: // control change — 2 data bytes
          case 0xE0: // pitch bend — 2 data bytes
            cursor.readByte();
            cursor.readByte();
          default:
            throw SmfFormatException(
              'unexpected status byte 0x${status.toRadixString(16)}',
              cursor.offset,
            );
        }
      }

      // Any note-on still open at track end gets clipped to the last event
      // tick — a defensive close for malformed tracks with no note-off.
      for (final list in pending.values) {
        for (final p in list) {
          notes.add(_noteFrom(p, absTick, division));
        }
      }

      cursor.offset = trackEnd;
    }

    final beatsPerBar = _beatsPerBar(tsNumerator, tsDenominator);
    final bars = _barsFor(notes, beatsPerBar);
    return MidiClip(
      name: clipName ?? fallbackName,
      notes: notes,
      bars: bars,
      beatsPerBar: beatsPerBar,
    );
  }

  static void _closeNote(
    List<MidiNote> notes,
    Map<int, List<_PendingNote>> pending,
    int channel,
    int pitch,
    int offTick,
    int division,
  ) {
    final list = pending[_voiceKey(channel, pitch)];
    if (list == null || list.isEmpty) return; // orphan note-off — ignore.
    final on = list.removeAt(0);
    notes.add(
      MidiNote(
        pitch: pitch,
        start: on.tick / division,
        duration: (offTick - on.tick) / division,
        velocity: on.velocity / 127.0,
        channel: channel,
      ),
    );
  }

  static MidiNote _noteFrom(_PendingNote on, int offTick, int division) =>
      MidiNote(
        pitch: on.pitch,
        start: on.tick / division,
        duration: (offTick - on.tick) / division,
        velocity: on.velocity / 127.0,
        channel: on.channel,
      );

  static int _voiceKey(int channel, int pitch) => channel * 128 + pitch;

  static int _beatsPerBar(int? numerator, int? denominator) {
    if (numerator == null || denominator == null || denominator == 0) return 4;
    // Express the bar length in quarter-note beats: a x/y bar spans
    // x * (4 / y) quarters. 4/4 → 4, 6/8 → 3, 3/4 → 3.
    final quarters = (numerator * 4 / denominator).round();
    return quarters < 1 ? 1 : quarters;
  }

  static int _barsFor(List<MidiNote> notes, int beatsPerBar) {
    var maxEnd = 0.0;
    for (final n in notes) {
      final end = n.start + n.duration;
      if (end > maxEnd) maxEnd = end;
    }
    if (maxEnd <= 0) return 1;
    final bars = (maxEnd / beatsPerBar).ceil();
    return bars < 1 ? 1 : bars;
  }

  static String _decodeText(List<int> data) {
    // SMF text is Latin-1 by convention; map bytes straight to code units.
    return String.fromCharCodes(data);
  }
}

class _PendingNote {
  const _PendingNote(this.channel, this.pitch, this.tick, this.velocity);
  final int channel;
  final int pitch;
  final int tick;
  final int velocity;
}

/// Big-endian byte cursor over the file, with the SMF-specific variable-length
/// quantity reader.
class _Cursor {
  _Cursor(this._bytes);
  final Uint8List _bytes;
  int offset = 0;

  bool get atEnd => offset >= _bytes.length;

  int peekByte() {
    _need(1);
    return _bytes[offset];
  }

  int readByte() {
    _need(1);
    return _bytes[offset++];
  }

  Uint8List readBytes(int n) {
    _need(n);
    final out = Uint8List.sublistView(_bytes, offset, offset + n);
    offset += n;
    return out;
  }

  int readUint16() => (readByte() << 8) | readByte();

  int readInt16() {
    final v = readUint16();
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  int readUint32() =>
      (readByte() << 24) | (readByte() << 16) | (readByte() << 8) | readByte();

  String readTag() => String.fromCharCodes(readBytes(4));

  bool matchTag(String tag) {
    _need(4);
    for (var i = 0; i < 4; i++) {
      if (_bytes[offset + i] != tag.codeUnitAt(i)) return false;
    }
    offset += 4;
    return true;
  }

  /// SMF variable-length quantity: 7 bits per byte, high bit = continue.
  int readVarLen() {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final b = readByte();
      value = (value << 7) | (b & 0x7F);
      if (b & 0x80 == 0) return value;
    }
    throw SmfFormatException('variable-length quantity too long', offset);
  }

  void _need(int n) {
    if (offset + n > _bytes.length) {
      throw SmfFormatException(
        'unexpected end of file (need $n byte(s))',
        offset,
      );
    }
  }
}
