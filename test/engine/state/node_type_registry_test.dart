import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

NodeDescriptor _desc(String type) => NodeDescriptor(
  type: type,
  title: 'demo',
  defaultSize: const Size(120, 60),
  defaultArgs: '',
  inputs: const [],
  outputs: const [],
  buildBody: (ctx, node, controller) => const SizedBox.shrink(),
);

void main() {
  group('NodeTypeRegistry', () {
    setUp(() => NodeTypeRegistry.instance.clear());
    tearDown(() => NodeTypeRegistry.instance.clear());

    test('register + find round-trip', () {
      final d = _desc('~demo');
      NodeTypeRegistry.instance.register(d);

      expect(NodeTypeRegistry.instance.find('~demo'), same(d));
      expect(NodeTypeRegistry.instance.find('?missing'), isNull);
    });

    test('register overwrites a previous entry of the same type', () {
      final a = _desc('~demo');
      final b = _desc('~demo');
      NodeTypeRegistry.instance.register(a);
      NodeTypeRegistry.instance.register(b);

      expect(NodeTypeRegistry.instance.find('~demo'), same(b));
      expect(NodeTypeRegistry.instance.all, hasLength(1));
    });

    test('registerBuiltInPatcherNodes populates sine, slider, dac', () {
      registerBuiltInPatcherNodes();

      final sine = NodeTypeRegistry.instance.find(Obj.dSine);
      final slider = NodeTypeRegistry.instance.find(Obj.gSlider);
      final dac = NodeTypeRegistry.instance.find(Obj.dDac);

      expect(sine, isNotNull);
      expect(slider, isNotNull);
      expect(dac, isNotNull);
      expect(sine!.outputs.single.kind, PatchPortKind.audio);
      expect(slider!.outputs.single.kind, PatchPortKind.control);
      expect(dac!.inputs, hasLength(2));
    });
  });
}
