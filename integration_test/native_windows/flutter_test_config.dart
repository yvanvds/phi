import 'dart:async';

import 'native_windows_test_binding.dart';

/// Runs before the integration entry point creates its binding, so the tests
/// in this folder get [NativeWindowsTestBinding] — real native windows —
/// instead of flutter_test's stand-ins.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  NativeWindowsTestBinding.ensureInitialized();
  await testMain();
}
