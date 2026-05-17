/// Guards against CSS-token drift. If `design system/colors_and_type.css`
/// changes without the matching `lib/design/tokens/*.dart` regen, this fails.
///
/// Run `dart run tool/gen_tokens.dart` to bring the Dart side back in sync.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('design tokens are in sync with colors_and_type.css', () {
    final result = Process.runSync('dart', [
      'run',
      'tool/gen_tokens.dart',
      '--check',
    ], runInShell: true);
    expect(
      result.exitCode,
      0,
      reason:
          'Design tokens drifted from `design system/colors_and_type.css`. '
          'Run `dart run tool/gen_tokens.dart` to regenerate.\n'
          'stdout: ${result.stdout}\n'
          'stderr: ${result.stderr}',
    );
  });
}
