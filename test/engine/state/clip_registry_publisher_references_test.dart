import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/engine/state/clip_registry_publisher.dart';
import 'package:phi/engine/state/midi_graph_controller.dart';

/// The publisher's reference sync (issue #240): whenever the published clip
/// document changes, its guarded `state.` addresses are re-declared into the
/// registry's back-reference index — so delete-impact on a state lists the
/// clips branching on it, mirroring `updateVoice` (design §4).
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late ProjectRegistry registry;
  late MidiTransformChain chain;
  late ClipEditor editor;
  late MidiGraphController graphController;
  late ClipRegistryPublisher publisher;
  late List<ProjectCommand> recorded;

  setUp(() {
    registry = ProjectRegistry();
    chain = MidiTransformChain(
      source: MidiClip(
        bars: 1,
        notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
      ),
    );
    editor = ClipEditor(chain.source);
    graphController = MidiGraphController.seededFrom(chain);
    recorded = <ProjectCommand>[];
    registry.createEntity(addr('clip.phrase_a'));
    registry.createEntity(addr('state.verse'));
    publisher = ClipRegistryPublisher()
      ..bind(
        registry: registry,
        chain: chain,
        editor: editor,
        graphController: graphController,
        clipAddress: addr('clip.phrase_a'),
        recordCommand: recorded.add,
      );
  });

  tearDown(() {
    publisher.unbind();
    graphController.dispose();
    editor.dispose();
    chain.dispose();
    registry.dispose();
  });

  test('authoring a state guard declares the clip → state reference', () {
    final node = graphController.graph.addNode(
      const TransposeTransform(semitones: 12, label: 'branch'),
    );
    graphController.graph.connect(
      TransformNodeId.source,
      node.id,
      condition: StateMatchCondition(addr('state.verse')),
    );

    expect(registry.referencesOf(addr('clip.phrase_a')), {addr('state.verse')});
    expect(registry.referrersOf(addr('state.verse')), {addr('clip.phrase_a')});
    // The payload change itself was journaled as usual.
    expect(recorded, isNotEmpty);
  });

  test('delete-impact on the guarded state lists the clip', () {
    final node = graphController.graph.addNode(
      const TransposeTransform(semitones: 12, label: 'branch'),
    );
    graphController.graph.connect(
      TransformNodeId.source,
      node.id,
      condition: StateMatchCondition(addr('state.verse')),
    );

    final impact = registry.impactOfRemoving(addr('state.verse'));
    expect(impact.referrers, [addr('clip.phrase_a')]);
  });

  test('removing the guard clears the declared reference', () {
    final node = graphController.graph.addNode(
      const TransposeTransform(semitones: 12, label: 'branch'),
    );
    graphController.graph.connect(
      TransformNodeId.source,
      node.id,
      condition: StateMatchCondition(addr('state.verse')),
    );
    expect(registry.referencesOf(addr('clip.phrase_a')), isNotEmpty);

    graphController.graph.disconnect(TransformNodeId.source, node.id);

    expect(registry.referencesOf(addr('clip.phrase_a')), isEmpty);
    expect(registry.referrersOf(addr('state.verse')), isEmpty);
  });

  test('a guard-free edit leaves the reference set untouched', () {
    // A plain graph edit with no state guard never calls setReferences with
    // anything new — the declared set stays empty throughout.
    final node = graphController.graph.addNode(
      const TransposeTransform(semitones: 5, label: '+5'),
    );
    graphController.graph.connect(TransformNodeId.source, node.id);

    expect(registry.referencesOf(addr('clip.phrase_a')), isEmpty);
  });
}
