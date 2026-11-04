import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/patcher/patch_type_name.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/state/patch_library_controller.dart';
import 'package:phi/engine/state/patch_reconciler.dart';
import 'package:phi/engine/state/patcher_commands/move_patch_nodes_command.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// `#0` in an abstraction (issue #561): every instance box has a number of its
/// own, its copy spells that number, and neither moves unless it has to, so an
/// edit somewhere else never rewires what is already running.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);

  late FakePatcherGateway gateway;
  late ProjectRegistry registry;
  late PatchReconciler reconciler;
  late PatchLibraryController library;

  PatchObjectDescriptor desc(String type) => gateway.objectTypes().firstWhere(
    (d) => d.type == type,
    orElse: () => PatchObjectDescriptor(
      type: type,
      description: '',
      category: PatchObjectCategory.generic,
      isDsp: false,
      inlets: const [],
      outlets: const [],
      params: const [],
    ),
  );

  PatchNodeId make(
    PatcherController editor,
    String type, {
    String args = '',
    PatchNodeId? inside,
    Offset at = Offset.zero,
  }) => editor.createObject(
    desc: desc(type),
    position: at,
    args: args,
    container: inside,
  )!;

  PatcherController newPatch(String name) {
    registry.createEntity(patch(name), payload: PatchPayload.empty.toJson());
    reconciler.sync(registry);
    return library.editorFor(patch(name))!;
  }

  PatchNodeId instance(PatcherController parent, String definition) =>
      make(parent, Obj.patcher, args: patch(definition).format());

  /// A definition holding `.s ping#0`, at the origin.
  (PatcherController, PatchNodeId) pingPatch([String name = 'voice']) {
    final editor = newPatch(name);
    return (editor, make(editor, Obj.gSend, args: 'ping#0'));
  }

  /// The arguments of every `.s` inside [box].
  List<String> sendsIn(PatcherController editor, PatchNodeId? box) => [
    for (final node in editor.nodesIn(box))
      if (node.type == Obj.gSend) editor.argsOf(node.id),
  ];

  /// The native writes of an object's arguments since the calls were cleared.
  Iterable<String> writes() =>
      gateway.calls.where((c) => c.startsWith('setParams:'));

  setUp(() {
    gateway = FakePatcherGateway();
    registry = ProjectRegistry();
    reconciler = PatchReconciler(
      gateway: gateway,
      resolveBus: (_) => null,
      onNotice: (_) {},
    );
    library = PatchLibraryController(
      registry: registry,
      patches: reconciler,
      gateway: gateway,
      busOptions: () => const [],
      recordCommand: (_) {},
    );
  });

  tearDown(() {
    library.dispose();
    reconciler.teardown();
  });

  group('a new instance', () {
    test('spells its own number, and the definition stays as typed', () {
      final (definition, send) = pingPatch();
      final parent = newPatch('song');

      final one = instance(parent, 'voice');
      final two = instance(parent, 'voice');

      final a = parent.instanceNumberOf(one)!;
      final b = parent.instanceNumberOf(two)!;
      expect(a, isNot(b));
      expect(a, isNot(0));
      expect(sendsIn(parent, one), ['ping#$a']);
      expect(sendsIn(parent, two), ['ping#$b']);
      expect(definition.argsOf(send), 'ping#0');
    });

    test('a patch\'s numbers are its own: two patches may both have a 1', () {
      pingPatch();
      final song = newPatch('song');
      final other = newPatch('other');

      final here = instance(song, 'voice');
      final there = instance(other, 'voice');

      expect(song.instanceNumberOf(here), other.instanceNumberOf(there));
    });

    test('the whole of what it holds reads the same number', () {
      final definition = newPatch('voice');
      final inner = make(definition, Obj.patcher, args: 'inner');
      make(definition, Obj.gSend, args: 'ping#0', inside: inner);
      final parent = newPatch('song');

      final box = instance(parent, 'voice');

      final copy = parent.nodesIn(box).single;
      expect(sendsIn(parent, copy.id), [
        'ping#${parent.instanceNumberOf(box)}',
      ]);
    });

    test('a copy of a longer name gets the box the longer name needs', () {
      pingPatch();
      final parent = newPatch('song');
      // Past the numbers the digits would otherwise fit in.
      for (var i = 0; i < 12; i++) {
        instance(parent, 'voice');
      }
      final last = parent.nodesIn(null).last.id;
      final send = parent.nodesIn(last).single;

      expect(parent.argsOf(send.id), endsWith('#12'));
      final fresh = newPatch('fresh');
      final same = make(fresh, Obj.gSend, args: parent.argsOf(send.id));
      expect(send.size, fresh.graph.nodeById(same)!.size);
    });

    test('a note in the definition stays as it was written', () {
      final definition = newPatch('voice');
      make(definition, PatchTypeName.noteType, args: 'wire #0 first');
      final parent = newPatch('song');

      final box = instance(parent, 'voice');

      expect(parent.argsOf(parent.nodesIn(box).single.id), 'wire #0 first');
    });
  });

  group('an edit in the definition', () {
    test('writes nothing to a copy that already reads right', () {
      final (definition, _) = pingPatch();
      final other = make(
        definition,
        Obj.dSine,
        args: '440',
        at: const Offset(0, 80),
      );
      final parent = newPatch('song');
      final box = instance(parent, 'voice');
      final kept = parent.nodesIn(box).firstWhere((n) => n.type == Obj.gSend);
      gateway.calls.clear();

      definition.applyParams(other, '220');

      final wrote = writes().toList();
      expect(wrote, hasLength(2), reason: 'the definition and its one copy');
      expect(wrote.any((c) => c.endsWith('220')), isTrue);
      expect(wrote.any((c) => c.contains('ping')), isFalse);
      expect(parent.graph.nodeById(kept.id), isNotNull);
    });

    test('a token added later lands on each copy in place', () {
      final definition = newPatch('voice');
      final send = make(definition, Obj.gSend, args: 'ping');
      final parent = newPatch('song');
      final one = instance(parent, 'voice');
      final two = instance(parent, 'voice');
      final kept = parent.nodesIn(one).single.id;

      definition.applyParams(send, 'ping#0');

      expect(parent.nodesIn(one).single.id, kept, reason: 'kept, not remade');
      expect(sendsIn(parent, one), ['ping#${parent.instanceNumberOf(one)}']);
      expect(sendsIn(parent, two), ['ping#${parent.instanceNumberOf(two)}']);
    });

    test('moving an object with a token keeps the copy, in its place', () {
      final (definition, send) = pingPatch();
      final parent = newPatch('song');
      final box = instance(parent, 'voice');
      final kept = parent.nodesIn(box).single.id;
      gateway.calls.clear();

      definition.undoScope.run(
        MovePatchNodesCommand(
          definition,
          from: {send: Offset.zero},
          to: {send: const Offset(40, 40)},
        ),
      );

      final copy = parent.graph.nodeById(kept)!;
      expect(copy.position, const Offset(40, 40));
      expect(writes(), isEmpty, reason: 'the name did not move');
    });
  });

  group('a copy of an instance', () {
    test('a duplicate gets its own number, the original is not touched', () {
      pingPatch();
      final parent = newPatch('song');
      final box = instance(parent, 'voice');
      final number = parent.instanceNumberOf(box)!;
      gateway.calls.clear();

      parent.selectNodes({box});
      parent.duplicateSelection();

      final copy = parent.nodesIn(null).singleWhere((n) => n.id != box).id;
      final fresh = parent.instanceNumberOf(copy)!;
      expect(fresh, isNot(number));
      expect(parent.instanceNumberOf(box), number);
      expect(sendsIn(parent, box), ['ping#$number']);
      expect(sendsIn(parent, copy), ['ping#$fresh']);
      expect(writes(), hasLength(1), reason: 'only the copy was respelled');
    });

    test('an undo gives a deleted box its number back, not to another', () {
      pingPatch();
      final parent = newPatch('song');
      final box = instance(parent, 'voice');
      final number = parent.instanceNumberOf(box)!;

      parent.selectNodes({box});
      parent.deleteSelection();
      final next = instance(parent, 'voice');
      expect(parent.instanceNumberOf(next), isNot(number));
      parent.undo(); // the new box
      parent.undo(); // the delete

      final back = parent.nodesIn(null).single.id;
      expect(parent.instanceNumberOf(back), number);
      expect(sendsIn(parent, back), ['ping#$number']);
    });

    test('with its definition gone, a duplicate is still told apart', () async {
      pingPatch();
      final parent = newPatch('song');
      final box = instance(parent, 'voice');
      library.delete(patch('voice'));
      await pumpEventQueue();

      parent.selectNodes({box});
      parent.duplicateSelection();

      final copy = parent.nodesIn(null).singleWhere((n) => n.id != box).id;
      final fresh = parent.instanceNumberOf(copy)!;
      expect(fresh, isNot(parent.instanceNumberOf(box)));
      expect(sendsIn(parent, copy), ['ping#$fresh']);
    });
  });

  group('nesting', () {
    test('a nested instance has its own number, in every patch using it', () {
      final (inner, send) = pingPatch('inner');
      final middle = newPatch('middle');
      final heldInMiddle = instance(middle, 'inner');
      make(middle, Obj.gSend, args: 'mid#0', at: const Offset(0, 80));
      final parent = newPatch('song');

      final one = instance(parent, 'middle');
      final two = instance(parent, 'middle');

      PatchNodeId nested(PatchNodeId box) =>
          parent.nodesIn(box).singleWhere((n) => n.type == Obj.patcher).id;
      final numbers = [
        parent.instanceNumberOf(one)!,
        parent.instanceNumberOf(two)!,
        parent.instanceNumberOf(nested(one))!,
        parent.instanceNumberOf(nested(two))!,
      ];
      expect(numbers.toSet(), hasLength(4));
      expect(sendsIn(parent, one), ['mid#${numbers[0]}']);
      expect(sendsIn(parent, two), ['mid#${numbers[1]}']);
      expect(sendsIn(parent, nested(one)), ['ping#${numbers[2]}']);
      expect(sendsIn(parent, nested(two)), ['ping#${numbers[3]}']);
      expect(sendsIn(middle, heldInMiddle), [
        'ping#${middle.instanceNumberOf(heldInMiddle)}',
      ]);

      inner.applyParams(send, 'pong#0');

      expect(sendsIn(parent, nested(one)), ['pong#${numbers[2]}']);
      expect(sendsIn(parent, nested(two)), ['pong#${numbers[3]}']);
      expect(parent.instanceNumberOf(nested(one)), numbers[2]);
    });

    test('nothing nested is rewritten by a pass over its parent', () {
      pingPatch('inner');
      final middle = newPatch('middle');
      instance(middle, 'inner');
      final parent = newPatch('song');
      instance(parent, 'middle');
      gateway.calls.clear();

      library.open(patch('song')); // runs the sync over the whole project

      expect(writes(), isEmpty);
      expect(
        gateway.calls.where((c) => c.startsWith('setGuiProperty')),
        isEmpty,
      );
    });
  });

  group('leaving and coming back', () {
    test('a detached box keeps its names, and undoing changes nothing', () {
      final (definition, send) = pingPatch();
      final parent = newPatch('song');
      final box = instance(parent, 'voice');
      final number = parent.instanceNumberOf(box)!;

      parent.detachInstance(box);
      expect(sendsIn(parent, box), ['ping#$number']);
      definition.applyParams(send, 'pong#0');
      expect(sendsIn(parent, box), ['ping#$number'], reason: 'not following');

      parent.undo();

      expect(parent.instanceNumberOf(box), number);
      expect(sendsIn(parent, box), ['pong#$number']);
    });

    test('a detached box made an abstraction again has the token back', () {
      pingPatch();
      final parent = newPatch('song');
      final box = instance(parent, 'voice');
      final number = parent.instanceNumberOf(box)!;
      parent.detachInstance(box);

      final made = library.makeAbstraction(parent, box)!;

      final definition = library.editorFor(made)!;
      expect(sendsIn(definition, null), ['ping#0']);
      expect(parent.instanceNumberOf(box), number);
      expect(sendsIn(parent, box), ['ping#$number']);
    });

    test(
      'an ordinary subpatch made an abstraction: its #0 starts to count',
      () {
        final parent = newPatch('song');
        final box = make(parent, Obj.patcher, args: 'voice');
        make(parent, Obj.gSend, args: 'ping#0', inside: box);
        expect(sendsIn(parent, box), ['ping#0'], reason: 'just a name, so far');
        expect(parent.instanceNumberOf(box), isNull);

        final made = library.makeAbstraction(parent, box)!;

        expect(sendsIn(library.editorFor(made)!, null), ['ping#0']);
        expect(sendsIn(parent, box), ['ping#${parent.instanceNumberOf(box)}']);
      },
    );

    test('a detached box\'s number is not given to a new instance', () {
      pingPatch();
      final parent = newPatch('song');
      final box = instance(parent, 'voice');
      final number = parent.instanceNumberOf(box);
      parent.detachInstance(box);

      final next = instance(parent, 'voice');

      expect(parent.instanceNumberOf(next), isNot(number));
    });
  });

  test('a project reloaded from its payloads keeps every number', () {
    pingPatch();
    final parent = newPatch('song');
    final one = instance(parent, 'voice');
    final two = instance(parent, 'voice');
    final numbers = {
      parent.instanceNumberOf(one)!,
      parent.instanceNumberOf(two)!,
    };
    reconciler.flushToPayloads(registry, null);
    final saved = {
      for (final name in ['voice', 'song'])
        name: registry.entityAt(patch(name))!.payload,
    };

    final freshRegistry = ProjectRegistry();
    saved.forEach(
      (name, payload) =>
          freshRegistry.createEntity(patch(name), payload: payload),
    );
    final freshGateway = FakePatcherGateway();
    final freshReconciler = PatchReconciler(
      gateway: freshGateway,
      resolveBus: (_) => null,
      onNotice: (_) {},
    )..sync(freshRegistry);
    final freshLibrary = PatchLibraryController(
      registry: freshRegistry,
      patches: freshReconciler,
      gateway: freshGateway,
      busOptions: () => const [],
    );
    addTearDown(() {
      freshLibrary.dispose();
      freshReconciler.teardown();
    });
    freshLibrary.open(patch('voice'));

    final reopened = freshLibrary.editorFor(patch('song'))!;
    final boxes = reopened.nodesIn(null).map((n) => n.id).toList();
    expect(boxes.map(reopened.instanceNumberOf).toSet(), numbers);
    for (final box in boxes) {
      expect(sendsIn(reopened, box), [
        'ping#${reopened.instanceNumberOf(box)}',
      ]);
    }
    expect(
      freshGateway.calls.where((c) => c.startsWith('setParams:')),
      isEmpty,
      reason: 'a reload rewires nothing',
    );
  });
}
