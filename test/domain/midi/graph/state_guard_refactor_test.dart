import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_mode.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';

/// Guard rename-following (issue #240 done-when): a [StateMatchCondition]
/// carries a `state.` entity address, the graph exposes / repoints its guard
/// addresses, and the rewrite survives the persistence round-trip — the
/// domain machinery the registry-backed rename wiring (issue #241) drives.
void main() {
  final verse = EntityAddress.parse('state.verse');
  final chorus = EntityAddress.parse('state.chorus');

  MidiClip clip() => MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  );

  MidiTransformGraph guarded(MidiClip source) {
    final graph = MidiTransformGraph(source: source);
    final node = graph.addNode(
      const TransposeTransform(semitones: 12, label: 'branch'),
    );
    graph.connect(
      TransformNodeId.source,
      node.id,
      condition: StateMatchCondition(verse),
    );
    return graph;
  }

  test('guardStateAddresses collects every state guard, de-duplicated', () {
    final graph = guarded(clip());
    addTearDown(graph.dispose);
    final second = graph.addNode(
      const TransposeTransform(semitones: 5, label: 'b2'),
    );
    graph.connect(
      TransformNodeId.source,
      second.id,
      condition: StateMatchCondition(verse),
    );

    expect(graph.guardStateAddresses, {verse});
  });

  test('an unguarded graph reports no state addresses', () {
    final graph = MidiTransformGraph(source: clip());
    addTearDown(graph.dispose);
    expect(graph.guardStateAddresses, isEmpty);
  });

  test('repointGuardState rewrites the guard and evaluation follows the new '
      'address', () {
    final graph = guarded(clip());
    addTearDown(graph.dispose);

    // Before the rename: the guard opens under `state.verse`.
    expect(
      graph.evaluate(GraphEvalContext(activeState: verse)).single.pitch,
      72,
    );

    var notified = 0;
    graph.addListener(() => notified++);
    expect(graph.repointGuardState(verse, chorus), isTrue);
    expect(notified, 1);

    // After: the old address no longer opens the branch, the new one does.
    expect(graph.guardStateAddresses, {chorus});
    expect(
      graph.evaluate(GraphEvalContext(activeState: verse)).single.pitch,
      60,
    );
    expect(
      graph.evaluate(GraphEvalContext(activeState: chorus)).single.pitch,
      72,
    );
  });

  test('repointGuardState is a silent no-op when nothing matches', () {
    final graph = guarded(clip());
    addTearDown(graph.dispose);
    var notified = 0;
    graph.addListener(() => notified++);

    expect(graph.repointGuardState(chorus, verse), isFalse);
    expect(notified, 0);
  });

  test('the repointed guard survives the persistence round-trip', () {
    final source = clip();
    final graph = guarded(source);
    addTearDown(graph.dispose);
    graph.repointGuardState(verse, chorus);

    final document = ClipDocument(
      source: source,
      mode: MidiClipMode.graph,
      graph: graph,
    );
    final reloaded = ClipDocument.fromJson(document.toJson());
    addTearDown(() => reloaded.graph?.dispose());

    expect(reloaded.guardStateReferences, {chorus});
    expect(
      reloaded.graph!
          .evaluate(GraphEvalContext(activeState: chorus))
          .single
          .pitch,
      72,
    );
  });

  test('ClipDocument.guardStateReferences reads the graph, chain or not', () {
    final source = clip();
    expect(ClipDocument(source: source).guardStateReferences, isEmpty);

    final graph = guarded(source);
    addTearDown(graph.dispose);
    // A dormant graph on a chain-mode clip still counts — its guards would
    // break too.
    final document = ClipDocument(
      source: source,
      mode: MidiClipMode.chain,
      graph: graph,
    );
    expect(document.guardStateReferences, {verse});
  });
}
