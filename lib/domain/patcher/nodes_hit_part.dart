/// Which part of a `.nodes` node a press landed on (issue #476).
enum NodesHitPart {
  /// Inside the circle: a layout drag moves the node.
  body,

  /// On the circle's edge: a layout drag changes the radius.
  rim,
}
