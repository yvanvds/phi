import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/shell_layout/layout_node.dart';
import 'package:phi/domain/shell_layout/split_axis.dart';

void main() {
  group('LayoutPane', () {
    test('round-trips through JSON', () {
      const pane = LayoutPane(id: 'p1', tabs: ['mix', 'midi'], active: 'midi');
      expect(LayoutNode.fromJson(pane.toJson()), pane);
    });

    test('toJson carries the tab stack and active tab', () {
      expect(
        const LayoutPane(id: 'p1', tabs: ['mix'], active: 'mix').toJson(),
        {
          'type': 'pane',
          'id': 'p1',
          'tabs': ['mix'],
          'active': 'mix',
        },
      );
    });

    test('fromJson pins active to a live tab', () {
      final pane =
          LayoutNode.fromJson(const {
                'type': 'pane',
                'id': 'p1',
                'tabs': ['mix', 'midi'],
                'active': 'ghost',
              })
              as LayoutPane;
      expect(pane.active, 'mix');
    });

    test('fromJson keeps only string tabs and defaults a missing active', () {
      final pane =
          LayoutNode.fromJson(const {
                'type': 'pane',
                'id': 'p1',
                'tabs': ['mix', 7, null, 'midi'],
              })
              as LayoutPane;
      expect(pane.tabs, ['mix', 'midi']);
      expect(pane.active, 'mix');
    });

    test('an empty pane has a null active', () {
      const pane = LayoutPane(id: 'p1');
      expect(pane.tabs, isEmpty);
      expect(pane.active, isNull);
      expect(LayoutNode.fromJson(pane.toJson()), pane);
    });

    test('copyWith can clear the active tab and leaves it otherwise', () {
      const pane = LayoutPane(id: 'p1', tabs: ['mix'], active: 'mix');
      expect(pane.copyWith(tabs: const []).active, 'mix'); // unchanged
      expect(pane.copyWith(active: null).active, isNull); // cleared
      expect(pane.copyWith(active: 'mix'), pane);
    });

    test('equality is by value across id, tabs and active', () {
      expect(
        const LayoutPane(id: 'p1', tabs: ['mix']),
        const LayoutPane(id: 'p1', tabs: ['mix']),
      );
      expect(
        const LayoutPane(id: 'p1', tabs: ['mix']),
        isNot(const LayoutPane(id: 'p2', tabs: ['mix'])),
      );
      expect(
        const LayoutPane(id: 'p1', tabs: ['mix'], active: 'mix'),
        isNot(const LayoutPane(id: 'p1', tabs: ['mix'])),
      );
    });
  });

  group('LayoutSplit', () {
    LayoutSplit split() => LayoutSplit(
      id: 's1',
      axis: SplitAxis.row,
      children: const [
        LayoutPane(id: 'p1', tabs: ['mix'], active: 'mix'),
        LayoutPane(id: 'p2', tabs: ['midi'], active: 'midi'),
      ],
      fractions: const [0.4, 0.6],
    );

    test('round-trips through JSON', () {
      expect(LayoutNode.fromJson(split().toJson()), split());
    });

    test('toJson tags the type, axis, children and fractions', () {
      expect(split().toJson(), {
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
        'fractions': [0.4, 0.6],
      });
    });

    test('fromJson coerces a fractions/children length mismatch', () {
      final node =
          LayoutNode.fromJson(const {
                'type': 'split',
                'id': 's1',
                'axis': 'column',
                'children': [
                  {
                    'type': 'pane',
                    'id': 'p1',
                    'tabs': ['mix'],
                  },
                  {
                    'type': 'pane',
                    'id': 'p2',
                    'tabs': ['midi'],
                  },
                ],
                'fractions': [0.9],
              })
              as LayoutSplit;
      expect(node.axis, SplitAxis.column);
      expect(node.fractions, [0.5, 0.5]);
    });

    test('an unknown or missing type reads as a pane', () {
      expect(LayoutNode.fromJson(const {'id': 'p1'}), isA<LayoutPane>());
      expect(
        LayoutNode.fromJson(const {'type': 'mystery', 'id': 'p1'}),
        isA<LayoutPane>(),
      );
    });
  });
}
