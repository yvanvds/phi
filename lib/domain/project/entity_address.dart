import 'name_validator.dart';

/// The dotted path that names an entity or group in the registry —
/// `kind.group….name` (design `docs/design/project-registry.md` §2–§3).
///
/// The same string is the Python attribute chain, the registry key, and
/// (mapped to slashes) the on-disk file path, so an address is *valid by
/// construction*: [kind] and every [segments] entry are checked through the
/// shared [NameValidator], and building an invalid one throws. A
/// [FormatException] — not a silent, half-built value — is the only outcome of
/// a bad address.
///
/// Grammar:
/// ```
/// address := kind '.' segment ('.' segment)*
/// segment := [a-z_][a-z0-9_]*        (max 64 chars)
/// ```
/// There is always a [kind] and at least one segment: the shortest address
/// (`clip.lead_line`) names a top-level entity or group. A kind on its own
/// (`clip`) is the tree root and has no address.
class EntityAddress {
  /// Builds an address from a [kind] and its path [segments].
  ///
  /// Throws a [FormatException] if [segments] is empty or if [kind] or any
  /// segment fails [NameValidator].
  factory EntityAddress({
    required String kind,
    required List<String> segments,
  }) {
    _validateSegment(kind, 'kind');
    if (segments.isEmpty) {
      throw const FormatException('An address needs at least one segment.');
    }
    for (final segment in segments) {
      _validateSegment(segment, 'segment');
    }
    return EntityAddress._(kind, List.unmodifiable(segments));
  }

  const EntityAddress._(this.kind, this.segments);

  /// Parses a dotted address such as `clip.drums.intro_fill`.
  ///
  /// Throws a [FormatException] if [dotted] is not a well-formed address (no
  /// kind, no segment, or any part that fails [NameValidator]). Use [tryParse]
  /// for the non-throwing form.
  factory EntityAddress.parse(String dotted) {
    final parts = dotted.split('.');
    if (parts.length < 2) {
      throw FormatException(
        'An address needs a kind and at least one segment: "$dotted".',
      );
    }
    return EntityAddress(kind: parts.first, segments: parts.sublist(1));
  }

  /// Parses a dotted address, returning `null` instead of throwing when
  /// [dotted] is not well-formed.
  static EntityAddress? tryParse(String dotted) {
    try {
      return EntityAddress.parse(dotted);
    } on FormatException {
      return null;
    }
  }

  /// The namespace this address lives in — `clip`, `mix`, `voice`, … The tree
  /// keeps one root per kind.
  final String kind;

  /// The path segments beneath [kind], in order. Always non-empty and
  /// unmodifiable; the last entry is [name].
  final List<String> segments;

  /// The leaf name — the entity's or group's own segment.
  String get name => segments.last;

  /// The group segments above [name] (everything but the last). Empty for a
  /// top-level address, whose parent is the kind root.
  List<String> get groupPath => segments.length == 1
      ? const []
      : segments.sublist(0, segments.length - 1);

  /// Whether this address sits directly under the kind root (one segment).
  bool get isTopLevel => segments.length == 1;

  /// The enclosing group's address, or `null` when this is [isTopLevel] (the
  /// parent is then the kind root, which has no address).
  EntityAddress? get parent => isTopLevel
      ? null
      : EntityAddress._(kind, segments.sublist(0, segments.length - 1));

  /// A child address one level deeper, named [segment].
  ///
  /// Throws a [FormatException] if [segment] fails [NameValidator].
  EntityAddress child(String segment) {
    _validateSegment(segment, 'segment');
    return EntityAddress._(kind, [...segments, segment]);
  }

  /// Whether this address is strictly nested inside [other] — same [kind], with
  /// [other]'s segments a proper prefix of this one's. A group is not a
  /// descendant of itself.
  bool isDescendantOf(EntityAddress other) {
    if (kind != other.kind) return false;
    if (other.segments.length >= segments.length) return false;
    for (var i = 0; i < other.segments.length; i++) {
      if (segments[i] != other.segments[i]) return false;
    }
    return true;
  }

  /// The dotted string form, `kind.seg1.seg2…` — the inverse of [parse].
  String format() => '$kind.${segments.join('.')}';

  @override
  String toString() => format();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EntityAddress) return false;
    if (other.kind != kind || other.segments.length != segments.length) {
      return false;
    }
    for (var i = 0; i < segments.length; i++) {
      if (other.segments[i] != segments[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(segments));

  static void _validateSegment(String value, String role) {
    final problem = NameValidator.check(value);
    if (problem != null) {
      throw FormatException('Invalid $role "$value": ${problem.message}');
    }
  }
}
