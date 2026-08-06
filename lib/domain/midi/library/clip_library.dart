import 'dart:convert';
import 'dart:typed_data';

import '../../project/commands/create_entity_command.dart';
import '../../project/entity_address.dart';
import '../../project/name_slug.dart';
import '../../project/project_registry.dart';
import '../../project/registry_kinds.dart';
import '../graph/graph_eval_context.dart';
import '../midi_clip.dart';
import '../midi_clip_mode.dart';
import '../midi_note.dart';
import '../smf/smf_reader.dart';
import '../smf/smf_writer.dart';
import '../store/clip_document.dart';
import '../store/midi_transform_codec.dart';

/// The `clip.` library commands (design `docs/design/midi-clips.md` §3) — the
/// pure-domain half of the MIDI-clip library (epic issue #185).
///
/// Every clip is a registry entity carrying a [ClipDocument] payload; the
/// library is the set of operations that *mint* or *read* those entities:
///
/// - [newClip] — an empty [ClipDocument] (default meter, **loop on**) at a
///   chosen address.
/// - [duplicate] — the whole document copied verbatim to `<name>_copy` beside
///   the original (graph and all — the copy is byte-for-byte, so a graph-mode
///   clip keeps its branches).
/// - [importFromSmf] — SMF bytes → [SmfReader] → a [ClipDocument] → a new entity
///   in the selected group, its address slugged from the filename.
/// - [exportSelected] — the selected clip's *transformed* output (its chain or
///   graph interpretation) through the existing [SmfWriter], now addressed by
///   entity rather than by the single live clip.
///
/// The three creating operations return an ordinary [CreateEntityCommand] — the
/// journaled command layer, so each round-trips through save/load *and* undo
/// (delete/rename need no new command; the registry already carries them). The
/// caller applies and records the command (through the surface's `UndoScope` /
/// `ProjectController`); the library itself never mutates the registry, keeping
/// it a pure command factory. [exportSelected] is a read: it returns the encoded
/// bytes and touches nothing.
class ClipLibrary {
  /// Binds the library to [registry]. [transformCodec] (de)serialises the chain
  /// / graph transforms — pass one carrying a `CustomTransformRegistry` and/or
  /// the project's time domains so imported/exported live-coded transforms and
  /// domain subscriptions re-link. [_reader] / [_writer] are the SMF codec, faked
  /// in tests but stateless `const` values in production.
  ClipLibrary(
    this.registry, {
    this.transformCodec = const MidiTransformCodec(),
    this._reader = const SmfReader(),
    this._writer = const SmfWriter(),
  });

  /// The registry the minted commands target and the exports read from.
  final ProjectRegistry registry;

  /// The transform codec used to encode a fresh document and decode one for
  /// export (a duplicate copies the stored map verbatim and needs none).
  final MidiTransformCodec transformCodec;

  final SmfReader _reader;
  final SmfWriter _writer;

  /// The default length of a fresh clip, in bars — the length authority (design
  /// §5) edits this later; the library only seeds it.
  static const int defaultBars = 4;

  /// The default meter of a fresh clip, in quarter-note beats per bar (4/4).
  static const int defaultBeatsPerBar = 4;

  /// Builds a command that creates an **empty** clip (default meter, loop on)
  /// under [group] (or top-level when null), named from [name] (slugged, made
  /// unique among its siblings).
  CreateEntityCommand newClip({EntityAddress? group, String name = 'clip'}) {
    final document = ClipDocument(
      source: MidiClip(
        notes: const [],
        bars: defaultBars,
        beatsPerBar: defaultBeatsPerBar,
      ),
      // ClipDocument.loop defaults to on — the fresh-clip rule (design §7.4).
    );
    return CreateEntityCommand(
      registry,
      _freshAddress(
        group: group,
        desired: NameSlug.of(name, fallback: 'clip'),
      ),
      payload: document.toJson(transformCodec: transformCodec),
    );
  }

  /// Builds a command that copies the clip at [source] — its whole document,
  /// source and interpretation alike — to `<name>_copy` beside it (made unique).
  ///
  /// The stored payload is copied **verbatim** (a deep JSON clone), so a
  /// graph-mode clip's branches survive without a decode/encode round-trip that
  /// could downgrade a live-coded transform. Throws an [ArgumentError] when no
  /// clip entity sits at [source].
  CreateEntityCommand duplicate(EntityAddress source) {
    final entity = registry.entityAt(source);
    if (entity == null) {
      throw ArgumentError.value(
        source.format(),
        'source',
        'no clip entity to duplicate',
      );
    }
    return CreateEntityCommand(
      registry,
      _freshAddress(group: source.parent, desired: '${source.name}_copy'),
      payload: _clonePayload(entity.payload),
    );
  }

  /// Builds a command that imports the SMF [bytes] as a **new** clip entity
  /// under [group] (or top-level when null), its address slugged from
  /// [fileName] (extension stripped, made unique) — dropping a `.mid` into the
  /// library never overwrites the open clip (design §3).
  ///
  /// Throws an [SmfFormatException] on a malformed stream (from [SmfReader]).
  CreateEntityCommand importFromSmf(
    Uint8List bytes, {
    EntityAddress? group,
    required String fileName,
  }) {
    final document = ClipDocument(source: _reader.read(bytes));
    return CreateEntityCommand(
      registry,
      _freshAddress(
        group: group,
        desired: NameSlug.of(_stem(fileName), fallback: 'clip'),
      ),
      payload: document.toJson(transformCodec: transformCodec),
    );
  }

  /// Encodes the clip at [source] to SMF bytes — its **transformed** output
  /// (the chain's, or the graph's `evaluate` for [context]), not the raw source,
  /// since a clip is "interpreted, not played" (matching the live export flow,
  /// now addressed by entity).
  ///
  /// Throws an [ArgumentError] when no clip entity sits at [source].
  Uint8List exportSelected(
    EntityAddress source, {
    GraphEvalContext context = const GraphEvalContext.empty(),
  }) {
    final entity = registry.entityAt(source);
    if (entity == null) {
      throw ArgumentError.value(
        source.format(),
        'source',
        'no clip entity to export',
      );
    }
    final document = _documentOf(entity.payload);
    final rendered = MidiClip(
      notes: _outputOf(document, context),
      bars: document.source.bars,
      beatsPerBar: document.source.beatsPerBar,
    );
    return _writer.write(rendered, name: source.name);
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// A `clip.` address for [desired] under [group] (top-level when null), made
  /// unique among its siblings by suffixing `_2`, `_3`, … — the tree-uniqueness
  /// [NameSlug] deliberately leaves to the caller.
  EntityAddress _freshAddress({
    required EntityAddress? group,
    required String desired,
  }) {
    if (group != null && group.kind != RegistryKinds.clip) {
      throw ArgumentError.value(
        group.format(),
        'group',
        'a clip must live under a "${RegistryKinds.clip}" group',
      );
    }
    EntityAddress at(String leaf) => group == null
        ? EntityAddress(kind: RegistryKinds.clip, segments: [leaf])
        : group.child(leaf);
    var leaf = desired;
    var attempt = 2;
    while (registry.contains(at(leaf))) {
      leaf = NameSlug.of('${desired}_$attempt', fallback: 'clip');
      attempt++;
    }
    return at(leaf);
  }

  /// A deep clone of a stored clip [payload] for a duplicate. The registry keeps
  /// clip payloads map-native (the journal contract), so a JSON round-trip is a
  /// full deep copy; a live [ClipDocument] is flattened through its codec.
  Object _clonePayload(Object? payload) {
    if (payload is ClipDocument) {
      return payload.toJson(transformCodec: transformCodec);
    }
    if (payload is Map) {
      return (jsonDecode(jsonEncode(payload)) as Map).cast<String, Object?>();
    }
    throw ArgumentError.value(
      payload,
      'payload',
      'clip entity has no document payload to duplicate',
    );
  }

  /// The [ClipDocument] behind a stored clip [payload] (map-native or a live
  /// object), for export.
  ClipDocument _documentOf(Object? payload) {
    if (payload is ClipDocument) return payload;
    if (payload is Map) {
      return ClipDocument.fromJson(
        payload.cast<String, Object?>(),
        transformCodec: transformCodec,
      );
    }
    throw ArgumentError.value(
      payload,
      'payload',
      'clip entity has no document payload to export',
    );
  }

  /// The document's transformed notes — the graph's `evaluate` in graph mode,
  /// else the active chain applied in order (mirroring `MidiTransformChain.output`).
  List<MidiNote> _outputOf(ClipDocument document, GraphEvalContext context) {
    final graph = document.graph;
    if (document.mode == MidiClipMode.graph && graph != null) {
      return graph.evaluate(context);
    }
    var notes = List<MidiNote>.of(document.source.notes);
    for (final transform in document.chain) {
      if (transform.active) notes = transform.apply(notes);
    }
    return notes;
  }

  /// The filename [fileName] with any directory prefix and final extension
  /// stripped — `sets/drum_loop.mid` → `drum_loop`. A leading-dot name keeps its
  /// stem (`.mid` → `mid`); [NameSlug] handles the empty case.
  static String _stem(String fileName) {
    final base = fileName.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
