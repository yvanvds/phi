import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/completion/phi_method_table.dart';

/// The drift guard of design `docs/design/live-coding.md` §6: the checked-in
/// [phiMethodTable] the completion popup ships must stay identical to the `phi`
/// library's own `_VERB_NAMES` (what `dir(voice.bells)` lists). This test reads
/// the library source and fails — printing the corrected list — the moment a
/// verb is added, removed, or reordered on one side but not the other.
void main() {
  test('phiMethodTable matches the phi library _VERB_NAMES', () {
    final source = File('python/phi/__init__.py').readAsStringSync();

    // Grab the tuple body of `_VERB_NAMES = ( ... )` (the assignment, not the
    // later `set(_VERB_NAMES)` use — that has no `= (`).
    final assignment = RegExp(
      r'_VERB_NAMES\s*=\s*\(([^)]*)\)',
    ).firstMatch(source);
    expect(
      assignment,
      isNotNull,
      reason: 'could not find `_VERB_NAMES = (...)` in python/phi/__init__.py',
    );

    final fromLibrary = RegExp(
      "'([^']*)'",
    ).allMatches(assignment!.group(1)!).map((m) => m.group(1)!).toList();

    expect(
      phiMethodTable,
      fromLibrary,
      reason:
          'phi_method_table.dart drifted from the phi library. Regenerate it '
          'to match _VERB_NAMES:\n$fromLibrary',
    );
  });
}
