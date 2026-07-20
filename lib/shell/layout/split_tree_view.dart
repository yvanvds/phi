import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/shell_layout/layout_node.dart';
import '../../domain/shell_layout/split_axis.dart';

/// Renders a [LayoutNode] split tree into nested rows/columns of panes (design
/// `docs/design/shell-layout.md` §2). A [LayoutSplit] becomes a [Row]
/// ([SplitAxis.row]) or [Column] ([SplitAxis.column]) whose children are sized
/// by the split's fractions; a [LayoutPane] leaf is handed to [buildPane].
///
/// Sizing is fraction-based via flexible children, so the geometry is
/// resolution-independent — the same tree fills a wide screen or a laptop
/// without pixel math. The splitter *handles* (drag to resize) and pane tab
/// strips are a later interaction slice; this widget only lays the tree out and
/// draws a hairline between siblings so a split reads as two regions.
class SplitTreeView extends StatelessWidget {
  const SplitTreeView({required this.root, required this.buildPane, super.key});

  /// The root of the tree to render.
  final LayoutNode root;

  /// Builds the content for a leaf pane (its resident tab stack).
  final Widget Function(LayoutPane pane) buildPane;

  /// Flex weights are integers; scale the fractions up so sub-percent
  /// differences still resolve to distinct weights.
  static const int _flexScale = 100000;

  @override
  Widget build(BuildContext context) => _node(root);

  Widget _node(LayoutNode node) {
    if (node is LayoutPane) {
      return KeyedSubtree(key: ValueKey(node.id), child: buildPane(node));
    }
    final split = node as LayoutSplit;
    final isRow = split.axis == SplitAxis.row;
    final children = <Widget>[];
    for (var i = 0; i < split.children.length; i++) {
      if (i > 0) children.add(_divider(isRow));
      final flex = (split.fractions[i] * _flexScale).round().clamp(1, 1 << 30);
      children.add(Expanded(flex: flex, child: _node(split.children[i])));
    }
    return isRow ? Row(children: children) : Column(children: children);
  }

  /// A 1px hairline between sibling panes — horizontal splits get a vertical
  /// rule, vertical splits a horizontal one.
  Widget _divider(bool isRow) => Container(
    width: isRow ? 1 : null,
    height: isRow ? null : 1,
    color: PhiColors.line1,
  );
}
