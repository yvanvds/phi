import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/commands/add_object_command.dart';
import 'package:phi/domain/patcher/commands/connect_command.dart';
import 'package:phi/domain/patcher/commands/delete_object_command.dart';
import 'package:phi/domain/patcher/commands/disconnect_command.dart';
import 'package:phi/domain/patcher/commands/move_node_command.dart';
import 'package:phi/domain/patcher/commands/param_change_command.dart';
import 'package:phi/domain/patcher/patch_connection.dart';
import 'package:phi/domain/patcher/patch_object_spec.dart';
import 'package:phi/domain/patcher/patch_point.dart';
import 'package:phi/domain/project/entity_address.dart';

import 'test_doubles/fake_patch_edit_gateway.dart';

void main() {
  final patch = EntityAddress.parse('patch.swirl');

  late FakePatchEditGateway gateway;

  setUp(() => gateway = FakePatchEditGateway());

  group('AddObjectCommand', () {
    const spec = PatchObjectSpec(type: '~sine', args: '440');

    test('apply creates the object and exposes its id', () {
      final command = AddObjectCommand(gateway, patch, spec);
      command.apply();
      expect(command.objectId, isNotNull);
      expect(gateway.objects[command.objectId!], spec);
    });

    test('revert removes the object again', () {
      final command = AddObjectCommand(gateway, patch, spec)..apply();
      command.revert();
      expect(gateway.objects, isEmpty);
    });

    test('redo restores the object under the same id', () {
      final command = AddObjectCommand(gateway, patch, spec)..apply();
      final id = command.objectId;
      command.revert();
      command.apply();
      expect(command.objectId, id);
      expect(gateway.objects.keys, [id]);
    });

    test('touches the patch entity and serialises', () {
      final command = AddObjectCommand(gateway, patch, spec)..apply();
      expect(command.entitiesTouched, {patch});
      expect(command.toJson(), {
        'type': 'add_object',
        'patch': 'patch.swirl',
        'spec': spec.toJson(),
        'id': command.objectId,
      });
    });
  });

  group('DeleteObjectCommand', () {
    late int sine;
    late int dac;

    setUp(() {
      sine = gateway.createObject(const PatchObjectSpec(type: '~sine'));
      dac = gateway.createObject(const PatchObjectSpec(type: '~dac'));
      gateway.connect(
        PatchConnection(fromId: sine, outlet: 0, toId: dac, inlet: 0),
      );
    });

    test('apply removes the object and its cables', () {
      DeleteObjectCommand(gateway, patch, sine).apply();
      expect(gateway.objects.containsKey(sine), isFalse);
      expect(gateway.cables, isEmpty);
    });

    test('revert restores the object and re-wires its cables', () {
      final before = gateway.objects[sine];
      final command = DeleteObjectCommand(gateway, patch, sine)..apply();
      command.revert();
      expect(gateway.objects[sine], before);
      expect(gateway.cables, [
        PatchConnection(fromId: sine, outlet: 0, toId: dac, inlet: 0),
      ]);
    });

    test('serialises to just the id (a forward replay only needs it)', () {
      expect(DeleteObjectCommand(gateway, patch, sine).toJson(), {
        'type': 'delete_object',
        'patch': 'patch.swirl',
        'id': sine,
      });
    });
  });

  group('ConnectCommand / DisconnectCommand', () {
    late int a;
    late int b;
    late PatchConnection cable;

    setUp(() {
      a = gateway.createObject(const PatchObjectSpec(type: '~sine'));
      b = gateway.createObject(const PatchObjectSpec(type: '~dac'));
      cable = PatchConnection(fromId: a, outlet: 0, toId: b, inlet: 0);
    });

    test('connect apply wires, revert unwires', () {
      final command = ConnectCommand(gateway, patch, cable)..apply();
      expect(gateway.cables, [cable]);
      command.revert();
      expect(gateway.cables, isEmpty);
    });

    test('disconnect apply unwires, revert re-wires', () {
      gateway.connect(cable);
      final command = DisconnectCommand(gateway, patch, cable)..apply();
      expect(gateway.cables, isEmpty);
      command.revert();
      expect(gateway.cables, [cable]);
    });

    test('connect serialises with the cable fields inlined', () {
      expect(ConnectCommand(gateway, patch, cable).toJson(), {
        'type': 'connect',
        'patch': 'patch.swirl',
        'from': a,
        'outlet': 0,
        'to': b,
        'inlet': 0,
      });
    });
  });

  group('MoveNodeCommand', () {
    late int id;

    setUp(() {
      id = gateway.createObject(
        const PatchObjectSpec(type: '.slider', position: PatchPoint(10, 10)),
      );
    });

    test('apply moves, revert restores the original position', () {
      final command = MoveNodeCommand(
        gateway,
        patch,
        id,
        const PatchPoint(90, 40),
      )..apply();
      expect(gateway.positionOf(id), const PatchPoint(90, 40));
      command.revert();
      expect(gateway.positionOf(id), const PatchPoint(10, 10));
    });

    test('redo returns to the destination without drifting the origin', () {
      final command =
          MoveNodeCommand(gateway, patch, id, const PatchPoint(90, 40))
            ..apply()
            ..revert()
            ..apply();
      expect(gateway.positionOf(id), const PatchPoint(90, 40));
      command.revert();
      expect(gateway.positionOf(id), const PatchPoint(10, 10));
    });

    test('serialises id and destination', () {
      expect(
        MoveNodeCommand(gateway, patch, id, const PatchPoint(90, 40)).toJson(),
        {
          'type': 'move_node',
          'patch': 'patch.swirl',
          'id': id,
          'to': const PatchPoint(90, 40).toJson(),
        },
      );
    });
  });

  group('ParamChangeCommand', () {
    test('apply sets, revert restores a prior value', () {
      final id = gateway.createObject(
        const PatchObjectSpec(type: '~sine', params: {'freq': 220.0}),
      );
      final command = ParamChangeCommand(gateway, patch, id, 'freq', 440.0)
        ..apply();
      expect(gateway.paramOf(id, 'freq'), 440.0);
      command.revert();
      expect(gateway.paramOf(id, 'freq'), 220.0);
    });

    test('revert clears a parameter that had no prior value', () {
      final id = gateway.createObject(const PatchObjectSpec(type: '~sine'));
      final command = ParamChangeCommand(gateway, patch, id, 'gain', 0.8)
        ..apply();
      expect(gateway.paramOf(id, 'gain'), 0.8);
      command.revert();
      expect(gateway.paramOf(id, 'gain'), isNull);
    });

    test('redo re-applies the new value', () {
      final id = gateway.createObject(
        const PatchObjectSpec(type: '~sine', params: {'freq': 220.0}),
      );
      ParamChangeCommand(gateway, patch, id, 'freq', 440.0)
        ..apply()
        ..revert()
        ..apply();
      expect(gateway.paramOf(id, 'freq'), 440.0);
    });

    test('serialises id, name and value', () {
      final id = gateway.createObject(const PatchObjectSpec(type: '~sine'));
      expect(ParamChangeCommand(gateway, patch, id, 'freq', 440.0).toJson(), {
        'type': 'param_change',
        'patch': 'patch.swirl',
        'id': id,
        'name': 'freq',
        'value': 440.0,
      });
    });
  });

  test('a mixed gesture stack undoes LIFO back to the empty baseline', () {
    // add ~sine, add ~dac, connect them, move the sine — then undo everything.
    final add1 = AddObjectCommand(
      gateway,
      patch,
      const PatchObjectSpec(type: '~sine', position: PatchPoint(0, 0)),
    )..apply();
    final add2 = AddObjectCommand(
      gateway,
      patch,
      const PatchObjectSpec(type: '~dac', position: PatchPoint(100, 0)),
    )..apply();
    final cable = PatchConnection(
      fromId: add1.objectId!,
      outlet: 0,
      toId: add2.objectId!,
      inlet: 0,
    );
    final connect = ConnectCommand(gateway, patch, cable)..apply();
    final move = MoveNodeCommand(
      gateway,
      patch,
      add1.objectId!,
      const PatchPoint(20, 20),
    )..apply();

    expect(gateway.objects, hasLength(2));
    expect(gateway.cables, [cable]);
    expect(gateway.positionOf(add1.objectId!), const PatchPoint(20, 20));

    // Undo in strict LIFO order.
    move.revert();
    connect.revert();
    add2.revert();
    add1.revert();

    expect(gateway.objects, isEmpty);
    expect(gateway.cables, isEmpty);
  });
}
