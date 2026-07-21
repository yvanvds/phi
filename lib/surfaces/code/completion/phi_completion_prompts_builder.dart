import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import '../../../domain/code/completion/phi_completion.dart';
import '../../../domain/code/completion/phi_completion_resolver.dart';
import 'phi_completion_prompt.dart';

/// Bridges `re_editor`'s autocomplete hook to the pure-Dart
/// [PhiCompletionResolver] (design `docs/design/live-coding.md` §6).
///
/// `re_editor` calls [build] with the current line and cursor on every user
/// keystroke; we hand the text left of the cursor to the resolver and, when it
/// finds a `phi` context, wrap each row as a [PhiCompletionPrompt]. Returning
/// `null` suppresses the overlay entirely, so a plain Python line pops nothing.
class PhiCompletionPromptsBuilder implements CodeAutocompletePromptsBuilder {
  const PhiCompletionPromptsBuilder(this.resolver);

  final PhiCompletionResolver resolver;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final text = codeLine.text;
    final offset = selection.extentOffset;
    if (offset < 0 || offset > text.length) return null;

    final PhiCompletion? completion = resolver.resolve(
      text.substring(0, offset),
    );
    if (completion == null) return null;

    return CodeAutocompleteEditingValue(
      input: completion.input,
      prompts: [for (final item in completion.items) PhiCompletionPrompt(item)],
      index: 0,
    );
  }
}
