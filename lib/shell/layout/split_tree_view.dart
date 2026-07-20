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
/// without pixel math. Between siblings sits a draggable **splitter handle**: a
/// hairline in an 8px hit strip that reports drags to [onResize] as a fraction
/// of the split's main-axis extent (the widget does the pixel→fraction maths;
/// the caller clamps to the minima). When [onResize] is null the handle is an
/// inert hairline.
class SplitTreeView extends StatelessWidget {
  const SplitTreeView({
    required this.root,
    required this.buildPane,
    this.onResize,
    super.key,
  });

  /// The root of the tree to render.
  final LayoutNode root;

  /// Builds the content for a leaf pane (its resident tab stack).
  final Widget Function(LayoutPane pane) buildPane;

  /// Called while the handle between child [leadingIndex] and its successor in
  /// split [splitId] is dragged, by [deltaFraction] of the split's main-axis
  /// extent (positive grows the leading child). Null makes handles inert.
  final void Function(String splitId, int leadingIndex, double deltaFraction)?
  onResize;

  /// Flex weights are integers; scale the fractions up so sub-percent
  /// differences still resolve to distinct weights.
  static const int _flexScale = 100000;

  /// The interactive width/height of a splitter handle (a hairline centred in a
  /// wider, easier-to-grab hit strip).
  static const double handleThickness = 8;

  /// Test handle for the splitter between child [leadingIndex] and its successor.
  static Key splitterKey(String splitId, int leadingIndex) =>
      ValueKey('splitter-$splitId-$leadingIndex');

  @override
  Widget build(BuildContext context) => _node(root);

  Widget _node(LayoutNode node) {
    if (node is LayoutPane) {
      return KeyedSubtree(key: ValueKey(node.id), child: buildPane(node));
    }
    final split = node as LayoutSplit;
    final isRow = split.axis == SplitAxis.row;
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = isRow ? constraints.maxWidth : constraints.maxHeight;
        final children = <Widget>[];
        for (var i = 0; i < split.children.length; i++) {
          if (i > 0) {
            children.add(
              _SplitterHandle(
                key: splitterKey(split.id, i - 1),
                isRow: isRow,
                onDragFraction: onResize == null || extent <= 0
                    ? null
                    : (deltaPixels) =>
                          onResize!(split.id, i - 1, deltaPixels / extent),
              ),
            );
          }
          final flex = (split.fractions[i] * _flexScale).round().clamp(
            1,
            1 << 30,
          );
          children.add(Expanded(flex: flex, child: _node(split.children[i])));
        }
        return isRow ? Row(children: children) : Column(children: children);
      },
    );
  }
}

/// A draggable divider between two sibling panes: a 1px hairline centred in an
/// 8px hit strip, with a resize cursor. Reports the raw pixel delta along the
/// split's main axis to [onDragFraction]; when that is null it is a plain rule.
class _SplitterHandle extends StatelessWidget {
  const _SplitterHandle({
    required this.isRow,
    required this.onDragFraction,
    super.key,
  });

  final bool isRow;

  /// Receives the drag delta in pixels along the split's main axis; null = inert.
  final ValueChanged<double>? onDragFraction;

  @override
  Widget build(BuildContext context) {
    final line = Container(
      width: isRow ? 1 : null,
      height: isRow ? null : 1,
      color: PhiColors.line1,
    );
    if (onDragFraction == null) {
      return SizedBox(
        width: isRow ? SplitTreeView.handleThickness : null,
        height: isRow ? null : SplitTreeView.handleThickness,
        child: Center(child: line),
      );
    }
    return MouseRegion(
      cursor: isRow
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: isRow
            ? (d) => onDragFraction!(d.delta.dx)
            : null,
        onVerticalDragUpdate: isRow ? null : (d) => onDragFraction!(d.delta.dy),
        child: SizedBox(
          width: isRow ? SplitTreeView.handleThickness : null,
          height: isRow ? null : SplitTreeView.handleThickness,
          child: Center(child: line),
        ),
      ),
    );
  }
}
