import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

NodeDescriptor _desc(String type, {Size size = const Size(120, 80)}) =>
    NodeDescriptor(
      type: type,
      defaultSize: size,
      defaultArgs: '',
      inputs: const [],
      outputs: const [],
      buildBody: (ctx, node, controller) => const SizedBox.shrink(),
    );

PatchPortId _out(PatchNodeId id, int i) =>
    PatchPortId(nodeId: id, side: PatchPortSide.output, index: i);
PatchPortId _in(PatchNodeId id, int i) =>
    PatchPortId(nodeId: id, side: PatchPortSide.input, index: i);

void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  // slider(out float) → sine(in {buffer,float}, out buffer) → dac(in {buffer}).
  PatchNode addSlider([Offset p = Offset.zero]) =>
      controller.addNode(desc: _desc(Obj.gSlider), position: p);
  PatchNode addSine([Offset p = Offset.zero]) =>
      controller.addNode(desc: _desc(Obj.dSine), position: p);
  PatchNode addDac([Offset p = Offset.zero]) =>
      controller.addNode(desc: _desc(Obj.dDac), position: p);

  group('typed-pin queries', () {
    test('outletTypeOf reads the catalogue OutType', () {
      final slider = addSlider();
      final sine = addSine();
      expect(
        controller.outletTypeOf(_out(slider.id, 0)),
        PatchOutletType.float,
      );
      expect(controller.outletTypeOf(_out(sine.id, 0)), PatchOutletType.buffer);
    });

    test('canConnect accepts a compatible drop', () {
      final slider = addSlider();
      final sine = addSine();
      expect(
        controller.canConnect(_out(slider.id, 0), _in(sine.id, 0)),
        isTrue,
      );
    });

    test(
      'canConnect rejects an incompatible drop (float into a DSP inlet)',
      () {
        final slider = addSlider();
        final dac = addDac();
        expect(
          controller.canConnect(_out(slider.id, 0), _in(dac.id, 0)),
          isFalse,
        );
      },
    );

    test('canConnect rejects a self-wire and a duplicate cable', () {
      final slider = addSlider();
      final sine = addSine();
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));
      // duplicate
      expect(
        controller.canConnect(_out(slider.id, 0), _in(sine.id, 0)),
        isFalse,
      );
      // self-wire (same node both ends)
      expect(controller.canConnect(_out(sine.id, 0), _in(sine.id, 0)), isFalse);
    });
  });

  group('connect gesture', () {
    test('connectViaGesture wires a compatible cable and undoes it', () {
      final slider = addSlider();
      final sine = addSine();

      final ok = controller.connectViaGesture(
        _out(slider.id, 0),
        _in(sine.id, 0),
      );

      expect(ok, isTrue);
      expect(controller.graph.cables, hasLength(1));
      expect(gateway.cables, hasLength(1));

      controller.undo();
      expect(controller.graph.cables, isEmpty);
      expect(gateway.cables, isEmpty);

      controller.redo();
      expect(controller.graph.cables, hasLength(1));
      expect(gateway.cables, hasLength(1));
    });

    test('connectViaGesture refuses an incompatible drop, leaving the graph '
        'untouched', () {
      final slider = addSlider();
      final dac = addDac();

      final ok = controller.connectViaGesture(
        _out(slider.id, 0),
        _in(dac.id, 0),
      );

      expect(ok, isFalse);
      expect(controller.graph.cables, isEmpty);
      expect(controller.undoScope.canUndo, isFalse);
    });
  });

  group('body drag', () {
    test('a drag commits one move command and undoes/redoes as a unit', () {
      final n = addSine(const Offset(40, 60));

      controller.beginNodeDrag(n.id);
      controller.dragSelectedBy(const Offset(10, 5));
      controller.endNodeDrag();

      expect(n.position, const Offset(50, 65));
      expect(controller.undoScope.canUndo, isTrue);

      controller.undo();
      expect(n.position, const Offset(40, 60));

      controller.redo();
      expect(n.position, const Offset(50, 65));
    });

    test('a zero-net drag journals nothing', () {
      final n = addSine(const Offset(40, 60));
      controller.beginNodeDrag(n.id);
      controller.dragSelectedBy(const Offset(10, 0));
      controller.dragSelectedBy(const Offset(-10, 0));
      controller.endNodeDrag();
      expect(controller.undoScope.canUndo, isFalse);
    });

    test(
      'dragging one of several selected nodes moves the whole selection',
      () {
        final a = addSine(const Offset(0, 0));
        final b = addSine(const Offset(100, 0));
        controller.selectNodes({a.id, b.id});

        controller.beginNodeDrag(a.id);
        controller.dragSelectedBy(const Offset(10, 10));
        controller.endNodeDrag();

        expect(a.position, const Offset(10, 10));
        expect(b.position, const Offset(110, 10));

        controller.undo();
        expect(a.position, const Offset(0, 0));
        expect(b.position, const Offset(100, 0));
      },
    );
  });

  // ─── grid snap on drop (issue #368) ──────────────────────────────────────

  group('snap on drop', () {
    test('an unsnapped drop lands exactly where the pointer left it', () {
      final n = addSine(const Offset(40, 60));
      controller.beginNodeDrag(n.id);
      controller.dragSelectedBy(const Offset(7, 3));
      controller.endNodeDrag();
      expect(n.position, const Offset(47, 63));
    });

    test('a snapped drop quantises to the 16px grid, and undo restores the '
        'off-grid origin', () {
      final n = addSine(const Offset(40, 60));
      controller.beginNodeDrag(n.id);
      controller.dragSelectedBy(const Offset(7, 3));
      controller.endNodeDrag(snapToGrid: true);

      // (47, 63) → the nearest cell of the 16px lattice.
      expect(n.position, const Offset(48, 64));

      // The snapped destination is what was journaled: undo goes back to where
      // the drag started, off-grid and all, and redo lands on the grid again.
      controller.undo();
      expect(n.position, const Offset(40, 60));
      controller.redo();
      expect(n.position, const Offset(48, 64));
    });

    test('a snapped multi-node drop shifts the whole selection by one offset, '
        'keeping its arrangement', () {
      final a = addSine(const Offset(40, 60));
      final b = addSine(const Offset(133, 60));
      controller.selectNodes({a.id, b.id});

      controller.beginNodeDrag(a.id);
      controller.dragSelectedBy(const Offset(7, 3));
      controller.endNodeDrag(snapToGrid: true);

      // The anchor (the node under the press) lands on the grid; the other
      // moves by the same offset, so the gap between them is untouched.
      expect(a.position, const Offset(48, 64));
      expect(b.position, const Offset(141, 64));
      expect(b.position - a.position, const Offset(93, 0));
    });

    test('a snap that cancels the drag out still lands the node on the grid, '
        'journaling nothing', () {
      final n = addSine(const Offset(48, 64));
      controller.beginNodeDrag(n.id);
      controller.dragSelectedBy(const Offset(3, 2));
      controller.endNodeDrag(snapToGrid: true);

      // Net zero after snapping — the node is back on its cell and no step was
      // pushed, but it must not be left on the half-pixel the preview drew.
      expect(n.position, const Offset(48, 64));
      expect(controller.undoScope.canUndo, isFalse);
    });
  });

  // ─── keyboard nudge machinery (issue #368) ───────────────────────────────

  group('selection move', () {
    test('beginSelectionMove captures the selection with no node under a '
        'pointer, and one commit journals the whole run', () {
      final a = addSine(const Offset(40, 60));
      final b = addSine(const Offset(100, 60));
      controller.selectNodes({a.id, b.id});

      controller.beginSelectionMove();
      expect(controller.isMovingNodes, isTrue);
      controller.dragSelectedBy(const Offset(16, 0));
      controller.dragSelectedBy(const Offset(16, 0));
      controller.endNodeDrag();

      expect(a.position, const Offset(72, 60));
      expect(b.position, const Offset(132, 60));

      // One step for the whole run, not one per move.
      controller.undo();
      expect(a.position, const Offset(40, 60));
      expect(b.position, const Offset(100, 60));
      expect(controller.undoScope.canUndo, isFalse);
    });

    test(
      'beginSelectionMove with nothing selected moves and journals nothing',
      () {
        final n = addSine(const Offset(40, 60));
        controller.clearSelection();

        controller.beginSelectionMove();
        expect(controller.isMovingNodes, isFalse);
        controller.dragSelectedBy(const Offset(16, 0));
        controller.endNodeDrag();

        expect(n.position, const Offset(40, 60));
        expect(controller.undoScope.canUndo, isFalse);
      },
    );
  });

  // ─── aborted body drag (issue #355) ──────────────────────────────────────

  group('abort body drag', () {
    test(
      'abortNodeDrag restores the pre-drag position and journals nothing',
      () {
        final n = addSine(const Offset(40, 60));

        controller.beginNodeDrag(n.id);
        controller.dragSelectedBy(const Offset(10, 5));
        expect(n.position, const Offset(50, 65)); // the live preview moved
        controller.abortNodeDrag();

        // The gesture never happened: the node is back, the stack is untouched.
        expect(n.position, const Offset(40, 60));
        expect(controller.undoScope.canUndo, isFalse);
      },
    );

    test('abortNodeDrag restores every node of a multi-node drag', () {
      final a = addSine(const Offset(0, 0));
      final b = addSine(const Offset(100, 0));
      controller.selectNodes({a.id, b.id});

      controller.beginNodeDrag(a.id);
      controller.dragSelectedBy(const Offset(30, 20));
      controller.abortNodeDrag();

      expect(a.position, const Offset(0, 0));
      expect(b.position, const Offset(100, 0));
      expect(controller.undoScope.canUndo, isFalse);
    });

    test('a drag after an aborted one commits normally', () {
      final n = addSine(const Offset(40, 60));

      controller.beginNodeDrag(n.id);
      controller.dragSelectedBy(const Offset(90, 90));
      controller.abortNodeDrag();

      // No origins leaked from the abandoned gesture: the next drag journals
      // its own move only, and undo lands on the *aborted* gesture's start.
      controller.beginNodeDrag(n.id);
      controller.dragSelectedBy(const Offset(10, 5));
      controller.endNodeDrag();

      expect(n.position, const Offset(50, 65));
      controller.undo();
      expect(n.position, const Offset(40, 60));
      expect(controller.undoScope.canUndo, isFalse);
    });

    test('abortNodeDrag with no drag in flight is a no-op', () {
      final n = addSine(const Offset(40, 60));
      controller.abortNodeDrag();
      expect(n.position, const Offset(40, 60));
      expect(controller.undoScope.canUndo, isFalse);
    });
  });

  group('cable delete', () {
    test('deleting a selected cable removes it and undoes it', () {
      final slider = addSlider();
      final sine = addSine();
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));
      final cable = controller.graph.cables.single;

      controller.selectCable(cable);
      controller.deleteSelection();

      expect(controller.graph.cables, isEmpty);
      expect(gateway.cables, isEmpty);

      controller.undo();
      expect(controller.graph.cables, hasLength(1));
      expect(gateway.cables, hasLength(1));
    });
  });

  group('delete nodes with cables', () {
    test('deletes the selected nodes and their cables, then restores both', () {
      final slider = addSlider();
      final sine = addSine();
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));

      controller.selectNodes({slider.id, sine.id});
      controller.deleteSelection();

      expect(controller.graph.nodes, isEmpty);
      expect(controller.graph.cables, isEmpty);
      expect(gateway.nodes, isEmpty);
      expect(gateway.cables, isEmpty);

      controller.undo();

      expect(controller.graph.nodes, hasLength(2));
      expect(controller.graph.cables, hasLength(1));
      expect(gateway.cables, hasLength(1));
      // Restored under the same logical ids, so the cable re-wired correctly.
      expect(controller.graph.nodeById(slider.id), isNotNull);
      expect(controller.graph.nodeById(sine.id), isNotNull);
    });

    test('delete of a partial selection drops only the incident cable', () {
      final slider = addSlider();
      final sine = addSine();
      final dac = addDac();
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));
      controller.connectViaGesture(_out(sine.id, 0), _in(dac.id, 0));
      expect(controller.graph.cables, hasLength(2));

      controller.selectNodes({dac.id});
      controller.deleteSelection();

      expect(controller.graph.nodes, hasLength(2));
      expect(controller.graph.cables, hasLength(1)); // slider→sine survives

      controller.undo();
      expect(controller.graph.nodes, hasLength(3));
      expect(controller.graph.cables, hasLength(2));
    });
  });

  group('duplicate', () {
    test('duplicates nodes + intra-selection cables offset a grid step', () {
      final slider = addSlider(const Offset(0, 0));
      final sine = addSine(const Offset(100, 0));
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));

      controller.selectNodes({slider.id, sine.id});
      controller.duplicateSelection();

      expect(controller.graph.nodes, hasLength(4));
      expect(controller.graph.cables, hasLength(2));
      // The duplicates are now the selection, offset one grid step (16px).
      expect(controller.graph.selectedNodes, hasLength(2));
      final dupes = controller.graph.nodes
          .where((n) => !{slider.id, sine.id}.contains(n.id))
          .toList();
      expect(dupes.map((n) => n.position), <Offset>{
        const Offset(16, 16),
        const Offset(116, 16),
      });

      controller.undo();
      expect(controller.graph.nodes, hasLength(2));
      expect(controller.graph.cables, hasLength(1));

      controller.redo();
      expect(controller.graph.nodes, hasLength(4));
      expect(controller.graph.cables, hasLength(2));
    });

    test('a cable with only one endpoint selected is not duplicated', () {
      final slider = addSlider();
      final sine = addSine(const Offset(100, 0));
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));

      controller.selectNodes({sine.id}); // only the target end
      controller.duplicateSelection();

      expect(controller.graph.nodes, hasLength(3)); // one copy of sine
      expect(controller.graph.cables, hasLength(1)); // no new cable
    });
  });

  group('copy/paste (issue #435)', () {
    test('paste recreates nodes + intra-selection cables one grid step '
        'down-right, selected, and undo/redo walk it as one step', () {
      final slider = addSlider(const Offset(0, 0));
      final sine = addSine(const Offset(100, 0));
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));

      controller.selectNodes({slider.id, sine.id});
      controller.copySelection();
      // Copying is not an edit: nothing on the graph moved. (That it journals
      // nothing is proved below — the first undo removes the *paste*, and the
      // no-op-paste case asserts an empty stack outright.)
      expect(controller.graph.nodes, hasLength(2));

      controller.pasteClipboard();
      expect(controller.graph.nodes, hasLength(4));
      expect(controller.graph.cables, hasLength(2));
      expect(controller.graph.selectedNodes, hasLength(2));
      final pasted = controller.graph.nodes
          .where((n) => !{slider.id, sine.id}.contains(n.id))
          .toList();
      expect(pasted.map((n) => n.position), <Offset>{
        const Offset(16, 16),
        const Offset(116, 16),
      });
      // The pasted set is the selection, ready to drag.
      expect(controller.graph.selectedNodes, pasted.map((n) => n.id).toSet());

      controller.undo();
      expect(controller.graph.nodes, hasLength(2));
      expect(controller.graph.cables, hasLength(1));

      controller.redo();
      expect(controller.graph.nodes, hasLength(4));
      expect(controller.graph.cables, hasLength(2));
    });

    test(
      'each repeated paste of the same copy lands one grid step further',
      () {
        final sine = addSine(const Offset(0, 0));
        controller.selectNodes({sine.id});
        controller.copySelection();

        controller.pasteClipboard();
        controller.pasteClipboard();

        final positions = controller.graph.nodes.map((n) => n.position).toSet();
        expect(positions, {
          const Offset(0, 0),
          const Offset(16, 16),
          const Offset(32, 32),
        });
        // A fresh copy resets the generation, so its first paste is one step.
        controller.selectNodes({sine.id});
        controller.copySelection();
        controller.pasteClipboard();
        expect(controller.graph.nodes, hasLength(4));
        expect(
          controller.graph.nodes.where(
            (n) => n.position == const Offset(16, 16),
          ),
          hasLength(2),
        );
      },
    );

    test('the copy is self-contained: it pastes after the originals are '
        'deleted', () {
      final slider = addSlider(const Offset(0, 0));
      final sine = addSine(const Offset(100, 0));
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));

      controller.selectNodes({slider.id, sine.id});
      controller.copySelection();
      controller.deleteSelection();
      expect(controller.graph.nodes, isEmpty);

      controller.pasteClipboard();
      expect(controller.graph.nodes, hasLength(2));
      expect(controller.graph.cables, hasLength(1));
    });

    test('a cable with only one endpoint selected is not copied', () {
      final slider = addSlider();
      final sine = addSine(const Offset(100, 0));
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));

      controller.selectNodes({sine.id});
      controller.copySelection();
      controller.pasteClipboard();

      expect(controller.graph.nodes, hasLength(3)); // one copy of sine
      expect(controller.graph.cables, hasLength(1)); // no new cable
    });

    test('copy with an empty selection keeps the previous copy; paste with an '
        'empty clipboard is a no-op', () {
      // Nothing copied yet: paste does nothing, journals nothing.
      controller.pasteClipboard();
      expect(controller.graph.nodes, isEmpty);
      expect(controller.undoScope.canUndo, isFalse);

      final sine = addSine(const Offset(0, 0));
      controller.selectNodes({sine.id});
      controller.copySelection();
      controller.clearSelection();
      controller.copySelection(); // empty selection — must not clobber
      controller.pasteClipboard();
      expect(controller.graph.nodes, hasLength(2));
    });

    test('a shared clipboard pastes a fragment copied in another patch', () {
      final other = PatcherController(gateway, clipboard: controller.clipboard);
      addTearDown(other.dispose);

      final slider = addSlider(const Offset(0, 0));
      final sine = addSine(const Offset(100, 0));
      controller.connectViaGesture(_out(slider.id, 0), _in(sine.id, 0));
      controller.selectNodes({slider.id, sine.id});
      controller.copySelection();

      other.pasteClipboard();
      expect(other.graph.nodes, hasLength(2));
      expect(other.graph.cables, hasLength(1));
      expect(other.graph.selectedNodes, hasLength(2));
      // The source patch is untouched.
      expect(controller.graph.nodes, hasLength(2));
    });
  });

  group('logical id stability across delete/undo', () {
    test('a move journaled before a delete still undoes after the node is '
        'restored', () {
      final n = addSine(const Offset(0, 0));

      // 1) move
      controller.beginNodeDrag(n.id);
      controller.dragSelectedBy(const Offset(100, 0));
      controller.endNodeDrag();
      expect(n.position, const Offset(100, 0));

      // 2) delete
      controller.selectNodes({n.id});
      controller.deleteSelection();
      expect(controller.graph.nodeById(n.id), isNull);

      // 3) undo delete → node returns under its ORIGINAL id at (100, 0)
      controller.undo();
      final restored = controller.graph.nodeById(n.id);
      expect(restored, isNotNull);
      expect(restored!.position, const Offset(100, 0));

      // 4) undo move → the move command still resolves n.id (now bound to a
      // fresh native handle), so it moves the restored node back to origin.
      controller.undo();
      expect(controller.graph.nodeById(n.id)!.position, const Offset(0, 0));
    });
  });

  group('backward-compatible primitives', () {
    test('permissive connect still wires across kinds', () {
      // Regression guard: the low-level connect must stay permissive for the
      // seed, even where canConnect (typed) would refuse.
      final slider = addSlider();
      final dac = addDac();
      expect(
        controller.canConnect(_out(slider.id, 0), _in(dac.id, 0)),
        isFalse,
      );
      final ok = controller.connect(_out(slider.id, 0), _in(dac.id, 0));
      expect(ok, isTrue);
      expect(controller.graph.cables, hasLength(1));
    });
  });
}
