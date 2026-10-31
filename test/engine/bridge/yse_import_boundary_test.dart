import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CLAUDE.md: "Don't import `package:yse/...` outside `lib/engine/bridge/`" —
/// the engine façade is the only place the FFI surface is touched. Surfaces
/// that need an engine type id read the pure-Dart mirror
/// (`PatchObjectTypes`) instead (issue #483).
void main() {
  test('only lib/engine/bridge/ imports package:yse', () {
    final offenders = <String>[];
    final directive = RegExp(
      r'''^\s*(import|export)\s+['"]package:yse/''',
      multiLine: true,
    );
    final bridge = Directory('lib/engine/bridge').absolute.path;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.absolute.path.startsWith(bridge)) continue;
      if (directive.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'package:yse may only be imported under lib/engine/bridge/ — found:\n'
          '${offenders.join('\n')}',
    );
  });
}
