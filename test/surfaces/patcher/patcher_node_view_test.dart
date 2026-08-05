import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';

/// Where a node's ports sit (issue #377): inlets along the **top** edge,
/// outlets along the **bottom** one, spread horizontally — so a port count sets
/// a node's minimum *width* instead of its height, which is what makes a
/// one-line object box possible at all (design §6, §12.1).
void main() {
  PatchPort port(int index, PatchPortSide side) => PatchPort(
    index: index,
    side: side,
    kind: PatchPortKind.control,
    voice: 1,
  );

  PatchNode node({
    required int inputs,
    required int outputs,
    Offset position = const Offset(100, 200),
    Size size = const Size(160, 64),
  }) => PatchNode(
    id: const PatchNodeId(7),
    type: '.fan',
    voice: 1,
    position: position,
    size: size,
    inputs: [for (var i = 0; i < inputs; i++) port(i, PatchPortSide.input)],
    outputs: [for (var i = 0; i < outputs; i++) port(i, PatchPortSide.output)],
  );

  PatchPortId inp(PatchNode n, int i) =>
      PatchPortId(nodeId: n.id, side: PatchPortSide.input, index: i);
  PatchPortId out(PatchNode n, int i) =>
      PatchPortId(nodeId: n.id, side: PatchPortSide.output, index: i);

  group('portPositionsFor', () {
    test('inlets run along the top edge, spread from the left', () {
      final n = node(inputs: 3, outputs: 0);
      final positions = portPositionsFor(n);

      for (var i = 0; i < 3; i++) {
        expect(
          positions[inp(n, i)],
          Offset(
            n.position.dx +
                PatchCanvasConstants.firstPortOffset +
                i * PatchCanvasConstants.portSpacing,
            n.position.dy,
          ),
          reason: 'inlet $i sits on the top edge',
        );
      }
    });

    test('outlets run along the bottom edge, at the same offsets', () {
      final n = node(inputs: 0, outputs: 2);
      final positions = portPositionsFor(n);

      for (var i = 0; i < 2; i++) {
        expect(
          positions[out(n, i)],
          Offset(
            n.position.dx + patchPortOffsetAlongEdge(i),
            n.position.dy + n.size.height,
          ),
        );
      }
    });

    test('a wider box does not move its ports — only its own edges', () {
      final narrow = node(inputs: 2, outputs: 2, size: const Size(120, 64));
      final wide = node(inputs: 2, outputs: 2, size: const Size(400, 64));

      // The spread is a fixed pitch from the left, not a distribution across
      // the width: retyping a box wider must not drag its cables sideways.
      expect(
        portPositionsFor(narrow)[inp(narrow, 1)],
        portPositionsFor(wide)[inp(wide, 1)],
      );
      // Only the outlets follow the box, and only downward with its height.
      expect(
        portPositionsFor(narrow)[out(narrow, 1)]!.dx,
        portPositionsFor(wide)[out(wide, 1)]!.dx,
      );
    });

    test('every port of a node with the maximum ports its width seats stays '
        'inside that width', () {
      const count = 4;
      final n = node(
        inputs: count,
        outputs: count,
        position: Offset.zero,
        size: Size(PatchCanvasConstants.minWidthForPorts(count), 64),
      );
      final positions = portPositionsFor(n);

      expect(positions[inp(n, count - 1)]!.dx, lessThan(n.size.width));
      expect(
        positions[inp(n, count - 1)]!.dx,
        n.size.width - PatchCanvasConstants.firstPortOffset,
      );
    });
  });

  group('PatchCanvasConstants.minWidthForPorts', () {
    test('a portless or single-port box needs only its two margins', () {
      expect(
        PatchCanvasConstants.minWidthForPorts(0),
        2 * PatchCanvasConstants.firstPortOffset,
      );
      expect(
        PatchCanvasConstants.minWidthForPorts(1),
        2 * PatchCanvasConstants.firstPortOffset,
      );
    });

    test('each further port costs one spacing', () {
      expect(
        PatchCanvasConstants.minWidthForPorts(4) -
            PatchCanvasConstants.minWidthForPorts(3),
        PatchCanvasConstants.portSpacing,
      );
    });
  });
}
