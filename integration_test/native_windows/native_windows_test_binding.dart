import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'engine_platform_dispatcher.dart';

/// The integration binding with **native** windows: a `WindowController` made
/// under it is a real top-level window over the running engine, drawn by the
/// engine into a view of its own, not flutter_test's stand-in.
///
/// The stock [IntegrationTestWidgetsFlutterBinding] installs flutter_test's
/// test windowing owner, whose views the engine never hears of (their frames
/// are dropped), and its dispatcher reports a fake engine id, so the platform
/// owner cannot be swapped in after the fact either (flutter/flutter#195919).
/// This binding keeps the platform's owner and reports the real id.
///
/// It has to exist before the integration entry point would create the stock
/// binding, so `flutter_test_config.dart` in this folder installs it.
class NativeWindowsTestBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestWindowingOwner => false;

  // Wraps [PlatformDispatcher.instance], not `super.platformDispatcher`: that
  // is the stock test dispatcher, whose engine id is the fake one.
  @override
  TestPlatformDispatcher get platformDispatcher => _platformDispatcher;
  late final TestPlatformDispatcher _platformDispatcher =
      EnginePlatformDispatcher(platformDispatcher: PlatformDispatcher.instance);

  // The real mouse keeps talking to a native window after its widgets have left
  // the tree, for as long as the window lives. flutter_test looks the event's
  // render view up and throws when there is none. It only does that for device
  // events, and the framework outside a test has no such lookup.
  @override
  void handlePointerEvent(PointerEvent event) {
    if (pointerEventSource == TestBindingEventSource.device &&
        !renderViews.any((view) => view.flutterView.viewId == event.viewId)) {
      return;
    }
    super.handlePointerEvent(event);
  }

  /// Installs this binding, once, before any other is made.
  static NativeWindowsTestBinding ensureInitialized() =>
      _instance ??= NativeWindowsTestBinding();

  static NativeWindowsTestBinding? _instance;
}
