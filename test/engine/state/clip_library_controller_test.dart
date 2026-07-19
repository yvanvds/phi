import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/engine/state/clip_library_controller.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';

EntityAddress _addr(String dotted) => EntityAddress.parse(dotted);

Map<String, Object?> _clipPayload({double pitch = 60, bool loop = true}) =>
    ClipDocument(
      source: MidiClip(
        bars: 1,
        notes: [MidiNote(pitch: pitch, start: 0, duration: 1, velocity: 1)],
      ),
      loop: loop,
    ).toJson();

MidiTransformChain _seedChain() => MidiTransformChain(
  source: MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
);

void main() {
  group('ClipLibraryController — tree + commands', () {
    late ProjectRegistry registry;
    late FakeMidiGateway gateway;
    late EngineMidiController sessions;
    late List<ProjectCommand> recorded;
    late ClipLibraryController controller;

    setUp(() {
      registry = ProjectRegistry();
      gateway = FakeMidiGateway();
      sessions = EngineMidiController(chain: _seedChain(), gateway: gateway);
      recorded = [];
      controller = ClipLibraryController(
        registry: registry,
        sessions: sessions,
        recordCommand: recorded.add,
      );
    });

    tearDown(() async {
      controller.dispose();
      sessions.dispose();
      registry.dispose();
      await gateway.dispose();
    });

    void seedTree() {
      registry.createEntity(_addr('clip.a'), payload: _clipPayload());
      registry.createEntity(_addr('clip.drums.kick'), payload: _clipPayload());
      registry.createEntity(_addr('clip.drums.snare'), payload: _clipPayload());
      registry.createEntity(_addr('clip.b'), payload: _clipPayload());
    }

    test('renders the clip.* namespace as an ordered tree with groups', () {
      seedTree();

      final tree = controller.tree;
      expect(tree.map((n) => n.name), ['a', 'drums', 'b']);

      final drums = tree[1];
      expect(drums.isGroup, isTrue);
      expect(drums.children.map((n) => n.name), ['kick', 'snare']);
      // Leaves are not groups.
      expect(tree.first.isGroup, isFalse);
    });

    test('the tree re-renders (notifies) when the registry mutates', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      registry.createEntity(_addr('clip.a'), payload: _clipPayload());

      expect(notifications, greaterThan(0));
      expect(controller.tree, hasLength(1));
    });

    test('select opens the clip as the edited session', () {
      registry.createEntity(_addr('clip.a'), payload: _clipPayload(pitch: 64));

      controller.select(_addr('clip.a'));

      expect(controller.editedAddress, _addr('clip.a'));
      expect(sessions.editedSession.address, _addr('clip.a'));
      expect(sessions.editedSession.chain.source.notes.single.pitch, 64);
    });

    test('newClip creates + records + opens the fresh clip', () {
      final created = controller.newClip();

      expect(created, isNotNull);
      expect(registry.entityAt(created!), isNotNull);
      expect(controller.editedAddress, created);
      expect(recorded, hasLength(1));
    });

    test('newGroup creates a group folder + records', () {
      final group = controller.newGroup();

      expect(registry.groupAt(group), isNotNull);
      expect(recorded, hasLength(1));
    });

    test('duplicate copies the document to <name>_copy beside it', () {
      registry.createEntity(_addr('clip.a'), payload: _clipPayload());

      final copy = controller.duplicate(_addr('clip.a'));

      expect(copy, _addr('clip.a_copy'));
      expect(registry.entityAt(copy!), isNotNull);
      expect(controller.editedAddress, copy);
    });

    test('rename moves the entity to the slug of the new name (refactor)', () {
      registry.createEntity(_addr('clip.a'), payload: _clipPayload());

      controller.rename(_addr('clip.a'), 'lead line');

      expect(registry.contains(_addr('clip.a')), isFalse);
      expect(registry.contains(_addr('clip.lead_line')), isTrue);
      expect(recorded, hasLength(1));
    });

    test('delete removes the node + records', () {
      registry.createEntity(_addr('clip.a'), payload: _clipPayload());

      controller.delete(_addr('clip.a'));

      expect(registry.contains(_addr('clip.a')), isFalse);
      expect(recorded, hasLength(1));
    });

    test('regroup re-parents a clip into a group (drag-to-group)', () {
      registry.createEntity(_addr('clip.a'), payload: _clipPayload());
      registry.createGroup(_addr('clip.drums'));

      controller.regroup(_addr('clip.a'), _addr('clip.drums'));

      expect(registry.contains(_addr('clip.a')), isFalse);
      expect(registry.contains(_addr('clip.drums.a')), isTrue);
    });

    test('regroup with a null target un-groups back to the top level', () {
      registry.createEntity(_addr('clip.drums.kick'), payload: _clipPayload());

      controller.regroup(_addr('clip.drums.kick'), null);

      expect(registry.contains(_addr('clip.kick')), isTrue);
    });

    test('reorderBefore reorders within a section', () {
      seedTree();
      // Move `b` to sit before `a` at the top level.
      controller.reorderBefore(_addr('clip.b'), _addr('clip.a'));

      expect(controller.tree.map((n) => n.name), ['b', 'a', 'drums']);
      expect(recorded.last.toJson()['type'], 'reorder_child');
    });
  });

  group('ClipLibraryController — play state', () {
    test('playClip opens + plays without changing the edited session', () {
      fakeAsync((async) {
        final registry = ProjectRegistry();
        final gateway = FakeMidiGateway();
        final sessions = EngineMidiController(
          chain: _seedChain(),
          gateway: gateway,
        );
        final controller = ClipLibraryController(
          registry: registry,
          sessions: sessions,
        );
        registry.createEntity(_addr('clip.a'), payload: _clipPayload());

        // The edited session is still the boot session (null address).
        expect(controller.editedAddress, isNull);

        controller.playClip(_addr('clip.a'));
        async.elapse(const Duration(milliseconds: 20));

        expect(controller.isPlaying(_addr('clip.a')), isTrue);
        // Playing a row did NOT swap the editor to it.
        expect(controller.editedAddress, isNull);

        controller.stopClip(_addr('clip.a'));
        expect(controller.isPlaying(_addr('clip.a')), isFalse);

        controller.dispose();
        sessions.dispose();
        registry.dispose();
      });
    });

    test(
      'playGroup plays every clip beneath a group; stopGroup halts them',
      () {
        fakeAsync((async) {
          final registry = ProjectRegistry();
          final gateway = FakeMidiGateway();
          final sessions = EngineMidiController(
            chain: _seedChain(),
            gateway: gateway,
          );
          final controller = ClipLibraryController(
            registry: registry,
            sessions: sessions,
          );
          registry.createEntity(
            _addr('clip.drums.kick'),
            payload: _clipPayload(pitch: 36),
          );
          registry.createEntity(
            _addr('clip.drums.snare'),
            payload: _clipPayload(pitch: 38),
          );

          controller.playGroup(_addr('clip.drums'));
          async.elapse(const Duration(milliseconds: 20));

          expect(controller.isGroupPlaying(_addr('clip.drums')), isTrue);
          expect(controller.isPlaying(_addr('clip.drums.kick')), isTrue);
          expect(controller.isPlaying(_addr('clip.drums.snare')), isTrue);

          controller.stopGroup(_addr('clip.drums'));
          expect(controller.isGroupPlaying(_addr('clip.drums')), isFalse);

          controller.dispose();
          sessions.dispose();
          registry.dispose();
        });
      },
    );

    test('toggleLoop flips the open session loop flag', () {
      fakeAsync((async) {
        final registry = ProjectRegistry();
        final gateway = FakeMidiGateway();
        final sessions = EngineMidiController(
          chain: _seedChain(),
          gateway: gateway,
        );
        final controller = ClipLibraryController(
          registry: registry,
          sessions: sessions,
        );
        registry.createEntity(
          _addr('clip.a'),
          payload: _clipPayload(loop: true),
        );

        expect(controller.loopOf(_addr('clip.a')), isTrue);
        controller.toggleLoop(_addr('clip.a'));
        expect(controller.loopOf(_addr('clip.a')), isFalse);

        controller.dispose();
        sessions.dispose();
        registry.dispose();
      });
    });
  });
}
