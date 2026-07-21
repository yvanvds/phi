import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs the pure-Python `phi` library's `unittest` suite (under `python/`) from
/// inside `flutter test`, so CI actually verifies the library the live-coding
/// epic ships as source (design `docs/design/live-coding.md` §3, issue #230).
///
/// The library is pure Python (review decision 4), but its whole contract —
/// table sync, rename-following bound proxies, group iteration, and every
/// verb's emitted address/value shape — is expressed as "submit source, assert
/// published addresses/values" against a fake `yse` bus. That suite is what this
/// harness drives. It is skipped only when no Python interpreter is on PATH
/// (never on CI's Ubuntu runner, where `python3` is always present).
void main() {
  test('phi python library unittest suite passes', () async {
    final repoRoot = _repoRoot();
    final testsDir = Directory('${repoRoot.path}/python/tests');
    expect(
      testsDir.existsSync(),
      isTrue,
      reason: 'expected python/tests under ${repoRoot.path}',
    );

    final python = await _findPython();
    if (python == null) {
      markTestSkipped('no python interpreter found on PATH');
      return;
    }

    final result = await Process.run(python, const <String>[
      '-m',
      'unittest',
      'discover',
      '-s',
      'python/tests',
      '-p',
      'test_*.py',
    ], workingDirectory: repoRoot.path);

    final output = '${result.stdout}\n${result.stderr}'.trim();
    expect(
      result.exitCode,
      0,
      reason: 'phi python suite failed ($python):\n$output',
    );
  });
}

/// Walk up from the current directory to the package root (the directory that
/// holds `pubspec.yaml`), so the harness works whatever the test runner's cwd.
Directory _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return Directory.current;
    dir = parent;
  }
}

/// The first working interpreter among `python3` / `python`, or null if neither
/// is on PATH.
Future<String?> _findPython() async {
  for (final candidate in const ['python3', 'python']) {
    try {
      final probe = await Process.run(candidate, const ['--version']);
      if (probe.exitCode == 0) return candidate;
    } on ProcessException {
      // Not on PATH — try the next candidate.
    }
  }
  return null;
}
