import 'phi_completion_item.dart';

/// The outcome of resolving a completion request at a cursor position — the
/// partial identifier already typed after the last dot ([input]) and the ranked
/// [items] that match it (design `docs/design/live-coding.md` §6).
///
/// The resolver returns `null` (not an empty [PhiCompletion]) for a non-`phi`
/// context or when nothing matches, so plain Python typing never pops an empty
/// list — the popup only ever appears with something in it.
class PhiCompletion {
  const PhiCompletion({required this.input, required this.items});

  /// The partial identifier typed after the last dot (`voice.be` → `be`), empty
  /// right after the dot. The editor replaces exactly this run when a row is
  /// chosen.
  final String input;

  /// The matching rows, in offer order — registry order for entities/groups, or
  /// method-table order for verbs. Never empty (the resolver returns `null`
  /// instead).
  final List<PhiCompletionItem> items;
}
