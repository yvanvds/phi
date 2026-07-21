/// What a single completion row *is* — the three shapes the registry-driven
/// popup offers (design `docs/design/live-coding.md` §6).
///
/// A [group] narrows one level deeper (`clip.drums.` → its members); an [entity]
/// is a concrete leaf (a voice, a clip, a bus …); a [method] is a verb from the
/// static method table one level past an entity (`voice.bells.` → `note`, `off`,
/// …). The widget layer paints each shape differently — a chevron for a group, a
/// colour swatch or bar-length for an entity, a call marker for a method.
enum PhiCompletionItemKind { group, entity, method }
