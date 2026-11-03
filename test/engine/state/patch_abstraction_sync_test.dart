import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/state/patch_library_controller.dart';
import 'package:phi/engine/state/patch_reconciler.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Abstractions across a project (issue #553): one `patch.` entity, instances
/// of it in several others, every instance following a change to it — open or
/// not, nested or not — and the registry knowing who uses what.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);

  late FakePatcherGateway gateway;
  late ProjectRegistry registry;
  late PatchReconciler reconciler;
  late PatchLibraryController library;
  late List<ProjectCommand> recorded;

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

  PatchPortId inlet(PatchNodeId id, [int i = 0]) =>
      PatchPortId(nodeId: id, side: PatchPortSide.input, index: i);
  PatchPortId outlet(PatchNodeId id, [int i = 0]) =>
      PatchPortId(nodeId: id, side: PatchPortSide.output, index: i);

  PatchNodeId make(
    PatcherController editor,
    String type, {
    String? args,
    PatchNodeId? inside,
    Offset at = Offset.zero,
  }) => editor.createObject(
    desc: desc(type),
    position: at,
    args: args ?? '',
    container: inside,
  )!;

  /// A new empty patch [name] and its editor.
  PatcherController newPatch(String name) {
    registry.createEntity(patch(name), payload: PatchPayload.empty.toJson());
    reconciler.sync(registry);
    return library.editorFor(patch(name))!;
  }

  /// A patch [name] holding `~inlet 0` → `~* 0.5` → `~outlet 0`.
  (PatcherController, PatchNodeId) gainPatch([String name = 'gain']) {
    final editor = newPatch(name);
    final i = make(editor, Obj.dInlet, args: '0');
    final g = make(editor, Obj.dSine, args: '0.5', at: const Offset(0, 80));
    final o = make(editor, Obj.dOutlet, args: '0', at: const Offset(0, 160));
    editor
      ..connectViaGesture(outlet(i), inlet(g))
      ..connectViaGesture(outlet(g), inlet(o));
    return (editor, g);
  }

  /// Makes an instance of [definition] the way the object box does, by typing
  /// its address over the `patcher` box.
  PatchNodeId instance(PatcherController parent, EntityAddress definition) =>
      make(parent, Obj.patcher, args: definition.format());

  /// The args of the first object of [type] inside [box].
  String argsIn(PatcherController editor, PatchNodeId box, String type) {
    final node = editor.nodesIn(box).firstWhere((n) => n.type == type);
    return editor.argsOf(node.id);
  }

  setUp(() {
    gateway = FakePatcherGateway();
    registry = ProjectRegistry();
    recorded = [];
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
      recordCommand: recorded.add,
    );
  });

  tearDown(() {
    library.dispose();
    reconciler.teardown();
  });

  group('materialising', () {
    test('a box named after a patch fills with its contents and pins', () {
      gainPatch();
      final parent = newPatch('song');

      final box = instance(parent, patch('gain'));

      expect(parent.abstractionOf(box), patch('gain'));
      expect(argsIn(parent, box, Obj.dSine), '0.5');
      expect(parent.graph.nodeById(box)!.inputs, hasLength(1));
      expect(parent.graph.nodeById(box)!.outputs, hasLength(1));
      expect(parent.graph.cables, hasLength(2));
    });

    test('offered under its address, the object box makes the same box', () {
      gainPatch();
      final parent = newPatch('song');
      final offered = library
          .abstractionTypes(parent)
          .firstWhere((d) => d.type == 'patch.gain');

      final box = parent.createObject(
        desc: offered,
        position: Offset.zero,
        args: '',
      )!;

      expect(parent.graph.nodeById(box)!.type, Obj.patcher);
      expect(parent.argsOf(box), 'patch.gain');
      expect(argsIn(parent, box, Obj.dSine), '0.5');
    });

    test('a box typed over with an address follows that patch instead', () {
      gainPatch();
      final (other, _) = gainPatch('other');
      other.applyParams(
        other.nodesIn(null).firstWhere((n) => n.type == Obj.dSine).id,
        '0.9',
      );
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));
      final offered = library
          .abstractionTypes(parent)
          .firstWhere((d) => d.type == 'patch.other');

      parent.applyBoxEdit(box, desc: offered, args: '');

      expect(parent.abstractionOf(box), patch('other'));
      expect(argsIn(parent, box, Obj.dSine), '0.9');
    });

    test('an undo takes the instance away; a redo materialises it again', () {
      gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));

      parent.undo();
      expect(parent.graph.nodes, isEmpty);

      parent.redo();
      expect(parent.abstractionOf(box), patch('gain'));
      expect(argsIn(parent, box, Obj.dSine), '0.5');
      expect(parent.graph.nodeById(box)!.inputs, hasLength(1));
    });

    test('duplicating an instance makes one more that follows', () {
      final (definition, gain) = gainPatch();
      final parent = newPatch('song');
      instance(parent, patch('gain'));
      parent.selectNodes({parent.nodesIn(null).single.id});
      parent.duplicateSelection();
      final boxes = parent.nodesIn(null).map((n) => n.id).toList();
      expect(boxes, hasLength(2));

      definition.applyParams(gain, '0.1');

      for (final box in boxes) {
        expect(argsIn(parent, box, Obj.dSine), '0.1');
      }
    });
  });

  group('a change to the definition', () {
    test('reaches every instance in every patch at once', () {
      final (definition, gain) = gainPatch();
      final one = newPatch('one');
      final two = newPatch('two');
      final first = instance(one, patch('gain'));
      final second = instance(one, patch('gain'));
      final third = instance(two, patch('gain'));

      definition.applyParams(gain, '0.25');

      expect(argsIn(one, first, Obj.dSine), '0.25');
      expect(argsIn(one, second, Obj.dSine), '0.25');
      expect(argsIn(two, third, Obj.dSine), '0.25');
    });

    test('is undone with its undo, everywhere', () {
      final (definition, gain) = gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));

      definition.applyParams(gain, '0.25');
      definition.undo();

      expect(argsIn(parent, box, Obj.dSine), '0.5');
      definition.redo();
      expect(argsIn(parent, box, Obj.dSine), '0.25');
    });

    test('runs through nested abstractions in one go', () {
      final (inner, gain) = gainPatch('inner');
      final middle = newPatch('middle');
      final held = instance(middle, patch('inner'));
      final outer = newPatch('outer');
      final box = instance(outer, patch('middle'));
      final nested = outer
          .nodesIn(box)
          .singleWhere((n) => n.type == Obj.patcher);
      expect(outer.argsOf(nested.id), 'patch.inner');

      inner.applyParams(gain, '0.75');

      expect(argsIn(middle, held, Obj.dSine), '0.75');
      expect(argsIn(outer, nested.id, Obj.dSine), '0.75');
    });

    test('says on the parent\'s canvas when it costs a cable', () {
      final (definition, _) = gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));
      final sine = make(parent, Obj.dSine, args: '440');
      parent.connectViaGesture(outlet(sine), inlet(box));
      final said = <String?>[];
      parent.notice.addListener(() => said.add(parent.notice.value));

      final pin = definition
          .nodesIn(null)
          .firstWhere((n) => n.type == Obj.dInlet);
      definition.selectNodes({pin.id});
      definition.deleteSelection();

      expect(said.whereType<String>().single, contains('1 cable dropped'));
      expect(parent.graph.nodeById(box)!.inputs, isEmpty);
    });

    test('an undo in the parent that names a gone pin draws no cable', () {
      final (definition, _) = gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));
      final sine = make(parent, Obj.dSine, args: '440');
      parent.connectViaGesture(outlet(sine), inlet(box));
      final pin = definition
          .nodesIn(null)
          .firstWhere((n) => n.type == Obj.dInlet);
      definition.selectNodes({pin.id});
      definition.deleteSelection();

      parent.undo(); // the connect, whose pin is gone
      parent.redo();

      expect(
        parent.graph.cables.where((c) => c.source.nodeId == sine),
        isEmpty,
      );
    });
  });

  group('detach and make abstraction', () {
    test('a detached instance keeps its contents and stops following', () {
      final (definition, gain) = gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));

      parent.detachInstance(box);
      definition.applyParams(gain, '0.25');

      expect(parent.abstractionOf(box), isNull);
      expect(parent.argsOf(box), 'gain');
      expect(argsIn(parent, box, Obj.dSine), '0.5');
      expect(registry.referencesOf(patch('song')), isEmpty);
    });

    test('undoing a detach follows again, catching up', () {
      final (definition, gain) = gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));
      parent.detachInstance(box);
      definition.applyParams(gain, '0.25');

      parent.undo();

      expect(parent.abstractionOf(box), patch('gain'));
      expect(argsIn(parent, box, Obj.dSine), '0.25');
    });

    test('make abstraction moves a box\'s contents behind a new patch', () {
      final parent = newPatch('song');
      final box = make(parent, Obj.patcher, args: 'level');
      final held = make(parent, Obj.dSine, args: '0.5', inside: box);
      final pin = make(parent, Obj.dOutlet, args: '0', inside: box);
      parent.connectViaGesture(outlet(held), inlet(pin));
      final dac = make(parent, Obj.dDac, at: const Offset(0, 100));
      parent.connectViaGesture(outlet(box), inlet(dac));

      final address = library.makeAbstraction(parent, box);

      expect(address, patch('level'));
      expect(parent.abstractionOf(box), address);
      expect(
        parent.graph.nodeById(held),
        isNotNull,
        reason: 'kept, not copied',
      );
      expect(parent.graph.cables, hasLength(2), reason: 'wiring untouched');
      final definition = library.editorFor(address!)!;
      expect(definition.nodesIn(null), hasLength(2));
      expect(definition.graph.cables, hasLength(1));
      expect(registry.referencesOf(patch('song')), {address});

      definition.applyParams(
        definition.nodesIn(null).firstWhere((n) => n.type == Obj.dSine).id,
        '0.25',
      );
      expect(parent.argsOf(held), '0.25', reason: 'the box follows it now');
    });

    test('undoing make abstraction leaves the box ordinary and the patch', () {
      final parent = newPatch('song');
      final box = make(parent, Obj.patcher, args: 'level');
      make(parent, Obj.dSine, args: '220', inside: box);
      final address = library.makeAbstraction(parent, box)!;

      parent.undo();

      expect(parent.abstractionOf(box), isNull);
      expect(parent.nodesIn(box), hasLength(1));
      expect(registry.entityAt(address), isNotNull);
    });

    test('an instance cannot be made an abstraction again', () {
      gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));
      expect(library.makeAbstraction(parent, box), isNull);
    });
  });

  group('loops', () {
    test('a patch is not offered itself or anything that uses it', () {
      final (definition, _) = gainPatch();
      final parent = newPatch('song');
      instance(parent, patch('gain'));

      final offered = library.abstractionTypes(definition).map((d) => d.type);

      expect(offered, isNot(contains('patch.gain')));
      expect(offered, isNot(contains('patch.song')));
      expect(
        library.abstractionTypes(parent).map((d) => d.type),
        contains('patch.gain'),
      );
    });

    test('typed anyway, the box stays empty and the canvas says why', () {
      final (definition, _) = gainPatch();
      final said = <String?>[];
      definition.notice.addListener(() => said.add(definition.notice.value));

      final box = instance(definition, patch('gain'));

      expect(definition.nodesIn(box), isEmpty);
      expect(said.whereType<String>().single, contains('patch.gain'));
    });

    test('a longer loop freezes the boxes, and neither grows', () {
      final (first, _) = gainPatch('first');
      final second = newPatch('second');
      instance(second, patch('first'));
      final before = second.graph.nodes.length;

      final back = instance(first, patch('second'));

      expect(first.nodesIn(back), isEmpty);
      expect(second.graph.nodes, hasLength(before));
    });
  });

  group('in the project', () {
    test('a patch references the definitions it uses', () {
      gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));

      expect(registry.referencesOf(patch('song')), {patch('gain')});
      expect(library.impactOf(patch('gain')).referrers, [patch('song')]);

      parent.selectNodes({box});
      parent.deleteSelection();
      expect(registry.referencesOf(patch('song')), isEmpty);
      expect(library.impactOf(patch('gain')).isSafe, isTrue);
    });

    test('deleting the definition leaves the instance as it was', () async {
      gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));

      library.delete(patch('gain'));
      await pumpEventQueue();

      expect(parent.abstractionOf(box), patch('gain'));
      expect(argsIn(parent, box, Obj.dSine), '0.5');
      expect(library.canFollow(parent, patch('gain')), isFalse);
    });

    test('a patch made at that address again picks its instances up', () async {
      gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));
      library.delete(patch('gain'));
      await pumpEventQueue();

      final (_, gain) = gainPatch();
      library.editorFor(patch('gain'))!.applyParams(gain, '0.9');
      await pumpEventQueue();

      expect(library.canFollow(parent, patch('gain')), isTrue);
      expect(argsIn(parent, box, Obj.dSine), '0.9');
    });

    test('renaming the definition rewrites every box naming it', () async {
      gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));
      library.open(patch('song'));

      library.rename(patch('gain'), 'level');
      await pumpEventQueue();

      final live = library.editorFor(patch('song'))!;
      expect(live.abstractionOf(box), patch('level'));
      expect(
        gateway.enumerate(live.instanceId).objects.map((o) => o.args),
        contains('patch.level'),
      );
      expect(registry.referencesOf(patch('song')), {patch('level')});

      // And it still follows, through the renamed patch's fresh editor.
      final renamed = library.editorFor(patch('level'))!;
      final fresh = renamed
          .nodesIn(null)
          .firstWhere((n) => n.type == Obj.dSine);
      renamed.applyParams(fresh.id, '0.1');
      expect(argsIn(live, box, Obj.dSine), '0.1');
    });

    test('a saved parent reloads into an instance that still follows', () {
      final (definition, gain) = gainPatch();
      final parent = newPatch('song');
      final box = instance(parent, patch('gain'));
      reconciler.flushToPayloads(registry, null);
      final saved = {
        for (final name in ['gain', 'song'])
          name: registry.entityAt(patch(name))!.payload,
      };
      expect(definition.argsOf(gain), '0.5');
      expect(parent.argsOf(box), 'patch.gain');

      // A project opened from those payloads, with no editor bound yet.
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
      freshLibrary.open(patch('gain'));

      expect(freshRegistry.referencesOf(patch('song')), {patch('gain')});
      final reopened = freshLibrary.editorFor(patch('song'))!;
      final reopenedBox = reopened
          .nodesIn(null)
          .singleWhere((n) => n.type == Obj.patcher);
      expect(reopened.abstractionOf(reopenedBox.id), patch('gain'));

      final reopenedDefinition = freshLibrary.editorFor(patch('gain'))!;
      reopenedDefinition.applyParams(
        reopenedDefinition
            .nodesIn(null)
            .firstWhere((n) => n.type == Obj.dSine)
            .id,
        '0.3',
      );
      expect(argsIn(reopened, reopenedBox.id, Obj.dSine), '0.3');
    });

    test('a definition saved past its instance is caught up with on load', () {
      final (definition, gain) = gainPatch();
      final parent = newPatch('song');
      instance(parent, patch('gain'));
      reconciler.flushToPayloads(registry, null);
      final staleParent = registry.entityAt(patch('song'))!.payload;
      definition.applyParams(gain, '0.25');
      reconciler.flushToPayloads(registry, null);
      final newDefinition = registry.entityAt(patch('gain'))!.payload;

      final freshRegistry = ProjectRegistry()
        ..createEntity(patch('gain'), payload: newDefinition)
        ..createEntity(patch('song'), payload: staleParent);
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

      freshLibrary.openFirst();

      final reopened = freshLibrary.editorFor(patch('song'))!;
      final box = reopened
          .nodesIn(null)
          .singleWhere((n) => n.type == Obj.patcher);
      expect(argsIn(reopened, box.id, Obj.dSine), '0.25');
    });

    test('a project with no abstractions binds and touches nothing', () {
      registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
      registry.createEntity(patch('b'), payload: PatchPayload.empty.toJson());
      reconciler.sync(registry);
      gateway.calls.clear();

      library.open(patch('a'));

      expect(gateway.calls, isEmpty);
      expect(library.addressOf(library.openEditor!), patch('a'));
    });
  });
}
