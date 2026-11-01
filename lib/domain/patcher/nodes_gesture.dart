import 'dart:math' as math;

import 'field_node.dart';
import 'nodes_edit.dart';
import 'nodes_hit_part.dart';
import 'nodes_view.dart';

/// One pointer on a `.nodes` field: which edits each move sends (issue #476).
///
/// Positions are in the box's own pixels ([NodesView]).
///
/// - A **plain** press puts the cursor under the pointer, and the drag carries
///   it; every new position is sent, and the object answers with its weights.
///   The cursor stays inside the field.
/// - An **alt**-press edits the layout instead. On a node's body the drag
///   moves it, holding the point it was grabbed by under the pointer; on its
///   rim the drag sets the radius to the pointer's distance from the centre.
///   An alt-press on empty space does nothing. A moved centre stays inside the
///   field, and a radius between [NodesView.minRadius] and
///   [NodesView.maxRadius].
///
/// [selected] is the node the layout drag holds.
class NodesGesture {
  /// A gesture over [view] on a field holding [nodes].
  NodesGesture({required this._view, required List<FieldNode> nodes})
    : _nodes = [...nodes];

  final NodesView _view;
  final List<FieldNode> _nodes;

  _Mode _mode = _Mode.idle;
  int _index = 0;
  double _grabX = 0;
  double _grabY = 0;
  NodesEdit? _last;

  /// The node the layout drag holds, or null.
  int? get selected =>
      _mode == _Mode.move || _mode == _Mode.resize ? _index : null;

  /// The pointer went down at ([px], [py]); [alt] is whether Alt was held.
  /// Answers the edit to send, or null when the press sends nothing.
  NodesEdit? down(double px, double py, {bool alt = false}) {
    _last = null;
    if (!alt) {
      _mode = _Mode.cursor;
      return _emit(_cursorAt(px, py));
    }
    final hit = _view.hit(_nodes, px, py);
    if (hit == null) {
      _mode = _Mode.idle;
      return null;
    }
    _index = hit.index;
    final node = _nodes[hit.index];
    if (hit.part == NodesHitPart.rim) {
      _mode = _Mode.resize;
      _last = NodesEdit.resize(_index, node.x, node.y, node.radius);
      return null;
    }
    _mode = _Mode.move;
    final (fx, fy) = _view.fieldAt(px, py);
    _grabX = fx - node.x;
    _grabY = fy - node.y;
    _last = NodesEdit.move(_index, node.x, node.y);
    return null;
  }

  /// The pointer moved to ([px], [py]). Answers the edit to send, or null when
  /// nothing changed.
  NodesEdit? moveTo(double px, double py) {
    switch (_mode) {
      case _Mode.idle:
        return null;
      case _Mode.cursor:
        return _emit(_cursorAt(px, py));
      case _Mode.move:
        final (fx, fy) = _view.fieldAt(px, py);
        final x = _view.snap((fx - _grabX).clamp(0.0, 1.0));
        final y = _view.snap((fy - _grabY).clamp(0.0, 1.0));
        final node = _nodes[_index];
        final edit = _emit(NodesEdit.move(_index, x, y));
        if (edit != null) _nodes[_index] = FieldNode(x, y, node.radius);
        return edit;
      case _Mode.resize:
        final node = _nodes[_index];
        final (fx, fy) = _view.fieldAt(px, py);
        final reach = math.sqrt(
          math.pow(fx - node.x, 2) + math.pow(fy - node.y, 2),
        );
        final radius = _view.snap(
          reach.clamp(NodesView.minRadius, NodesView.maxRadius),
        );
        final edit = _emit(NodesEdit.resize(_index, node.x, node.y, radius));
        if (edit != null) _nodes[_index] = FieldNode(node.x, node.y, radius);
        return edit;
    }
  }

  /// The pointer lifted.
  void up() => _mode = _Mode.idle;

  NodesEdit _cursorAt(double px, double py) {
    final (x, y) = _view.clampedAt(px, py);
    return NodesEdit.cursor(x, y);
  }

  /// [edit], unless it repeats the last one.
  NodesEdit? _emit(NodesEdit edit) {
    if (edit == _last) return null;
    _last = edit;
    return edit;
  }
}

enum _Mode { idle, cursor, move, resize }
