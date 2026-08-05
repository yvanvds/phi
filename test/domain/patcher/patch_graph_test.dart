import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_cable.dart';
import 'package:phi/domain/patcher/patch_graph.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';

PatchNode _node(
  int id, {
  List<PatchPort> inputs = const [],
  List<PatchPort> outputs = const [],
}) => PatchNode(
  id: PatchNodeId(id),
  type: '~sine',
  voice: 1,
  position: Offset.zero,
  size: const Size(130, 70),
  inputs: inputs,
  outputs: outputs,
);

PatchPortId _out(int nodeId, int index) => PatchPortId(
  nodeId: PatchNodeId(nodeId),
  side: PatchPortSide.output,
  index: index,
);

PatchPortId _in(int nodeId, int index) => PatchPortId(
  nodeId: PatchNodeId(nodeId),
  side: PatchPortSide.input,
  index: index,
);

void main() {
  group('PatchGraph', () {
    test('addNode appends and bumps version + notifies', () {
      final g = PatchGraph();
      var ticks = 0;
      g.addListener(() => ticks++);
      final v0 = g.version;

      g.addNode(_node(1));

      expect(g.nodes, hasLength(1));
      expect(g.version, greaterThan(v0));
      expect(ticks, 1);
    });

    test('removeNode also removes touching cables', () {
      final g = PatchGraph();
      g.addNode(
        _node(
          1,
          outputs: [
            const PatchPort(
              index: 0,
              side: PatchPortSide.output,
              kind: PatchPortKind.audio,
              voice: 1,
            ),
          ],
        ),
      );
      g.addNode(
        _node(
          2,
          inputs: [
            const PatchPort(
              index: 0,
              side: PatchPortSide.input,
              kind: PatchPortKind.audio,
              voice: 1,
            ),
          ],
        ),
      );
      g.addCable(
        PatchCable(
          source: _out(1, 0),
          target: _in(2, 0),
          kind: PatchPortKind.audio,
        ),
      );
      expect(g.cables, hasLength(1));

      g.removeNode(const PatchNodeId(1));

      expect(g.nodes, hasLength(1));
      expect(g.cables, isEmpty);
    });

    test('removeNode on a missing id is a no-op and does not notify', () {
      final g = PatchGraph();
      g.addNode(_node(1));
      final v0 = g.version;
      var ticks = 0;
      g.addListener(() => ticks++);

      g.removeNode(const PatchNodeId(999));

      expect(g.version, v0);
      expect(ticks, 0);
    });

    test('addCable / removeCable notify and bump version', () {
      final g = PatchGraph();
      final cable = PatchCable(
        source: _out(1, 0),
        target: _in(2, 0),
        kind: PatchPortKind.audio,
      );
      var ticks = 0;
      g.addListener(() => ticks++);

      g.addCable(cable);
      g.removeCable(cable);

      expect(g.cables, isEmpty);
      expect(ticks, 2);
    });

    test('beginCableDrag / endCableDrag toggle the drag-source port', () {
      final g = PatchGraph();
      final src = _out(1, 0);
      g.beginCableDrag(src);
      expect(g.dragSourcePort, src);
      g.endCableDrag();
      expect(g.dragSourcePort, isNull);
    });
  });

  group('PatchGraph selection', () {
    test('selectNodes replaces the set and clears a cable selection', () {
      final g = PatchGraph();
      final cable = PatchCable(
        source: _out(1, 0),
        target: _in(2, 0),
        kind: PatchPortKind.audio,
      );
      g.selectCable(cable);
      expect(g.selectedCable, cable);

      g.selectNodes({const PatchNodeId(1), const PatchNodeId(2)});

      expect(g.selectedNodes, {const PatchNodeId(1), const PatchNodeId(2)});
      expect(g.selectedCable, isNull);
      expect(g.isNodeSelected(const PatchNodeId(1)), isTrue);
    });

    test('toggleNode adds then removes one node', () {
      final g = PatchGraph();
      g.toggleNode(const PatchNodeId(3));
      expect(g.selectedNodes, {const PatchNodeId(3)});
      g.toggleNode(const PatchNodeId(3));
      expect(g.selectedNodes, isEmpty);
    });

    test('selectCable clears node selection', () {
      final g = PatchGraph();
      g.selectNodes({const PatchNodeId(1)});
      final cable = PatchCable(
        source: _out(1, 0),
        target: _in(2, 0),
        kind: PatchPortKind.control,
      );
      g.selectCable(cable);
      expect(g.selectedNodes, isEmpty);
      expect(g.selectedCable, cable);
    });

    test('removeNode prunes a selected node and a cable that touched it', () {
      final g = PatchGraph();
      g.addNode(_node(1));
      g.selectNodes({const PatchNodeId(1)});
      final cable = PatchCable(
        source: _out(1, 0),
        target: _in(2, 0),
        kind: PatchPortKind.audio,
      );
      g.addCable(cable);
      g.selectCable(cable); // clears node selection
      g.selectNodes({const PatchNodeId(1)}); // reselect the node

      g.removeNode(const PatchNodeId(1));

      expect(g.isNodeSelected(const PatchNodeId(1)), isFalse);
      expect(g.selectedCable, isNull);
    });

    test('clearSelection empties both node and cable selection', () {
      final g = PatchGraph();
      g.selectNodes({const PatchNodeId(1)});
      g.clearSelection();
      expect(g.selectedNodes, isEmpty);
      expect(g.selectedCable, isNull);
    });
  });

  group('PatchPortId', () {
    test('value equality + hashCode', () {
      const a = PatchPortId(
        nodeId: PatchNodeId(5),
        side: PatchPortSide.input,
        index: 1,
      );
      const b = PatchPortId(
        nodeId: PatchNodeId(5),
        side: PatchPortSide.input,
        index: 1,
      );
      const c = PatchPortId(
        nodeId: PatchNodeId(5),
        side: PatchPortSide.output,
        index: 1,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('PatchNode', () {
    test('moveTo notifies only when position actually changes', () {
      final n = _node(1);
      var ticks = 0;
      n.addListener(() => ticks++);

      n.moveTo(const Offset(50, 50));
      n.moveTo(const Offset(50, 50));

      expect(n.position, const Offset(50, 50));
      expect(ticks, 1);
    });

    test('setArmed notifies only on toggle', () {
      final n = _node(1);
      var ticks = 0;
      n.addListener(() => ticks++);

      n.setArmed(true);
      n.setArmed(true);
      n.setArmed(false);

      expect(ticks, 2);
    });
  });
}
