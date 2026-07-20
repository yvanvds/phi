import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/shell_layout/drop_edge.dart';
import 'package:phi/domain/shell_layout/layout_node.dart';
import 'package:phi/domain/shell_layout/shell_layout.dart';
import 'package:phi/domain/shell_layout/split_axis.dart';
import 'package:phi/shell/layout/pane_dock_zones.dart';
import 'package:phi/shell/layout/pane_tab_strip.dart';
import 'package:phi/shell/layout/shell_layout_controller.dart';
import 'package:phi/shell/layout/split_tree_view.dart';
import 'package:phi/shell/layout/splitter_resize.dart';
import 'package:phi/shell/layout/workstation_pane.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

/// Widget tests for the tab + split interactions (issue #252): tab select /
/// close / reorder, every drag-to-dock zone (edge splits + centre join), an
/// invalid drop snapping back, splitter resize + minima, narrow-pane overflow,
/// and the visible focus marker. These exercise the real [WorkstationPane] /
/// [SplitTreeView] composition against a live [ShellLayoutController], so the
/// interaction → domain wiring is covered end to end below the app.
void main() {
  /// A single-pane layout with the given [tabs] (first is active).
  ShellLayoutController onePane(List<String> tabs) => ShellLayoutController(
    layout: ShellLayout(
      root: LayoutPane(id: 'p1', tabs: tabs, active: tabs.first),
    ),
    activePaneId: 'p1',
  );

  /// A two-pane row: p1 holds [left], p2 holds [right]; p1 active.
  ShellLayoutController twoPanes(String left, String right) =>
      ShellLayoutController(
        layout: ShellLayout(
          root: LayoutSplit(
            id: 's1',
            axis: SplitAxis.row,
            children: [
              LayoutPane(id: 'p1', tabs: [left], active: left),
              LayoutPane(id: 'p2', tabs: [right], active: right),
            ],
            fractions: const [0.5, 0.5],
          ),
        ),
        activePaneId: 'p1',
      );

  Widget harness(
    ShellLayoutController controller, {
    Size size = const Size(800, 600),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: size,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => SplitTreeView(
                root: controller.layout.root,
                onResize: (splitId, i, delta) {
                  final node = controller.layout.nodeById(splitId);
                  if (node is LayoutSplit) {
                    controller.resize(
                      splitId,
                      resizeSiblings(
                        fractions: node.fractions,
                        leadingIndex: i,
                        deltaFraction: delta,
                      ),
                    );
                  }
                },
                buildPane: (pane) => WorkstationPane(
                  pane: pane,
                  isActivePane: pane.id == controller.activePaneId,
                  controller: controller,
                  contentFor: (id, {required active}) => ColoredBox(
                    color: const Color(0xFF101010),
                    child: Center(child: Text('content-$id')),
                  ),
                  labelFor: (id) => id,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Drags the tab keyed [from] onto the target keyed [to] and releases.
  Future<void> dragTab(WidgetTester tester, Key from, Key to) async {
    final start = tester.getCenter(find.byKey(from));
    final end = tester.getCenter(find.byKey(to));
    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  LayoutSplit rootSplit(ShellLayoutController c) =>
      c.layout.root as LayoutSplit;
  List<String> tabsOf(LayoutNode node) => (node as LayoutPane).tabs;

  group('tab strip', () {
    testWidgets('tapping a tab selects it and focuses the pane', (
      tester,
    ) async {
      final controller = onePane(['mix', 'midi']);
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      expect(controller.focusedSurface, 'mix');
      await tester.tap(find.text('midi'));
      await tester.pumpAndSettle();

      expect(controller.focusedSurface, 'midi');
    });

    testWidgets('closing a tab removes it; summon brings it back', (
      tester,
    ) async {
      final controller = onePane(['mix', 'midi']);
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await tester.tap(find.byKey(PaneTabStrip.closeKey('p1', 'midi')));
      await tester.pumpAndSettle();
      expect(controller.layout.placedSurfaces, {'mix'});
      expect(find.byKey(PaneTabStrip.tabKey('p1', 'midi')), findsNothing);

      // Summon it back (the rail's mechanism) — the chip returns.
      controller.summon('midi');
      await tester.pumpAndSettle();
      expect(find.byKey(PaneTabStrip.tabKey('p1', 'midi')), findsOneWidget);
    });

    testWidgets('dragging a tab onto another reorders within the pane', (
      tester,
    ) async {
      final controller = onePane(['mix', 'midi', 'racks']);
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      // Drop 'mix' onto 'racks' → it lands just before racks.
      await dragTab(
        tester,
        PaneTabStrip.tabKey('p1', 'mix'),
        PaneTabStrip.tabKey('p1', 'racks'),
      );

      expect(controller.layout.paneById('p1')!.tabs, ['midi', 'mix', 'racks']);
    });
  });

  group('drag-to-dock zones', () {
    testWidgets('right edge splits into a row, dropped surface on the right', (
      tester,
    ) async {
      final controller = onePane(['mix', 'midi']);
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await dragTab(
        tester,
        PaneTabStrip.tabKey('p1', 'midi'),
        PaneDockZones.edgeZoneKey('p1', DropEdge.right),
      );

      expect(controller.layout.paneCount, 2);
      final split = rootSplit(controller);
      expect(split.axis, SplitAxis.row);
      expect(tabsOf(split.children[0]), ['mix']);
      expect(tabsOf(split.children[1]), ['midi']);
    });

    testWidgets('left edge splits into a row, dropped surface on the left', (
      tester,
    ) async {
      final controller = onePane(['mix', 'midi']);
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await dragTab(
        tester,
        PaneTabStrip.tabKey('p1', 'midi'),
        PaneDockZones.edgeZoneKey('p1', DropEdge.left),
      );

      final split = rootSplit(controller);
      expect(split.axis, SplitAxis.row);
      expect(tabsOf(split.children[0]), ['midi']);
      expect(tabsOf(split.children[1]), ['mix']);
    });

    testWidgets('bottom edge splits into a column, surface below', (
      tester,
    ) async {
      final controller = onePane(['mix', 'midi']);
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await dragTab(
        tester,
        PaneTabStrip.tabKey('p1', 'midi'),
        PaneDockZones.edgeZoneKey('p1', DropEdge.bottom),
      );

      final split = rootSplit(controller);
      expect(split.axis, SplitAxis.column);
      expect(tabsOf(split.children[0]), ['mix']);
      expect(tabsOf(split.children[1]), ['midi']);
    });

    testWidgets('top edge splits into a column, surface above', (tester) async {
      final controller = onePane(['mix', 'midi']);
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await dragTab(
        tester,
        PaneTabStrip.tabKey('p1', 'midi'),
        PaneDockZones.edgeZoneKey('p1', DropEdge.top),
      );

      final split = rootSplit(controller);
      expect(split.axis, SplitAxis.column);
      expect(tabsOf(split.children[0]), ['midi']);
      expect(tabsOf(split.children[1]), ['mix']);
    });

    testWidgets('centre joins a tab dragged in from another pane', (
      tester,
    ) async {
      final controller = twoPanes('mix', 'midi');
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      // Drag midi (from p2) onto p1's centre → joined into p1, p2 pruned.
      await dragTab(
        tester,
        PaneTabStrip.tabKey('p2', 'midi'),
        PaneDockZones.centerZoneKey('p1'),
      );

      expect(controller.layout.paneCount, 1);
      expect(controller.layout.paneById('p1')!.tabs, ['mix', 'midi']);
    });

    testWidgets('an invalid drop (sole tab on its own pane) snaps back', (
      tester,
    ) async {
      final controller = onePane(['mix']);
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      // Sole tab dropped on its own edge and centre — the domain no-ops both.
      await dragTab(
        tester,
        PaneTabStrip.tabKey('p1', 'mix'),
        PaneDockZones.edgeZoneKey('p1', DropEdge.right),
      );
      await dragTab(
        tester,
        PaneTabStrip.tabKey('p1', 'mix'),
        PaneDockZones.centerZoneKey('p1'),
      );

      expect(controller.layout.paneCount, 1);
      expect(controller.layout.paneById('p1')!.tabs, ['mix']);
    });
  });

  group('splitter', () {
    testWidgets('dragging the handle resizes the flanking panes', (
      tester,
    ) async {
      final controller = twoPanes('mix', 'midi');
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await tester.drag(
        find.byKey(SplitTreeView.splitterKey('s1', 0)),
        const Offset(120, 0),
      );
      await tester.pumpAndSettle();

      final f = rootSplit(controller).fractions;
      expect(f[0], greaterThan(0.55), reason: 'leading pane grew');
      expect(f[1], lessThan(0.45));
      expect(f[0] + f[1], closeTo(1, 1e-9));
    });

    testWidgets('a hard drag clamps the shrinking pane at the minimum', (
      tester,
    ) async {
      final controller = twoPanes('mix', 'midi');
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      await tester.drag(
        find.byKey(SplitTreeView.splitterKey('s1', 0)),
        const Offset(-2000, 0),
      );
      await tester.pumpAndSettle();

      final f = rootSplit(controller).fractions;
      expect(f[0], closeTo(ShellLayout.minFraction, 1e-9));
      expect(f[1], closeTo(1 - ShellLayout.minFraction, 1e-9));
    });
  });

  group('overflow + focus', () {
    testWidgets('a narrow pane scrolls its tabs instead of overflowing', (
      tester,
    ) async {
      final controller = onePane([for (final s in SurfaceId.values) s.name]);
      addTearDown(controller.dispose);

      await tester.pumpWidget(harness(controller, size: const Size(200, 400)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The strip is horizontally scrollable rather than clipping to fit.
      expect(
        find.descendant(
          of: find.byType(PaneTabStrip),
          matching: find.byType(Scrollable),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the focused pane is visibly marked and follows a click', (
      tester,
    ) async {
      final controller = twoPanes('mix', 'midi');
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(controller));

      // p1 starts focused.
      expect(find.byKey(WorkstationPane.focusRingKey('p1')), findsOneWidget);
      expect(find.byKey(WorkstationPane.focusRingKey('p2')), findsNothing);

      // Click into p2's body → focus follows.
      await tester.tap(find.text('content-midi'));
      await tester.pumpAndSettle();

      expect(controller.activePaneId, 'p2');
      expect(find.byKey(WorkstationPane.focusRingKey('p2')), findsOneWidget);
      expect(find.byKey(WorkstationPane.focusRingKey('p1')), findsNothing);
    });
  });
}
