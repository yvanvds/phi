import '../graph/midi_transform_graph.dart';
import '../midi_clip.dart';
import '../midi_clip_mode.dart';
import '../midi_note.dart';
import '../midi_transform.dart';
import 'midi_transform_codec.dart';
import 'midi_transform_graph_codec.dart';

/// The complete persistable state of a `clip.` entity — its **source** notes
/// plus its **interpretation** (issue #135).
///
/// #124 migrated a clip's source [MidiClip] into the registry but deferred the
/// interpretation: a clip is "interpreted, not played", and the chain / graph is
/// that interpretation. This value type bundles both so save/reload restores the
/// whole clip, not just its notes:
/// - [source] — the authored notes + meter (the old v1 payload).
/// - [mode] — whether the clip is a linear [MidiClipMode.chain] or a branching
///   [MidiClipMode.graph].
/// - [chain] — the linear transform list (the chain mode's pipeline).
/// - [graph] — the branching [MidiTransformGraph], present once the clip has been
///   converted to graph mode (else `null`).
/// - [loop] — whether playback loops the clip's declared length (issue #184,
///   design §7 decision 4). **On by default** for new clips; performance play
///   state itself is never persisted (a loaded project starts silent).
///
/// [toJson] / [fromJson] are the wire form; the `clip.` [MidiClipCodec] wraps
/// them behind the store's per-kind codec seam and handles the v1 → v2 migration.
class ClipDocument {
  ClipDocument({
    required this.source,
    this.mode = MidiClipMode.chain,
    this.chain = const [],
    this.graph,
    this.loop = true,
  });

  /// Rebuilds a document from the map [toJson] produced, migrating the v1 form
  /// (a bare clip — just notes + meter, no `source` key) forward to a document
  /// whose [source] is that clip with an empty [chain].
  ///
  /// [transformCodec] decodes the chain / graph node transforms; pass one
  /// carrying a `CustomTransformRegistry` to re-link live-coded transforms.
  factory ClipDocument.fromJson(
    Map<String, Object?> json, {
    MidiTransformCodec transformCodec = const MidiTransformCodec(),
  }) {
    // v1 payloads are the bare clip (top-level `notes`/`bars`), with no `source`
    // sub-map. Detect that shape and wrap it — the migration seam.
    if (json['source'] is! Map) {
      return ClipDocument(source: clipFromJson(json));
    }
    final source = clipFromJson(_map(json['source']));
    final graphCodec = MidiTransformGraphCodec(transformCodec: transformCodec);
    return ClipDocument(
      source: source,
      mode: _mode(json['mode']),
      chain: [
        for (final raw in _list(json['chain']))
          transformCodec.decode(_map(raw)),
      ],
      graph: json['graph'] is Map
          ? graphCodec.decode(_map(json['graph']), source)
          : null,
      // Absent on pre-#184 payloads → defaults on, matching a fresh clip.
      loop: json['loop'] as bool? ?? true,
    );
  }

  /// The authored source material — notes + meter.
  final MidiClip source;

  /// Which interpretation the clip uses — linear chain or branching graph.
  final MidiClipMode mode;

  /// The linear transform pipeline (chain mode).
  final List<MidiTransform> chain;

  /// The branching transform graph, or `null` if the clip is chain-only.
  final MidiTransformGraph? graph;

  /// Whether playback loops the clip's declared length. On by default; see the
  /// class doc (issue #184, design §7 decision 4).
  final bool loop;

  /// Flattens the document to a JSON-compatible map. [transformCodec] encodes
  /// the chain / graph node transforms.
  Map<String, Object?> toJson({
    MidiTransformCodec transformCodec = const MidiTransformCodec(),
  }) {
    final graphCodec = MidiTransformGraphCodec(transformCodec: transformCodec);
    return <String, Object?>{
      'source': clipToJson(source),
      'mode': mode.name,
      'chain': [for (final t in chain) transformCodec.encode(t)],
      if (graph != null) 'graph': graphCodec.encode(graph!),
      'loop': loop,
    };
  }

  // ── clip source (de)serialisation ──────────────────────────────────────────

  /// The JSON form of a source [MidiClip] — its meter and notes. Shared by
  /// [toJson] and the v1 migration so the clip encoding lives in one place.
  ///
  /// The clip carries no display name (issue #184); a `name` on a legacy payload
  /// is simply no longer written or read.
  static Map<String, Object?> clipToJson(MidiClip clip) => <String, Object?>{
    'bars': clip.bars,
    'beatsPerBar': clip.beatsPerBar,
    'notes': [for (final note in clip.notes) _noteToJson(note)],
  };

  /// Rebuilds a source [MidiClip] from the map [clipToJson] produced (also the
  /// whole v1 payload). Any `name` a legacy payload carries is ignored.
  static MidiClip clipFromJson(Map<String, Object?> json) => MidiClip(
    bars: (json['bars'] as num?)?.toInt() ?? 4,
    beatsPerBar: (json['beatsPerBar'] as num?)?.toInt() ?? 4,
    notes: [
      for (final raw in _list(json['notes']))
        if (raw is Map) _noteFromJson(raw.cast<String, Object?>()),
    ],
  );

  static Map<String, Object?> _noteToJson(MidiNote note) => <String, Object?>{
    'pitch': note.pitch,
    'start': note.start,
    'duration': note.duration,
    'velocity': note.velocity,
    if (note.voice != null) 'voice': note.voice,
  };

  static MidiNote _noteFromJson(Map<String, Object?> json) => MidiNote(
    pitch: (json['pitch'] as num?)?.toDouble() ?? 0,
    start: (json['start'] as num?)?.toDouble() ?? 0,
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    velocity: (json['velocity'] as num?)?.toDouble() ?? 0,
    voice: json['voice'] as String?,
  );

  static MidiClipMode _mode(Object? name) {
    for (final m in MidiClipMode.values) {
      if (m.name == name) return m;
    }
    return MidiClipMode.chain;
  }

  static Map<String, Object?> _map(Object? json) =>
      (json as Map).cast<String, Object?>();

  static List<Object?> _list(Object? json) =>
      (json as List?)?.cast<Object?>() ?? const [];
}
