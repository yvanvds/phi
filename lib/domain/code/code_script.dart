/// The payload of a `code.` registry entity — a live-coding script's source
/// text in the standard envelope (design `docs/design/live-coding.md` §5,
/// review decision 2, issue #235).
///
/// A script *is* its source: everything else about it — what has been evaluated
/// so far — is performance state that is never persisted. So the payload is just
/// the [source] string, wrapped in a one-key JSON map so the entity file stays a
/// conventional object envelope (matching the `mix.` / `domain.` map-native
/// payloads). Round-tripping it is byte-identical: [fromJson]∘[toJson] returns
/// the same [source] verbatim, so a saved script reopens exactly as written.
class CodeScript {
  /// A script carrying [source] (empty for a brand-new script).
  const CodeScript({this.source = ''});

  /// Rebuilds a script from its [json] payload map, defaulting a missing or
  /// malformed `source` to the empty string (so an older/partial file still
  /// loads).
  factory CodeScript.fromJson(Map<String, Object?> json) {
    final source = json[sourceKey];
    return CodeScript(source: source is String ? source : '');
  }

  /// The script's Python source text — the whole editable body.
  final String source;

  /// The JSON key the source is stored under in the payload map.
  static const String sourceKey = 'source';

  /// The payload map for this script — `{'source': <text>}`.
  Map<String, Object?> toJson() => <String, Object?>{sourceKey: source};

  /// A copy of this script with its [source] replaced.
  CodeScript copyWith({String? source}) =>
      CodeScript(source: source ?? this.source);

  @override
  bool operator ==(Object other) =>
      other is CodeScript && other.source == source;

  @override
  int get hashCode => source.hashCode;

  @override
  String toString() => 'CodeScript(${source.length} chars)';
}
