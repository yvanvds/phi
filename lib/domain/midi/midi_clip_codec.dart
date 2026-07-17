import '../project/store/entity_payload_codec.dart';
import 'midi_clip.dart';
import 'midi_note.dart';

/// The per-kind [EntityPayloadCodec] for `clip.` entities (design
/// `docs/design/project-registry.md` §5) — it (de)serialises a clip's **source**
/// material.
///
/// A clip is "interpreted, not played": the source [MidiClip] (its notes and
/// meter) is the authored material a `MidiTransformChain` reads. This codec
/// persists exactly that source — the transform chain / graph is a separate
/// serialisation surface deferred beyond the v1 migration. The clip's display
/// [MidiClip.name] is stored in the payload because it may contain characters the
/// entity address (a slug of it) cannot.
///
/// Payloads are the typed [MidiClip] in memory; [encode] flattens one to a JSON
/// map and [decode] rebuilds it, stamped at schema [version] `1`.
class MidiClipCodec implements EntityPayloadCodec {
  /// A `const` codec — it holds no state.
  const MidiClipCodec();

  @override
  int get version => 1;

  @override
  Object? encode(Object? payload) {
    if (payload == null) return null;
    final clip = payload as MidiClip;
    return <String, Object?>{
      'name': clip.name,
      'bars': clip.bars,
      'beatsPerBar': clip.beatsPerBar,
      'notes': [
        for (final note in clip.notes)
          <String, Object?>{
            'pitch': note.pitch,
            'start': note.start,
            'duration': note.duration,
            'velocity': note.velocity,
            'channel': note.channel,
          },
      ],
    };
  }

  @override
  Object? decode(Object? json, int version) {
    if (json == null) return null;
    final map = json as Map<String, Object?>;
    final rawNotes = (map['notes'] as List<Object?>? ?? const []);
    return MidiClip(
      name: map['name'] as String? ?? 'clip',
      bars: (map['bars'] as num?)?.toInt() ?? 4,
      beatsPerBar: (map['beatsPerBar'] as num?)?.toInt() ?? 4,
      notes: [
        for (final raw in rawNotes)
          if (raw is Map<String, Object?>)
            MidiNote(
              pitch: (raw['pitch'] as num?)?.toDouble() ?? 0,
              start: (raw['start'] as num?)?.toDouble() ?? 0,
              duration: (raw['duration'] as num?)?.toDouble() ?? 0,
              velocity: (raw['velocity'] as num?)?.toDouble() ?? 0,
              channel: (raw['channel'] as num?)?.toInt() ?? 0,
            ),
      ],
    );
  }
}
