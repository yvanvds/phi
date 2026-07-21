import 'phi_completion_item_kind.dart';

/// One row the completion popup offers — the identifier to insert plus the
/// Phi-flavoured extras the popup paints beside it (design
/// `docs/design/live-coding.md` §6).
///
/// A pure value type: the extras are sourced from the Dart registry (a voice's
/// [colorToken], a clip's [bars]) but stay token/number-shaped here — the domain
/// never reaches for a Flutter `Color`. The design layer resolves [colorToken]
/// to a swatch when it paints the row.
///
/// [identifier] is *all* that is ever inserted — a group narrows the path, an
/// entity names a thing, a method names a verb, but selection only ever writes
/// the bare identifier (design §6: "inserts the identifier only").
class PhiCompletionItem {
  const PhiCompletionItem({
    required this.identifier,
    required this.kind,
    this.namespace,
    this.colorToken,
    this.bars,
  });

  /// The bare identifier the editor inserts on selection.
  final String identifier;

  /// Whether this row is a group, an entity, or a method.
  final PhiCompletionItemKind kind;

  /// The phi namespace this row lives under (`voice`, `clip`, …), or `null` for
  /// a method row. Drives which entity flavour the popup paints.
  final String? namespace;

  /// A voice entity's colour token (`voice1..voice6`, or any palette token) —
  /// the design layer resolves it to a swatch. `null` for non-voice rows.
  final String? colorToken;

  /// A clip entity's length in bars — painted as a trailing badge. `null` for
  /// non-clip rows.
  final int? bars;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhiCompletionItem &&
          other.identifier == identifier &&
          other.kind == kind &&
          other.namespace == namespace &&
          other.colorToken == colorToken &&
          other.bars == bars;

  @override
  int get hashCode =>
      Object.hash(identifier, kind, namespace, colorToken, bars);

  @override
  String toString() =>
      'PhiCompletionItem($identifier, ${kind.name}, ns: $namespace, '
      'color: $colorToken, bars: $bars)';
}
