import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/state/patch_instance_materialiser.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Bringing one window of a patch in line with another (issue #553): what pairs
/// up is kept, the rest is made or deleted, the parent's cables stay on the pins
/// they were on, and a run with nothing to do writes nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePatcherGateway gateway;
  late PatcherController definition;
  late PatcherController parent;
  late PatchNodeId box;

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

  PatchPortId inlet(PatchNodeId id, [int i = 0]) =>
      PatchPortId(nodeId: id, side: PatchPortSide.input, index: i);
  PatchPortId outlet(PatchNodeId id, [int i = 0]) =>
      PatchPortId(nodeId: id, side: PatchPortSide.output, index: i);

  PatchInstanceMaterialiser sync() => PatchInstanceMaterialiser(
    source: definition,
    sourceScope: null,
    target: parent,
    targetScope: box,
  )..run();

  /// The window's contents, as `type args` lines.
  Set<String> contents() => {
    for (final n in parent.nodesIn(box)) '${n.type} ${parent.argsOf(n.id)}',
  };

  PatchNodeId inside(String type) =>
      parent.nodesIn(box).firstWhere((n) => n.type == type).id;

  setUp(() {
    gateway = FakePatcherGateway();
    definition = PatcherController(gateway);
    parent = PatcherController(gateway);
    box = make(parent, Obj.patcher, args: 'patch.gain');
  });

  tearDown(() {
    definition.dispose();
    parent.dispose();
  });

  /// `~inlet 0` → `~* 0.5` → `~outlet 0` in the definition.
  ({PatchNodeId inlet, PatchNodeId gain, PatchNodeId outlet}) gainDefinition() {
    final i = make(definition, Obj.dInlet, args: '0');
    final g = make(definition, Obj.dSine, args: '0.5', at: const Offset(0, 80));
    final o = make(
      definition,
      Obj.dOutlet,
      args: '0',
      at: const Offset(0, 160),
    );
    definition
      ..connectViaGesture(outlet(i), inlet(g))
      ..connectViaGesture(outlet(g), inlet(o));
    return (inlet: i, gain: g, outlet: o);
  }

  test('copies the objects and cables, and gives the box its pins', () {
    gainDefinition();

    expect(sync().changed, isTrue);

    expect(contents(), {
      '${Obj.dInlet} 0',
      '${Obj.dSine} 0.5',
      '${Obj.dOutlet} 0',
    });
    expect(parent.graph.cables, hasLength(2));
    final node = parent.graph.nodeById(box)!;
    expect(node.inputs, hasLength(1));
    expect(node.outputs, hasLength(1));
  });

  test('a second run with nothing to do writes nothing', () {
    gainDefinition();
    sync();
    gateway.calls.clear();

    expect(sync().changed, isFalse);

    expect(gateway.calls, isEmpty);
  });

  test('a changed argument keeps the object: its state is not thrown away', () {
    final made = gainDefinition();
    sync();
    final copy = inside(Obj.dSine);

    definition.applyParams(made.gain, '0.25');
    sync();

    expect(inside(Obj.dSine), copy);
    expect(parent.argsOf(copy), '0.25');
    expect(parent.graph.cables, hasLength(2));
    expect(gateway.calls.where((c) => c.startsWith('deleteObject')), isEmpty);
  });

  test('a move keeps the object and only moves it', () {
    final made = gainDefinition();
    sync();
    final copy = inside(Obj.dSine);

    definition.placeNode(made.gain, const Offset(200, 80));
    sync();

    expect(inside(Obj.dSine), copy);
    expect(parent.graph.nodeById(copy)!.position, const Offset(200, 80));
  });

  test('objects and cables added to and taken from the definition follow', () {
    final made = gainDefinition();
    sync();

    final limit = make(
      definition,
      Obj.dSine,
      args: '2',
      at: const Offset(0, 120),
    );
    definition.selectNodes({made.gain});
    definition.deleteSelection();
    definition.connectViaGesture(outlet(made.inlet), inlet(limit));
    definition.connectViaGesture(outlet(limit), inlet(made.outlet));
    sync();

    expect(contents(), {
      '${Obj.dInlet} 0',
      '${Obj.dSine} 2',
      '${Obj.dOutlet} 0',
    });
    expect(parent.graph.cables, hasLength(2));
  });

  test('a decoration follows, and goes when the definition drops it', () {
    final note = make(definition, '.text', args: 'hello');
    definition.setNoteColor(note, 'note-amber');
    sync();
    final copy = inside('.text');
    expect(parent.noteColorOf(copy), 'note-amber');

    definition.setNoteColor(note, '');
    sync();

    expect(parent.noteColorOf(copy), '');
  });

  group('the parent\'s cables', () {
    late PatchNodeId sine;
    late PatchNodeId dac;

    setUp(() {
      sine = make(parent, Obj.dSine, args: '440', at: const Offset(0, -80));
      dac = make(parent, Obj.dDac, at: const Offset(0, 80));
    });

    void wireParent() {
      parent
        ..connectViaGesture(outlet(sine), inlet(box))
        ..connectViaGesture(outlet(box), inlet(dac));
    }

    test('stay on a boundary object that is kept', () {
      gainDefinition();
      sync();
      wireParent();
      final pin = inside(Obj.dInlet);

      sync();

      expect(inside(Obj.dInlet), pin);
      expect(parent.graph.cables, hasLength(4));
    });

    test(
      'move to the object that now claims the pin, when one replaces it',
      () {
        final made = gainDefinition();
        sync();
        wireParent();
        final before = inside(Obj.dOutlet);

        // A message outlet feeds anything, so the parent's `~dac` can stay.
        definition.applyBoxEdit(
          made.outlet,
          desc: desc(Obj.gOutlet),
          args: '0',
        );
        final run = sync();

        expect(run.dropped, 0);
        expect(parent.graph.nodeById(before), isNull);
        final pin = inside(Obj.gOutlet);
        expect(
          parent.graph.cables.where(
            (c) => c.source.nodeId == pin && c.target.nodeId == dac,
          ),
          hasLength(1),
        );
      },
    );

    test('are counted when the new object does not accept them', () {
      final made = gainDefinition();
      sync();
      wireParent();

      // A message inlet takes no audio, and the parent's cable is audio.
      definition.applyBoxEdit(made.inlet, desc: desc(Obj.gInlet), args: '0');
      final run = sync();

      expect(run.dropped, 1);
      expect(
        parent.graph.cables.where((c) => c.source.nodeId == sine),
        isEmpty,
      );
    });

    test('are counted when the pin is gone', () {
      final made = gainDefinition();
      sync();
      wireParent();
      expect(parent.graph.cables, hasLength(4));

      definition.selectNodes({made.inlet});
      definition.deleteSelection();
      final run = sync();

      expect(run.dropped, 1);
      expect(parent.graph.nodeById(box)!.inputs, isEmpty);
      expect(
        parent.graph.cables.where((c) => c.source.nodeId == sine),
        isEmpty,
      );
      expect(
        parent.graph.cables.where((c) => c.target.nodeId == dac),
        hasLength(1),
        reason: 'the other pin is untouched',
      );
    });
  });

  test('a subpatch inside the definition is copied with what it holds', () {
    final inner = make(definition, Obj.patcher, args: 'inner');
    final sine = make(definition, Obj.dSine, args: '220', inside: inner);
    final out = make(definition, Obj.dOutlet, args: '0', inside: inner);
    definition.connectViaGesture(outlet(sine), inlet(out));
    final dac = make(definition, Obj.dDac, at: const Offset(0, 100));
    definition.connectViaGesture(outlet(inner), inlet(dac));

    sync();

    final copy = inside(Obj.patcher);
    expect(parent.nodesIn(copy).map((n) => n.type).toSet(), {
      Obj.dSine,
      Obj.dOutlet,
    });
    expect(parent.graph.nodeById(copy)!.outputs, hasLength(1));
    expect(parent.graph.cables, hasLength(2));

    definition.applyParams(sine, '330');
    sync();
    final copiedSine = parent
        .nodesIn(copy)
        .firstWhere((n) => n.type == Obj.dSine);
    expect(parent.argsOf(copiedSine.id), '330');
  });

  test('a box copied out into a top level keeps its layout and wiring', () {
    final held = make(parent, Obj.dSine, args: '220', inside: box);
    final pin = make(parent, Obj.dOutlet, args: '0', inside: box);
    parent.connectViaGesture(outlet(held), inlet(pin));

    PatchInstanceMaterialiser(
      source: parent,
      sourceScope: box,
      target: definition,
      targetScope: null,
    ).run();

    expect(definition.graph.nodes.map((n) => n.type).toSet(), {
      Obj.dSine,
      Obj.dOutlet,
    });
    expect(definition.graph.cables, hasLength(1));
  });
}
