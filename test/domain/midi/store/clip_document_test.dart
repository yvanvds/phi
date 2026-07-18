import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_mode.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/quantization_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';

void main() {
  MidiClip source() => MidiClip(
    name: 'phrase',
    bars: 2,
    beatsPerBar: 4,
    notes: const [
      MidiNote(pitch: 60, start: 0, duration: 0.5, velocity: 0.7),
      MidiNote(pitch: 64, start: 1, duration: 0.5, velocity: 0.6, channel: 1),
    ],
  );

  test('a chain-mode document round-trips source + transforms', () {
    final doc = ClipDocument(
      source: source(),
      chain: const [
        TransposeTransform(semitones: 3, label: 'up'),
        QuantizationTransform(gravity: 0.5, label: 'q', active: false),
      ],
    );

    final decoded = ClipDocument.fromJson(doc.toJson());

    expect(decoded.mode, MidiClipMode.chain);
    expect(decoded.source.name, 'phrase');
    expect(decoded.source.bars, 2);
    expect(decoded.source.notes, hasLength(2));
    expect(decoded.source.notes[1].channel, 1);
    expect(decoded.chain, hasLength(2));
    expect((decoded.chain[0] as TransposeTransform).semitones, 3);
    expect(decoded.chain[1].active, isFalse);
    expect(decoded.graph, isNull);
  });

  test('a graph-mode document round-trips its graph', () {
    final clip = source();
    final graph = MidiTransformGraph.linear(
      source: clip,
      transforms: const [TransposeTransform(semitones: 12, label: 'up')],
    );
    addTearDown(graph.dispose);
    final doc = ClipDocument(
      source: clip,
      mode: MidiClipMode.graph,
      graph: graph,
    );

    final decoded = ClipDocument.fromJson(doc.toJson());
    addTearDown(() => decoded.graph?.dispose());

    expect(decoded.mode, MidiClipMode.graph);
    expect(decoded.graph, isNotNull);
    expect(decoded.graph!.nodes, hasLength(1));
    expect(
      decoded.graph!.evaluate().map((n) => n.pitch),
      graph.evaluate().map((n) => n.pitch),
    );
  });

  test('migrates a v1 payload (bare clip) forward', () {
    final v1 = ClipDocument.clipToJson(source());
    // No `source` key, no chain — the v1 shape.
    expect(v1.containsKey('source'), isFalse);

    final decoded = ClipDocument.fromJson(v1);
    expect(decoded.source.name, 'phrase');
    expect(decoded.source.notes, hasLength(2));
    expect(decoded.mode, MidiClipMode.chain);
    expect(decoded.chain, isEmpty);
    expect(decoded.graph, isNull);
  });
}
