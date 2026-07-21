import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_mode.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/domain/state_machine/store/state_transition_spec.dart';

/// `state.` entities in the [ProjectRegistry] — the issue-#240 done-when:
/// the seed migration, delete-impact on a state listing its inbound
/// transitions *and* MIDI-graph guard usages, and rename-refactor covering a
/// state document's references.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late ProjectRegistry registry;

  setUp(() => registry = ProjectRegistry());
  tearDown(() => registry.dispose());

  group('seed migration', () {
    test('a fresh project seeds state.intro → state.verse, as today', () {
      seedDefaultProject(registry);

      expect(registry.contains(introStateAddress), isTrue);
      expect(registry.contains(verseStateAddress), isTrue);

      final intro = StateDocument.fromJson(
        (registry.entityAt(introStateAddress)!.payload! as Map).cast(),
      );
      expect(intro.position, const Offset(160, 160));
      expect(intro.transitions.single.to, verseStateAddress);
      expect(intro.transitions.single.trigger.kind, 'manual');

      final verse = StateDocument.fromJson(
        (registry.entityAt(verseStateAddress)!.payload! as Map).cast(),
      );
      expect(verse.position, const Offset(400, 160));
      expect(verse.transitions, isEmpty);
    });

    test('the seeded transition feeds the back-reference index', () {
      seedDefaultProject(registry);
      expect(registry.referrersOf(verseStateAddress), {introStateAddress});
    });
  });

  group('delete-impact (issue #240 done-when)', () {
    test('removing a state lists its inbound transitions', () {
      seedDefaultProject(registry);
      final impact = registry.impactOfRemoving(verseStateAddress);
      expect(impact.referrers, contains(introStateAddress));
    });

    test('removing a state lists the MIDI-graph guards branching on it', () {
      seedDefaultProject(registry);

      // A clip whose graph guards a branch on `state.verse`, its guard
      // references declared as the publisher does in production.
      final source = MidiClip(
        bars: 1,
        notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
      );
      final graph = MidiTransformGraph(source: source);
      addTearDown(graph.dispose);
      final node = graph.addNode(
        const TransposeTransform(semitones: 12, label: 'branch'),
      );
      graph.connect(
        TransformNodeId.source,
        node.id,
        condition: StateMatchCondition(verseStateAddress),
      );
      final document = ClipDocument(
        source: source,
        mode: MidiClipMode.graph,
        graph: graph,
      );
      registry.createEntity(
        addr('clip.branchy'),
        payload: document.toJson(),
        references: document.guardStateReferences,
      );

      final impact = registry.impactOfRemoving(verseStateAddress);
      expect(
        impact.referrers,
        containsAll([introStateAddress, addr('clip.branchy')]),
      );
    });
  });

  group('rename = refactor', () {
    test('renaming a state remaps every referrer edge in the index', () {
      seedDefaultProject(registry);

      registry.move(verseStateAddress, addr('state.chorus'));

      expect(registry.referencesOf(introStateAddress), {addr('state.chorus')});
      expect(registry.referrersOf(addr('state.chorus')), {introStateAddress});
      expect(registry.referrersOf(verseStateAddress), isEmpty);
    });

    test('a StateDocument payload is rewritten through ReferenceSource — the '
        'registry-backed controller wiring #241 builds on', () {
      // Payload as the typed document (a ReferenceSource): the registry
      // rewrites the payload itself on a rename, transitions included.
      final intro = introStateDocument();
      registry.createEntity(
        introStateAddress,
        payload: intro,
        references: intro.references,
      );
      final verse = verseStateDocument();
      registry.createEntity(
        verseStateAddress,
        payload: verse.toJson(),
        references: verse.references,
      );

      registry.move(verseStateAddress, addr('state.chorus'));

      final rewritten =
          registry.entityAt(introStateAddress)!.payload! as StateDocument;
      expect(rewritten.transitions.single.to, addr('state.chorus'));
      expect(
        rewritten,
        introStateDocument().withReferenceUpdated(
          verseStateAddress,
          addr('state.chorus'),
        ),
      );
    });
  });

  group('the state codec is registered', () {
    test(
      'a state payload survives an encode/decode through the default codecs',
      () {
        seedDefaultProject(registry);
        final stored = (registry.entityAt(introStateAddress)!.payload! as Map)
            .cast<String, Object?>();
        final decoded = StateDocument.fromJson(stored);
        expect(decoded, introStateDocument());
        expect(
          decoded.transitions.single,
          StateTransitionSpec(to: verseStateAddress),
        );
      },
    );
  });
}
