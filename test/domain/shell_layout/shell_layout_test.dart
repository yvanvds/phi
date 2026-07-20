import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/shell_layout/drop_edge.dart';
import 'package:phi/domain/shell_layout/layout_node.dart';
import 'package:phi/domain/shell_layout/shell_layout.dart';
import 'package:phi/domain/shell_layout/split_axis.dart';

/// Asserts every structural invariant the layout promises (design §2): live
/// fractions, single-instance surfaces, a live active tab, unique ids and at
/// least one pane (empty only when it is the sole pane).
void expectValidLayout(ShellLayout layout) {
  expect(
    layout.paneCount,
    greaterThanOrEqualTo(1),
    reason: 'at least one pane',
  );

  final surfaces = <String>[];
  final ids = <String>{};

  void walk(LayoutNode node) {
    expect(node.id, isNotEmpty, reason: 'ids are non-empty');
    expect(ids.add(node.id), isTrue, reason: 'ids are unique (${node.id})');
    switch (node) {
      case LayoutPane():
        surfaces.addAll(node.tabs);
        if (node.tabs.isEmpty) {
          expect(node.active, isNull, reason: 'empty pane has no active tab');
        } else {
          expect(node.tabs, contains(node.active), reason: 'active is live');
        }
      case LayoutSplit():
        expect(
          node.children.length,
          greaterThanOrEqualTo(2),
          reason: 'a split has at least two children',
        );
        expect(node.fractions.length, node.children.length);
        final sum = node.fractions.fold<double>(0, (a, f) => a + f);
        expect(sum, closeTo(1, 1e-9), reason: 'fractions sum to 1');
        for (final f in node.fractions) {
          expect(f, greaterThan(0), reason: 'fractions are positive');
        }
        node.children.forEach(walk);
    }
  }

  walk(layout.root);
  expect(
    surfaces.toSet().length,
    surfaces.length,
    reason: 'each surface appears at most once',
  );
  final hasEmptyPane = layout.panes.any((p) => p.tabs.isEmpty);
  if (hasEmptyPane) {
    expect(layout.paneCount, 1, reason: 'an empty pane is only ever the last');
  }
}

void main() {
  group('seed', () {
    test('is one pane holding Mix', () {
      final layout = ShellLayout.seed();
      expectValidLayout(layout);
      expect(layout.paneCount, 1);
      expect(layout.root, isA<LayoutPane>());
      expect(layout.placedSurfaces, {'mix'});
      expect((layout.root as LayoutPane).active, 'mix');
    });

    test('takes an override surface id', () {
      expect(ShellLayout.seed('scene').placedSurfaces, {'scene'});
    });
  });

  group('split', () {
    test('a right drop wraps the pane in a row, new pane after', () {
      final layout = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      expectValidLayout(layout);
      final root = layout.root as LayoutSplit;
      expect(root.axis, SplitAxis.row);
      expect(root.fractions, [0.5, 0.5]);
      expect((root.children.first as LayoutPane).tabs, ['mix']);
      expect((root.children.last as LayoutPane).tabs, ['midi']);
    });

    test('a left drop puts the new pane before the target', () {
      final layout = ShellLayout.seed().split('p1', 'midi', DropEdge.left);
      final root = layout.root as LayoutSplit;
      expect((root.children.first as LayoutPane).tabs, ['midi']);
      expect((root.children.last as LayoutPane).tabs, ['mix']);
    });

    test('a bottom drop splits along a column', () {
      final layout = ShellLayout.seed().split('p1', 'midi', DropEdge.bottom);
      expect((layout.root as LayoutSplit).axis, SplitAxis.column);
    });

    test('splitting into a same-axis parent extends the row (n-ary)', () {
      var layout = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      final secondPaneId = (layout.root as LayoutSplit).children.last.id;
      layout = layout.split(secondPaneId, 'scene', DropEdge.right);
      expectValidLayout(layout);
      final root = layout.root as LayoutSplit;
      expect(root.children.length, 3, reason: 'one row of three panes');
      expect(root.axis, SplitAxis.row);
      expect(root.fractions.fold<double>(0, (a, f) => a + f), closeTo(1, 1e-9));
    });

    test('moves the surface out of its old pane (single-instance)', () {
      // mix and midi in one row; re-splitting p1 with midi must relocate it,
      // never duplicate it (the emptied midi pane collapses away).
      var layout = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      layout = layout.split('p1', 'midi', DropEdge.bottom);
      expectValidLayout(layout); // the checker asserts single-instance
      expect(layout.placedSurfaces, {'mix', 'midi'});
      expect(layout.paneCount, 2);
      expect((layout.root as LayoutSplit).axis, SplitAxis.column);
      expect(layout.paneIdOf('midi'), isNot(layout.paneIdOf('mix')));
    });

    test('dropping a pane\'s only tab onto itself is a no-op', () {
      final layout = ShellLayout.seed();
      expect(layout.split('p1', 'mix', DropEdge.right), layout);
    });

    test('an unknown target pane is a no-op', () {
      final layout = ShellLayout.seed();
      expect(layout.split('ghost', 'midi', DropEdge.right), layout);
    });
  });

  group('join', () {
    test('appends the surface to the target stack and activates it', () {
      var layout = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      layout = layout.join('p1', 'scene');
      expectValidLayout(layout);
      final pane = layout.paneById('p1')!;
      expect(pane.tabs, ['mix', 'scene']);
      expect(pane.active, 'scene');
    });
  });

  group('moveSurface', () {
    test('into another pane, collapsing the emptied source', () {
      final layout = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      final moved = layout.moveSurface('midi', 'p1');
      expectValidLayout(moved);
      expect(moved.paneCount, 1);
      expect(moved.paneById('p1')!.tabs, ['mix', 'midi']);
    });

    test('at an explicit index within a stack', () {
      final layout = ShellLayout.seed().join('p1', 'midi').join('p1', 'scene');
      final moved = layout.moveSurface('scene', 'p1', atIndex: 0);
      expect(moved.paneById('p1')!.tabs, ['scene', 'mix', 'midi']);
    });
  });

  group('reorderTab', () {
    test('reorders within a pane and keeps the active tab', () {
      final layout = ShellLayout.seed()
          .join('p1', 'midi')
          .join('p1', 'scene')
          .moveSurface('midi', 'p1'); // active is now midi at the end
      final reordered = layout.reorderTab('p1', 0, 2);
      expectValidLayout(reordered);
      expect(reordered.paneById('p1')!.tabs, ['scene', 'midi', 'mix']);
      expect(reordered.paneById('p1')!.active, 'midi');
    });

    test('an out-of-range index is a no-op', () {
      final layout = ShellLayout.seed();
      expect(layout.reorderTab('p1', 5, 0), layout);
    });
  });

  group('close', () {
    test('removes a tab and picks a neighbouring active', () {
      const layout = ShellLayout(
        root: LayoutPane(
          id: 'p1',
          tabs: ['mix', 'midi', 'scene'],
          active: 'midi',
        ),
      );
      final closed = layout.close('midi');
      expectValidLayout(closed);
      expect(closed.paneById('p1')!.tabs, ['mix', 'scene']);
      expect(closed.paneById('p1')!.active, 'scene');
    });

    test('an emptied pane collapses its split (last pane survives)', () {
      final layout = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      final closed = layout.close('midi');
      expectValidLayout(closed);
      expect(closed.paneCount, 1);
      expect(closed.placedSurfaces, {'mix'});
    });

    test('closing the last surface leaves an empty last pane', () {
      final layout = ShellLayout.seed().close('mix');
      expectValidLayout(layout);
      expect(layout.paneCount, 1);
      expect(layout.placedSurfaces, isEmpty);
      expect((layout.root as LayoutPane).active, isNull);
    });

    test('closing an unplaced surface is a no-op', () {
      final layout = ShellLayout.seed();
      expect(layout.close('scene'), layout);
    });
  });

  group('resize', () {
    ShellLayout twoPaneRow() =>
        ShellLayout.seed().split('p1', 'midi', DropEdge.right);

    test('replaces fractions, normalised', () {
      final layout = twoPaneRow();
      final splitId = layout.root.id;
      final resized = layout.resize(splitId, [0.8, 0.2]);
      expectValidLayout(resized);
      expect((resized.root as LayoutSplit).fractions, [0.8, 0.2]);
    });

    test('clamps a near-zero fraction up off the floor', () {
      final layout = twoPaneRow();
      final resized = layout.resize(layout.root.id, [0.98, 0.02]);
      final fractions = (resized.root as LayoutSplit).fractions;
      expect(fractions[1], greaterThan(0.02));
      expect(fractions.fold<double>(0, (a, f) => a + f), closeTo(1, 1e-9));
    });

    test('a length mismatch is a no-op', () {
      final layout = twoPaneRow();
      expect(layout.resize(layout.root.id, [1]), layout);
    });
  });

  group('serialization', () {
    test('round-trips a complex tree exactly', () {
      final layout = ShellLayout.seed()
          .split('p1', 'midi', DropEdge.right)
          .split('p1', 'scene', DropEdge.bottom)
          .join('p1', 'code');
      expectValidLayout(layout);
      expect(ShellLayout.fromJson(layout.toJson()), layout);
    });

    test('round-trips the empty seed-then-closed layout', () {
      final layout = ShellLayout.seed().close('mix');
      expect(ShellLayout.fromJson(layout.toJson()), layout);
    });

    test('carries the schema version', () {
      expect(
        ShellLayout.seed().toJson()['version'],
        ShellLayout.currentVersion,
      );
      expect(
        ShellLayout.fromJson(const {'version': 1, 'root': null}).version,
        1,
      );
    });
  });

  group('fromJson repair (fit fallback of a corrupt section)', () {
    test('a missing root becomes a single empty pane', () {
      final layout = ShellLayout.fromJson(const {'version': 1});
      expectValidLayout(layout);
      expect(layout.paneCount, 1);
      expect(layout.placedSurfaces, isEmpty);
    });

    test('a duplicated surface is dropped from the later pane', () {
      final layout = ShellLayout.fromJson(const {
        'version': 1,
        'root': {
          'type': 'split',
          'id': 's1',
          'axis': 'row',
          'children': [
            {
              'type': 'pane',
              'id': 'p1',
              'tabs': ['mix'],
              'active': 'mix',
            },
            {
              'type': 'pane',
              'id': 'p2',
              'tabs': ['mix', 'midi'],
              'active': 'mix',
            },
          ],
          'fractions': [0.5, 0.5],
        },
      });
      expectValidLayout(layout);
      expect(layout.placedSurfaces, {'mix', 'midi'});
      expect(layout.paneIdOf('mix'), 'p1');
    });

    test('out-of-range fractions are renormalised', () {
      final layout = ShellLayout.fromJson(const {
        'version': 1,
        'root': {
          'type': 'split',
          'id': 's1',
          'axis': 'row',
          'children': [
            {
              'type': 'pane',
              'id': 'p1',
              'tabs': ['mix'],
              'active': 'mix',
            },
            {
              'type': 'pane',
              'id': 'p2',
              'tabs': ['midi'],
              'active': 'midi',
            },
          ],
          'fractions': [7, 7],
        },
      });
      expect((layout.root as LayoutSplit).fractions, [0.5, 0.5]);
    });

    test('duplicate node ids are made unique', () {
      final layout = ShellLayout.fromJson(const {
        'version': 1,
        'root': {
          'type': 'split',
          'id': 'x',
          'axis': 'row',
          'children': [
            {
              'type': 'pane',
              'id': 'x',
              'tabs': ['mix'],
              'active': 'mix',
            },
            {
              'type': 'pane',
              'id': 'x',
              'tabs': ['midi'],
              'active': 'midi',
            },
          ],
          'fractions': [0.5, 0.5],
        },
      });
      expectValidLayout(layout); // the checker asserts id uniqueness
    });
  });

  group('fit', () {
    test('drops a surface the app no longer knows, collapsing its pane', () {
      final layout = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      final fitted = layout.fit({'mix'});
      expectValidLayout(fitted);
      expect(fitted.placedSurfaces, {'mix'});
      expect(fitted.paneCount, 1);
    });

    test('keeps known surfaces and clamps their fractions', () {
      final layout = ShellLayout(
        root: LayoutSplit(
          id: 's1',
          axis: SplitAxis.row,
          children: const [
            LayoutPane(id: 'p1', tabs: ['mix'], active: 'mix'),
            LayoutPane(id: 'p2', tabs: ['midi'], active: 'midi'),
          ],
          fractions: const [0.99, 0.01],
        ),
      );
      final fitted = layout.fit({'mix', 'midi'});
      expectValidLayout(fitted);
      final fractions = (fitted.root as LayoutSplit).fractions;
      expect(fractions[1], greaterThan(0.01), reason: 'the sliver was clamped');
    });

    test('all surfaces unknown leaves a single empty pane', () {
      final layout = ShellLayout.seed().split('p1', 'midi', DropEdge.right);
      final fitted = layout.fit(const {});
      expectValidLayout(fitted);
      expect(fitted.paneCount, 1);
      expect(fitted.placedSurfaces, isEmpty);
    });
  });

  group('closedSurfaces', () {
    test('is the known universe minus the placed surfaces', () {
      final layout = ShellLayout.seed();
      expect(layout.closedSurfaces({'mix', 'midi', 'scene'}), {
        'midi',
        'scene',
      });
    });
  });

  group('property: random operation sequences preserve the invariants', () {
    test('500 random ops from the seed stay valid', () {
      final rng = Random(0xC0FFEE);
      const universe = [
        'mix',
        'midi',
        'scene',
        'patcher',
        'code',
        'state',
        'racks',
      ];
      var layout = ShellLayout.seed();

      for (var step = 0; step < 500; step++) {
        final paneIds = layout.panes.map((p) => p.id).toList();
        final splitIds = <String>[];
        final splitArity = <String, int>{};
        void collect(LayoutNode node) {
          if (node is LayoutSplit) {
            splitIds.add(node.id);
            splitArity[node.id] = node.children.length;
            node.children.forEach(collect);
          }
        }

        collect(layout.root);

        final surface = universe[rng.nextInt(universe.length)];
        final paneId = paneIds[rng.nextInt(paneIds.length)];

        switch (rng.nextInt(6)) {
          case 0:
            layout = layout.split(
              paneId,
              surface,
              DropEdge.values[rng.nextInt(DropEdge.values.length)],
            );
          case 1:
            layout = layout.join(paneId, surface);
          case 2:
            layout = layout.close(surface);
          case 3:
            layout = layout.moveSurface(
              surface,
              paneId,
              atIndex: rng.nextInt(4),
            );
          case 4:
            final pane = layout.paneById(paneId)!;
            if (pane.tabs.isNotEmpty) {
              layout = layout.reorderTab(
                paneId,
                rng.nextInt(pane.tabs.length),
                rng.nextInt(pane.tabs.length + 1),
              );
            }
          case 5:
            if (splitIds.isNotEmpty) {
              final splitId = splitIds[rng.nextInt(splitIds.length)];
              final arity = splitArity[splitId]!;
              layout = layout.resize(splitId, [
                for (var i = 0; i < arity; i++) rng.nextDouble() + 0.01,
              ]);
            }
        }

        expectValidLayout(layout);
      }
    });

    test('a round-trip is exact after a random walk', () {
      final rng = Random(42);
      const universe = ['mix', 'midi', 'scene', 'patcher', 'code'];
      var layout = ShellLayout.seed();
      for (var step = 0; step < 120; step++) {
        final paneIds = layout.panes.map((p) => p.id).toList();
        final paneId = paneIds[rng.nextInt(paneIds.length)];
        final surface = universe[rng.nextInt(universe.length)];
        layout = switch (rng.nextInt(3)) {
          0 => layout.split(
            paneId,
            surface,
            DropEdge.values[rng.nextInt(DropEdge.values.length)],
          ),
          1 => layout.join(paneId, surface),
          _ => layout.close(surface),
        };
      }
      expect(ShellLayout.fromJson(layout.toJson()), layout);
    });
  });
}
