import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/library/clip_library.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_mode.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/smf/smf_reader.dart';
import 'package:phi/domain/midi/smf/smf_writer.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';

void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  ClipDocument documentAt(ProjectRegistry registry, String dotted) =>
      ClipDocument.fromJson(
        (registry.entityAt(addr(dotted))!.payload! as Map).cast(),
      );

  MidiClip threeNoteClip() => MidiClip(
    bars: 2,
    beatsPerBar: 4,
    notes: const [
      MidiNote(pitch: 60, start: 0, duration: 0.5, velocity: 0.7),
      MidiNote(pitch: 64, start: 1, duration: 0.5, velocity: 0.6),
      MidiNote(pitch: 67, start: 2, duration: 1, velocity: 0.8),
    ],
  );

  late ProjectRegistry registry;
  late ClipLibrary library;

  setUp(() {
    registry = ProjectRegistry();
    library = ClipLibrary(registry);
  });

  tearDown(() => registry.dispose());

  group('newClip', () {
    test('creates an empty, looping clip at a slugged top-level address', () {
      final command = library.newClip(name: 'Fresh Idea');
      expect(command.address, addr('clip.fresh_idea'));

      command.apply();
      final document = documentAt(registry, 'clip.fresh_idea');
      expect(document.source.notes, isEmpty);
      expect(document.source.bars, ClipLibrary.defaultBars);
      expect(document.source.beatsPerBar, ClipLibrary.defaultBeatsPerBar);
      expect(document.mode, MidiClipMode.chain);
      expect(document.chain, isEmpty);
      // Loop is on by default for a fresh clip (design §7 decision 4).
      expect(document.loop, isTrue);
    });

    test('places the clip under a selected group', () {
      final command = library.newClip(group: addr('clip.drums'), name: 'kick');
      expect(command.address, addr('clip.drums.kick'));
      command.apply();
      expect(registry.entityAt(addr('clip.drums.kick')), isNotNull);
    });

    test('suffixes the leaf to stay unique among siblings', () {
      library.newClip(name: 'idea').apply();
      final second = library.newClip(name: 'idea');
      expect(second.address, addr('clip.idea_2'));
      second.apply();
      final third = library.newClip(name: 'idea');
      expect(third.address, addr('clip.idea_3'));
    });

    test('rejects a group of the wrong kind', () {
      expect(
        () => library.newClip(group: addr('mix.drums')),
        throwsArgumentError,
      );
    });

    test('the command round-trips through undo', () {
      final command = library.newClip(name: 'idea');
      command.apply();
      expect(registry.contains(addr('clip.idea')), isTrue);
      command.revert();
      expect(registry.contains(addr('clip.idea')), isFalse);
    });
  });

  group('duplicate', () {
    test('copies the whole document to <name>_copy beside the original', () {
      registry.createEntity(
        addr('clip.phrase'),
        payload: ClipDocument(source: threeNoteClip()).toJson(),
      );

      final command = library.duplicate(addr('clip.phrase'));
      expect(command.address, addr('clip.phrase_copy'));
      command.apply();

      final copy = documentAt(registry, 'clip.phrase_copy');
      expect(copy.source.notes, hasLength(3));
      expect(copy.source.bars, 2);
      expect(copy.loop, isTrue);
    });

    test('duplicating inside a group keeps the copy beside its source', () {
      registry.createEntity(
        addr('clip.drums.fill'),
        payload: ClipDocument(source: threeNoteClip()).toJson(),
      );
      final command = library.duplicate(addr('clip.drums.fill'));
      expect(command.address, addr('clip.drums.fill_copy'));
    });

    test('suffixes when a _copy already exists', () {
      registry.createEntity(
        addr('clip.phrase'),
        payload: ClipDocument(source: threeNoteClip()).toJson(),
      );
      library.duplicate(addr('clip.phrase')).apply();
      final second = library.duplicate(addr('clip.phrase'));
      expect(second.address, addr('clip.phrase_copy_2'));
    });

    test('preserves the graph of a graph-mode clip', () {
      final source = threeNoteClip();
      final graph = MidiTransformGraph(source: source);
      final n0 = graph.addNode(
        const TransposeTransform(semitones: 12, label: 'a'),
      );
      final n1 = graph.addNode(
        const TransposeTransform(semitones: 12, label: 'b'),
      );
      graph.connect(TransformNodeId.source, n0.id);
      graph.connect(
        n0.id,
        n1.id,
        condition: StateMatchCondition(EntityAddress.parse('state.hot')),
      );
      registry.createEntity(
        addr('clip.branchy'),
        payload: ClipDocument(
          source: source,
          mode: MidiClipMode.graph,
          graph: graph,
        ).toJson(),
      );
      graph.dispose();

      library.duplicate(addr('clip.branchy')).apply();

      final copy = documentAt(registry, 'clip.branchy_copy');
      expect(copy.mode, MidiClipMode.graph);
      final copiedGraph = copy.graph!;
      addTearDown(copiedGraph.dispose);
      expect(copiedGraph.nodes, hasLength(2));
      expect(copiedGraph.edges, hasLength(2));

      // The guarded branch survived: closed guard fires only n0 (+12), open
      // fires n0 → n1 (+24).
      const closed = GraphEvalContext.empty();
      final open = GraphEvalContext(
        activeState: EntityAddress.parse('state.hot'),
      );
      final closedPitches = copiedGraph.evaluate(closed).map((n) => n.pitch);
      final openPitches = copiedGraph.evaluate(open).map((n) => n.pitch);
      expect(closedPitches, [72, 76, 79]);
      expect(openPitches, [84, 88, 91]);
    });

    test('throws when the source clip does not exist', () {
      expect(
        () => library.duplicate(addr('clip.missing')),
        throwsArgumentError,
      );
    });

    test('the command round-trips through undo', () {
      registry.createEntity(
        addr('clip.phrase'),
        payload: ClipDocument(source: threeNoteClip()).toJson(),
      );
      final command = library.duplicate(addr('clip.phrase'));
      command.apply();
      expect(registry.contains(addr('clip.phrase_copy')), isTrue);
      command.revert();
      expect(registry.contains(addr('clip.phrase_copy')), isFalse);
    });
  });

  group('importFromSmf', () {
    Uint8List smfBytes(MidiClip clip) => const SmfWriter().write(clip);

    test('imports SMF bytes as a new clip slugged from the filename', () {
      final command = library.importFromSmf(
        smfBytes(threeNoteClip()),
        fileName: 'My Cool Loop.mid',
      );
      expect(command.address, addr('clip.my_cool_loop'));
      command.apply();

      final document = documentAt(registry, 'clip.my_cool_loop');
      expect(document.source.notes, hasLength(3));
      // A fresh import loops by default, like a new clip.
      expect(document.loop, isTrue);
      expect(document.mode, MidiClipMode.chain);
      expect(document.chain, isEmpty);
    });

    test('lands in the selected group', () {
      final command = library.importFromSmf(
        smfBytes(threeNoteClip()),
        group: addr('clip.drums'),
        fileName: 'kick.mid',
      );
      expect(command.address, addr('clip.drums.kick'));
      command.apply();
      expect(registry.entityAt(addr('clip.drums.kick')), isNotNull);
    });

    test('strips a directory prefix and stays unique', () {
      library
          .importFromSmf(smfBytes(threeNoteClip()), fileName: 'loop.mid')
          .apply();
      final second = library.importFromSmf(
        smfBytes(threeNoteClip()),
        fileName: 'sets/loop.mid',
      );
      expect(second.address, addr('clip.loop_2'));
    });

    test('the command round-trips through undo', () {
      final command = library.importFromSmf(
        smfBytes(threeNoteClip()),
        fileName: 'loop.mid',
      );
      command.apply();
      expect(registry.contains(addr('clip.loop')), isTrue);
      command.revert();
      expect(registry.contains(addr('clip.loop')), isFalse);
    });
  });

  group('exportSelected', () {
    test('encodes the chain-transformed output, not the raw source', () {
      registry.createEntity(
        addr('clip.phrase'),
        payload: ClipDocument(
          source: threeNoteClip(),
          chain: const [TransposeTransform(semitones: 12, label: 'up')],
        ).toJson(),
      );

      final bytes = library.exportSelected(addr('clip.phrase'));
      final decoded = const SmfReader().read(bytes);

      final pitches = decoded.notes.map((n) => n.pitch).toList()..sort();
      // Every pitch is transposed up an octave — the interpretation, not the
      // 60/64/67 source.
      expect(pitches, [72, 76, 79]);
    });

    test('an inactive chip does not contribute to the export', () {
      registry.createEntity(
        addr('clip.phrase'),
        payload: ClipDocument(
          source: threeNoteClip(),
          chain: const [
            TransposeTransform(semitones: 12, label: 'off', active: false),
          ],
        ).toJson(),
      );
      final decoded = const SmfReader().read(
        library.exportSelected(addr('clip.phrase')),
      );
      final pitches = decoded.notes.map((n) => n.pitch).toList()..sort();
      expect(pitches, [60, 64, 67]);
    });

    test('encodes a graph-mode clips evaluated output', () {
      final source = threeNoteClip();
      final graph = MidiTransformGraph.linear(
        source: source,
        transforms: const [TransposeTransform(semitones: 12, label: 'up')],
      );
      registry.createEntity(
        addr('clip.branchy'),
        payload: ClipDocument(
          source: source,
          mode: MidiClipMode.graph,
          graph: graph,
        ).toJson(),
      );
      graph.dispose();

      final decoded = const SmfReader().read(
        library.exportSelected(addr('clip.branchy')),
      );
      final pitches = decoded.notes.map((n) => n.pitch).toList()..sort();
      expect(pitches, [72, 76, 79]);
    });

    test('names the track from the entity leaf', () {
      registry.createEntity(
        addr('clip.drums.snare'),
        payload: ClipDocument(source: threeNoteClip()).toJson(),
      );
      // Round-trips without error and produces a non-empty SMF stream.
      final bytes = library.exportSelected(addr('clip.drums.snare'));
      expect(bytes, isNotEmpty);
      expect(const SmfReader().read(bytes).notes, hasLength(3));
    });

    test('throws when the source clip does not exist', () {
      expect(
        () => library.exportSelected(addr('clip.missing')),
        throwsArgumentError,
      );
    });
  });
}
