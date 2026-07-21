import 'package:re_editor/re_editor.dart';

import '../../../domain/code/completion/phi_completion_item.dart';

/// Adapts a Phi [PhiCompletionItem] onto `re_editor`'s [CodePrompt] contract so
/// the editor's autocomplete overlay can host our registry-driven rows.
///
/// The [autocomplete] result is the bare identifier — selecting a row inserts
/// `bells`, never `bells(...)`, even for a method (design
/// `docs/design/live-coding.md` §6: "inserts the identifier only"). The wrapped
/// [item] carries the Phi-flavoured extras the popup paints.
class PhiCompletionPrompt extends CodePrompt {
  PhiCompletionPrompt(this.item) : super(word: item.identifier);

  /// The registry-sourced row this prompt renders and inserts.
  final PhiCompletionItem item;

  @override
  CodeAutocompleteResult get autocomplete =>
      CodeAutocompleteResult.fromWord(item.identifier);

  @override
  bool match(String input) =>
      word.toLowerCase().startsWith(input.toLowerCase());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhiCompletionPrompt && other.item == item;

  @override
  int get hashCode => item.hashCode;
}
