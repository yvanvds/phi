import 'split_axis.dart';

/// A node in the shell's split tree (design `docs/design/shell-layout.md` §2).
///
/// The tree is made of two node kinds: a [LayoutPane] leaf — an ordered tab
/// stack of surface ids with one active tab — and a [LayoutSplit] branch — a row
/// or column of child nodes with fraction-based sizes. Every node carries a
/// stable [id] so operations can target it and a save/reload can round-trip it.
///
/// Nodes are pure, immutable value types (no Flutter, no engine): they
/// (de)serialise to JSON and compare by value, so the whole tree round-trips and
/// an operation's result is easy to assert. Structural invariants (fractions sum
/// to 1, single-instance surfaces, a live active tab, at least one pane) are
/// enforced by [ShellLayout], not by the node constructors — a node on its own is
/// just data.
sealed class LayoutNode {
  const LayoutNode();

  /// Rebuilds a node from its decoded JSON map, dispatching on the `type` tag.
  /// An unrecognised (or missing) tag is read as a [LayoutPane] — the tolerant
  /// default, so a corrupt manifest section still yields a usable node.
  static LayoutNode fromJson(Map<String, Object?> json) =>
      json['type'] == 'split'
      ? LayoutSplit.fromJson(json)
      : LayoutPane.fromJson(json);

  /// The node's stable identifier, unique within a tree.
  String get id;

  /// The node as the JSON map stored in the layout section.
  Map<String, Object?> toJson();
}

/// A leaf pane: an ordered [tabs] stack of surface ids with one [active] tab
/// (design §2 — "each pane holds a tab stack of surfaces").
///
/// [active] is null exactly when [tabs] is empty; otherwise it is one of [tabs].
/// A surface id is opaque here — the shell maps its `SurfaceId` onto a string —
/// which is what lets fit-fallback drop an id the app no longer knows.
final class LayoutPane extends LayoutNode {
  const LayoutPane({required this.id, this.tabs = const [], this.active});

  /// Reads a pane from JSON, keeping only string tab ids and pinning [active] to
  /// a tab that actually exists (falling back to the first tab, or null when the
  /// stack is empty).
  factory LayoutPane.fromJson(Map<String, Object?> json) {
    final tabs = <String>[
      for (final tab in (json['tabs'] as List<Object?>? ?? const []))
        if (tab is String) tab,
    ];
    final active = json['active'] as String?;
    return LayoutPane(
      id: json['id'] as String? ?? '',
      tabs: tabs,
      active: active != null && tabs.contains(active)
          ? active
          : (tabs.isEmpty ? null : tabs.first),
    );
  }

  @override
  final String id;

  /// The surface ids in this pane, in tab order (index = tab position).
  final List<String> tabs;

  /// The active (foreground) tab's surface id, or null when [tabs] is empty.
  final String? active;

  LayoutPane copyWith({
    String? id,
    List<String>? tabs,
    Object? active = _unset,
  }) => LayoutPane(
    id: id ?? this.id,
    tabs: tabs ?? this.tabs,
    active: identical(active, _unset) ? this.active : active as String?,
  );

  @override
  Map<String, Object?> toJson() => {
    'type': 'pane',
    'id': id,
    'tabs': tabs,
    'active': active,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutPane &&
          other.id == id &&
          other.active == active &&
          _sameStrings(other.tabs, tabs);

  @override
  int get hashCode => Object.hash(id, active, Object.hashAll(tabs));

  @override
  String toString() => 'LayoutPane($id, tabs: $tabs, active: $active)';

  /// Sentinel distinguishing "leave [active] unchanged" from "set it to null" in
  /// [copyWith] — a plain `null` default can't tell the two apart.
  static const Object _unset = Object();
}

/// A branch node: a [row] or [column] of [children] sized by [fractions] (design
/// §2 — "rows and columns of panes, resizable by splitter drag").
///
/// [fractions] runs parallel to [children] (fraction `i` sizes child `i`) and, in
/// a well-formed tree, holds positive values summing to 1 — so geometry is
/// resolution-independent and degrades gracefully on a smaller screen.
final class LayoutSplit extends LayoutNode {
  LayoutSplit({
    required this.id,
    required this.axis,
    required this.children,
    required this.fractions,
  }) : assert(
         children.length == fractions.length,
         'each child needs exactly one fraction',
       );

  /// Reads a split from JSON. Fractions are coerced to match the child count
  /// (an equal share when the stored list disagrees); [ShellLayout] normalises
  /// them afterwards.
  factory LayoutSplit.fromJson(Map<String, Object?> json) {
    final children = <LayoutNode>[
      for (final child in (json['children'] as List<Object?>? ?? const []))
        if (child is Map) LayoutNode.fromJson(child.cast<String, Object?>()),
    ];
    var fractions = <double>[
      for (final fraction in (json['fractions'] as List<Object?>? ?? const []))
        if (fraction is num) fraction.toDouble(),
    ];
    if (fractions.length != children.length) {
      final share = children.isEmpty ? 1.0 : 1.0 / children.length;
      fractions = [for (final _ in children) share];
    }
    return LayoutSplit(
      id: json['id'] as String? ?? '',
      axis: json['axis'] == 'column' ? SplitAxis.column : SplitAxis.row,
      children: children,
      fractions: fractions,
    );
  }

  @override
  final String id;

  /// The direction this split lays its [children] out along.
  final SplitAxis axis;

  /// The child nodes in order (a well-formed split has at least two).
  final List<LayoutNode> children;

  /// The size of each child as a fraction of this split, parallel to [children].
  final List<double> fractions;

  LayoutSplit copyWith({
    String? id,
    SplitAxis? axis,
    List<LayoutNode>? children,
    List<double>? fractions,
  }) => LayoutSplit(
    id: id ?? this.id,
    axis: axis ?? this.axis,
    children: children ?? this.children,
    fractions: fractions ?? this.fractions,
  );

  @override
  Map<String, Object?> toJson() => {
    'type': 'split',
    'id': id,
    'axis': axis.name,
    'children': [for (final child in children) child.toJson()],
    'fractions': fractions,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutSplit &&
          other.id == id &&
          other.axis == axis &&
          _sameNodes(other.children, children) &&
          _sameDoubles(other.fractions, fractions);

  @override
  int get hashCode => Object.hash(
    id,
    axis,
    Object.hashAll(children),
    Object.hashAll(fractions),
  );

  @override
  String toString() =>
      'LayoutSplit($id, ${axis.name}, children: $children, '
      'fractions: $fractions)';
}

/// Element-wise string-list equality — the domain stays Flutter-free, so it
/// cannot borrow `foundation`'s `listEquals`.
bool _sameStrings(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Element-wise node-list equality (order matters — children are ordered).
bool _sameNodes(List<LayoutNode> a, List<LayoutNode> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Element-wise double-list equality (fractions).
bool _sameDoubles(List<double> a, List<double> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
