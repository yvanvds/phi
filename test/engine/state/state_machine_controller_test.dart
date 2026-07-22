import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/move_entity_command.dart';
import 'package:phi/domain/project/commands/remove_entity_command.dart';
import 'package:phi/domain/project/commands/update_entity_payload_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/state_machine/state_transition.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/state/state_machine_controller.dart';

/// The registry-backed [StateMachineController] (issue #241): the canvas
/// view derives from `state.` entities, structural edits are journaled
/// commands, live/armed stay performance state keyed by address, and a
/// rename refactors sibling payloads while keeping the arm and the live
/// capsule.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late ProjectRegistry registry;
  late StateMachineController controller;
  late List<ProjectCommand> recorded;

  /// Seed the default `intro → verse` pair exactly as production does —
  /// map-native payloads with declared references.
  void seedStates(ProjectRegistry target) {
    final intro = introStateDocument();
    target.createEntity(
      introStateAddress,
      payload: intro.toJson(),
      references: intro.references,
    );
    final verse = verseStateDocument();
    target.createEntity(
      verseStateAddress,
      payload: verse.toJson(),
      references: verse.references,
    );
  }

  StateDocument docAt(EntityAddress address) {
    final payload = registry.entityAt(address)!.payload;
    return payload is StateDocument
        ? payload
        : StateDocument.fromJson((payload! as Map).cast());
  }

  StateTransition ref(EntityAddress source, EntityAddress target) =>
      StateTransition(source: source, target: target);

  setUp(() {
    registry = ProjectRegistry();
    seedStates(registry);
    recorded = [];
    controller = StateMachineController(
      registry: registry,
      recordCommand: recorded.add,
    );
  });

  tearDown(() {
    controller.dispose();
    registry.dispose();
  });

  group('registry-backed view', () {
    test('renders the seeded intro → verse pair from the registry', () {
      expect(controller.states, hasLength(2));
      expect(controller.states.first.address, introStateAddress);
      expect(controller.states.first.name, 'intro');
      expect(controller.states.first.position, const Offset(160, 160));
      expect(controller.states.last.address, verseStateAddress);
      expect(controller.states.last.position, const Offset(400, 160));

      final transition = controller.transitions.single;
      expect(transition.source, introStateAddress);
      expect(transition.target, verseStateAddress);
      expect(transition.armed, isFalse);
      expect(transition.fireOn, 'manual');
    });

    test('normalises map-native payloads to typed documents on bind', () {
      // The seed stored maps; the controller replaced them with the typed
      // ReferenceSource so rename-refactor can rewrite them (issue #240's
      // registry test is the contract this builds on).
      expect(
        registry.entityAt(introStateAddress)!.payload,
        isA<StateDocument>(),
      );
      expect(
        registry.entityAt(verseStateAddress)!.payload,
        isA<StateDocument>(),
      );
      // Normalisation is a view concern — nothing journals.
      expect(recorded, isEmpty);
    });

    test('seeds the live state from the first entity in registry order', () {
      expect(controller.activeStateAddress, introStateAddress);
    });

    test('a bare controller owns an empty scratch registry', () {
      final bare = StateMachineController();
      addTearDown(bare.dispose);
      expect(bare.states, isEmpty);
      expect(bare.activeStateAddress, isNull);

      final added = bare.addState(name: 'solo', position: const Offset(3, 5));
      expect(added, addr('state.solo'));
      expect(bare.states.single.position, const Offset(0, 0));
      expect(bare.activeStateAddress, added);
    });
  });

  group('addState', () {
    test('creates a journaled entity at the snapped position', () {
      final added = controller.addState(
        name: 'Break Down',
        position: const Offset(53, 71),
      );

      expect(added, addr('state.break_down'));
      // 53 → 48, 71 → 64 (nearest multiples of 16).
      expect(docAt(added).position, const Offset(48, 64));
      expect(controller.states, hasLength(3));
      expect(recorded.whereType<CreateEntityCommand>(), hasLength(1));
    });

    test('uniques the slug among siblings', () {
      final second = controller.addState(name: 'intro', position: Offset.zero);
      expect(second, addr('state.intro_2'));
    });
  });

  group('node moves', () {
    test('moveState stays transient and snaps to the 16px grid', () {
      controller.moveState(introStateAddress, const Offset(3, 11));

      // 163 → 160, 171 → 176 — the node view moved…
      expect(
        controller.nodeAt(introStateAddress)!.position,
        const Offset(160, 176),
      );
      // …but nothing journaled and the payload is untouched until endMove.
      expect(recorded, isEmpty);
      expect(docAt(introStateAddress).position, const Offset(160, 160));
    });

    test('endMove commits one journaled position command', () {
      controller.moveState(introStateAddress, const Offset(30, 0));
      controller.moveState(introStateAddress, const Offset(34, 0));
      controller.endMove(introStateAddress);

      expect(docAt(introStateAddress).position, const Offset(224, 160));
      final updates = recorded.whereType<UpdateEntityPayloadCommand>();
      expect(updates, hasLength(1));

      // Undo restores the old position exactly.
      updates.single.revert();
      expect(docAt(introStateAddress).position, const Offset(160, 160));
    });

    test('endMove without a net move journals nothing', () {
      controller.moveState(introStateAddress, const Offset(2, 2)); // snaps back
      controller.endMove(introStateAddress);
      expect(recorded, isEmpty);
    });

    test('moveState on a missing address is a no-op', () {
      controller.moveState(addr('state.ghost'), const Offset(16, 16));
      controller.endMove(addr('state.ghost'));
      expect(recorded, isEmpty);
    });
  });

  group('connect / disconnect', () {
    test('connect appends a manual transition spec to the source payload', () {
      expect(controller.connect(verseStateAddress, introStateAddress), isTrue);

      expect(docAt(verseStateAddress).transitions.single.to, introStateAddress);
      expect(
        docAt(verseStateAddress).transitions.single.trigger.kind,
        'manual',
      );
      expect(controller.transitions, hasLength(2));
      expect(recorded.whereType<UpdateEntityPayloadCommand>(), hasLength(1));
    });

    test('connect rejects self-loops, duplicates and unknown endpoints', () {
      expect(controller.connect(introStateAddress, introStateAddress), isFalse);
      expect(controller.connect(introStateAddress, verseStateAddress), isFalse);
      expect(
        controller.connect(introStateAddress, addr('state.nope')),
        isFalse,
      );
      expect(
        controller.connect(addr('state.nope'), introStateAddress),
        isFalse,
      );
      expect(recorded, isEmpty);
    });

    test('disconnect drops the spec from the source payload', () {
      controller.disconnect(introStateAddress, verseStateAddress);
      expect(docAt(introStateAddress).transitions, isEmpty);
      expect(controller.transitions, isEmpty);
    });
  });

  group('arm + fire (performance state)', () {
    test('toggleArmed flips the rendered arm without journaling', () {
      controller.toggleArmed(ref(introStateAddress, verseStateAddress));
      expect(controller.transitions.single.armed, isTrue);

      controller.toggleArmed(ref(introStateAddress, verseStateAddress));
      expect(controller.transitions.single.armed, isFalse);
      expect(recorded, isEmpty);
    });

    test('toggleArmed on an unknown transition is a no-op', () {
      controller.toggleArmed(ref(verseStateAddress, introStateAddress));
      expect(controller.transitions.single.armed, isFalse);
    });

    test('fire flips the live state to the target and clears every arm', () {
      controller.toggleArmed(ref(introStateAddress, verseStateAddress));
      controller.fire(ref(introStateAddress, verseStateAddress));

      expect(controller.activeStateAddress, verseStateAddress);
      expect(controller.transitions.single.armed, isFalse);
      expect(recorded, isEmpty);
    });

    test('setLive moves the live capsule; unknown addresses are ignored', () {
      controller.setLive(verseStateAddress);
      expect(controller.activeStateAddress, verseStateAddress);

      controller.setLive(addr('state.ghost'));
      expect(controller.activeStateAddress, verseStateAddress);
    });
  });

  group('rename = refactor', () {
    test('rewrites sibling transition targets in the same move command', () {
      final to = controller.rename(verseStateAddress, 'chorus');

      expect(to, addr('state.chorus'));
      expect(registry.contains(verseStateAddress), isFalse);
      expect(docAt(addr('state.chorus')).position, const Offset(400, 160));
      // intro's payload followed — the typed ReferenceSource rewrite.
      expect(
        docAt(introStateAddress).transitions.single.to,
        addr('state.chorus'),
      );
      expect(recorded.whereType<MoveEntityCommand>(), hasLength(1));
    });

    test('rename mid-arm keeps the arm (issue #241 done-when)', () {
      controller.toggleArmed(ref(introStateAddress, verseStateAddress));

      controller.rename(verseStateAddress, 'chorus');

      final transition = controller.transitions.single;
      expect(transition.target, addr('state.chorus'));
      expect(transition.armed, isTrue);
    });

    test('renaming the live state keeps it live', () {
      expect(controller.activeStateAddress, introStateAddress);
      final to = controller.rename(introStateAddress, 'opening');
      expect(controller.activeStateAddress, to);
    });

    test('fires onStateMoved so MIDI-graph guards can repoint', () {
      final moves = <(EntityAddress, EntityAddress)>[];
      controller.onStateMoved = (from, to) => moves.add((from, to));

      controller.rename(verseStateAddress, 'chorus');

      expect(moves, isNotEmpty);
      expect(moves.first, (verseStateAddress, addr('state.chorus')));
    });

    test(
      'undoing the rename restores payloads and remaps the arm back',
      () async {
        controller.toggleArmed(ref(introStateAddress, verseStateAddress));
        controller.rename(verseStateAddress, 'chorus');

        recorded.whereType<MoveEntityCommand>().single.revert();
        // The reverse move reaches the controller through the async registry
        // event stream — flush it before asserting.
        await pumpEventQueue();

        expect(
          docAt(introStateAddress).transitions.single.to,
          verseStateAddress,
        );
        final transition = controller.transitions.single;
        expect(transition.target, verseStateAddress);
        expect(transition.armed, isTrue);
      },
    );

    test('a blank or unchanged name is a no-op', () {
      expect(controller.rename(verseStateAddress, '   '), isNull);
      expect(controller.rename(verseStateAddress, 'verse'), verseStateAddress);
      expect(recorded, isEmpty);
    });
  });

  group('delete', () {
    test('impactOf lists the inbound transitions', () {
      final impact = controller.impactOf(verseStateAddress);
      expect(impact.hasReferrers, isTrue);
      expect(impact.referrers, contains(introStateAddress));
    });

    test('removeState strips inbound transitions and removes the entity', () {
      controller.removeState(verseStateAddress);

      expect(registry.contains(verseStateAddress), isFalse);
      expect(docAt(introStateAddress).transitions, isEmpty);
      expect(controller.states, hasLength(1));
      expect(controller.transitions, isEmpty);
      expect(recorded.whereType<UpdateEntityPayloadCommand>(), hasLength(1));
      expect(recorded.whereType<RemoveEntityCommand>(), hasLength(1));
    });

    test('deleting the live state re-seeds the live capsule', () {
      controller.setLive(verseStateAddress);
      controller.removeState(verseStateAddress);
      expect(controller.activeStateAddress, introStateAddress);
    });

    test('deleting an armed target drops the arm', () {
      controller.toggleArmed(ref(introStateAddress, verseStateAddress));
      controller.removeState(verseStateAddress);
      expect(controller.transitions, isEmpty);
      controller.connect(
        introStateAddress,
        controller.addState(name: 'verse', position: const Offset(400, 160)),
      );
      // The recreated verse does not inherit the stale arm.
      expect(controller.transitions.single.armed, isFalse);
    });
  });

  group('duplicate', () {
    test('copies the document one grid cell away under <name>_copy', () {
      final copy = controller.duplicateState(introStateAddress);

      expect(copy, addr('state.intro_copy'));
      final document = docAt(copy!);
      expect(document.position, const Offset(192, 192));
      expect(document.transitions.single.to, verseStateAddress);
      expect(controller.states, hasLength(3));
    });

    test('duplicate of an unknown state is a no-op', () {
      expect(controller.duplicateState(addr('state.ghost')), isNull);
      expect(recorded, isEmpty);
    });
  });

  group('transition drag', () {
    test('begin/end expose the drag source for the ghost arrow', () {
      controller.beginTransitionDrag(introStateAddress);
      expect(controller.dragSourceState, introStateAddress);

      controller.endTransitionDrag();
      expect(controller.dragSourceState, isNull);
    });
  });

  group('rebind', () {
    test('swaps the registry, re-seeds live, clears performance state', () {
      controller.toggleArmed(ref(introStateAddress, verseStateAddress));
      controller.setLive(verseStateAddress);

      final other = ProjectRegistry();
      addTearDown(other.dispose);
      const solo = StateDocument(position: Offset(32, 32));
      other.createEntity(
        addr('state.solo'),
        payload: solo.toJson(),
        references: solo.references,
      );

      final rebound = <ProjectCommand>[];
      controller.rebind(registry: other, recordCommand: rebound.add);

      expect(controller.states.single.address, addr('state.solo'));
      expect(controller.activeStateAddress, addr('state.solo'));
      expect(controller.transitions, isEmpty);

      // Edits journal through the new callback, into the new registry.
      controller.addState(name: 'later', position: Offset.zero);
      expect(rebound, hasLength(1));
      expect(other.contains(addr('state.later')), isTrue);
      expect(recorded, isEmpty);
    });
  });
}
