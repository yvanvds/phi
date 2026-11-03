import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// A [TestPlatformDispatcher] that reports the real engine's id.
///
/// flutter_test hard-codes [TestPlatformDispatcher.engineId] to `1`. The
/// platform windowing owners read it to reach the engine, and on Linux it is
/// the address of the `FlEngine`, so a native window made under the stock
/// test dispatcher dereferences address 1 (flutter/flutter#195919).
class EnginePlatformDispatcher extends TestPlatformDispatcher {
  EnginePlatformDispatcher({required super.platformDispatcher});

  @override
  int? get engineId => PlatformDispatcher.instance.engineId;
}
