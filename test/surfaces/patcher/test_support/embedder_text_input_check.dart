import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the platform's text input plugin in an integration test and
/// checks the one rule a multi-window app can break: every call that needs
/// the client's view must find that view still alive **when the platform
/// gets round to it** (issue #481).
///
/// The Windows embedder's `TextInputPlugin` remembers the `viewId` of the
/// last `TextInput.setClient`, and `setEditableSizeAndTransform`,
/// `setMarkedTextRect` and `clearClient` look that view up — failing with
/// `Text input is not available because view with view_id=N cannot be
/// found` when it is gone. Those calls are platform messages, handled on a
/// later turn of the platform loop, while destroying a window is a
/// synchronous FFI call; so a window destroyed in the same turn its text field
/// detaches makes the embedder fail the detach. The Linux embedder does not
/// check at all.
///
/// It also has to stand in, not just watch: under flutter_test a window is a
/// stand-in view on the test platform dispatcher that the engine never hears
/// of, so the real Windows plugin fails *every* call from a field in it (PR
/// #555's CI). Checked against the binding's views here, the same rule holds
/// for the stand-in as the engine applies to a native window.
///
/// Queues each call, handles it one event-loop turn later in order — as the
/// embedder does — and records in [errors] every view-dependent call whose
/// view no longer exists.
class EmbedderTextInputCheck {
  EmbedderTextInputCheck(this.tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      _receive,
    );
  }

  final WidgetTester tester;

  /// One line per call the Windows embedder would have failed.
  final List<String> errors = [];

  /// Every call handled, in order, as `method(viewId)`.
  final List<String> log = [];

  int? _viewId;
  Future<void> _queue = Future<void>.value();

  static const Set<String> _needsView = {
    'TextInput.setEditableSizeAndTransform',
    'TextInput.setMarkedTextRect',
    'TextInput.clearClient',
  };

  Future<Object?> _receive(MethodCall call) {
    final handled = _queue.then((_) async {
      // The embedder runs a platform message on a later turn of its loop.
      await Future<void>.delayed(Duration.zero);
      _handle(call);
    });
    _queue = handled;
    return handled.then((_) => null);
  }

  void _handle(MethodCall call) {
    if (call.method == 'TextInput.setClient') {
      final config = (call.arguments as List<Object?>)[1]! as Map;
      _viewId = config['viewId'] as int?;
    }
    final view = _viewId;
    log.add('${call.method}($view)');
    if (!_needsView.contains(call.method) || view == null) return;
    final alive = tester.binding.platformDispatcher.views.any(
      (v) => v.viewId == view,
    );
    if (!alive) errors.add('${call.method}: view $view is gone');
  }

  /// Lets every queued call be handled.
  Future<void> drain() => tester.runAsync(() => _queue);

  /// Puts the real handler back.
  void dispose() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.textInput, null);
}
