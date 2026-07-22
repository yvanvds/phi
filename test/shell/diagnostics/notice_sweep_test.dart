import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The retrofit sweep (design `docs/design/diagnostics.md` §3, §8 decision 3)
/// leaves the notice channel (`NoticeCenter.notice`) as the single way a
/// user-facing notice reaches the screen. This guards that: nowhere under `lib/`
/// may surface an ad-hoc transient message through Flutter's `SnackBar` /
/// `ScaffoldMessenger` — a future notice must route through the channel so it is
/// both toasted and logged, never flashed without a trace.
void main() {
  test('no direct SnackBar / ScaffoldMessenger notice sites under lib/', () {
    final offenders = <String>[];
    final banned = RegExp(r'\b(SnackBar|ScaffoldMessenger|showSnackBar)\b');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final match in banned.allMatches(text)) {
        offenders.add('${entity.path}: ${match.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'ad-hoc notice sites must route through NoticeCenter.notice — found:\n'
          '${offenders.join('\n')}',
    );
  });
}
