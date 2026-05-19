import 'package:flutter/painting.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';

import '../../design/tokens/phi_colors.dart';

/// Phi-flavoured highlight theme. Voices and semantic colours from
/// [PhiColors] are reused — keywords get fuchsia (`voice1`), strings
/// get cyan (`voice2`), comments fade into `fg3`. The map keys match
/// `re_highlight`'s class names.
CodeHighlightTheme buildPythonHighlightTheme() {
  return CodeHighlightTheme(
    languages: {'python': CodeHighlightThemeMode(mode: langPython)},
    theme: const {
      'root': TextStyle(color: PhiColors.fg1),
      'comment': TextStyle(color: PhiColors.fg3),
      'quote': TextStyle(color: PhiColors.fg3),
      'string': TextStyle(color: PhiColors.voice2),
      'number': TextStyle(color: PhiColors.voice3),
      'literal': TextStyle(color: PhiColors.voice3),
      'keyword': TextStyle(color: PhiColors.voice1),
      'selector-tag': TextStyle(color: PhiColors.voice1),
      'built_in': TextStyle(color: PhiColors.voice5),
      'type': TextStyle(color: PhiColors.voice5),
      'title': TextStyle(color: PhiColors.voice4),
      'section': TextStyle(color: PhiColors.voice4),
      'params': TextStyle(color: PhiColors.fg0),
      'meta': TextStyle(color: PhiColors.fg2),
      'symbol': TextStyle(color: PhiColors.voice2),
    },
  );
}
