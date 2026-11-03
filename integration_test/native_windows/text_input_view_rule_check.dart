import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Watches the text input channel on its way to the **real** platform plugin
/// and checks the one rule a multi-window app can break: every call that needs
/// the client's view must find that view alive when the platform has handled
/// it (issues #481, #557).
///
/// The Windows embedder's `TextInputPlugin` remembers the `viewId` of the last
/// `TextInput.setClient`, and `setEditableSizeAndTransform`, `setMarkedTextRect`
/// and `clearClient` look that view up, failing with `Text input is not
/// available because view with view_id=N cannot be found` when it is gone.
/// Those calls are platform messages, while destroying a window is a
/// synchronous FFI call, so a window destroyed in the same turn its text field
/// detaches overtakes the detach. The Linux plugin does not check at all, so
/// without this a Linux run would pass code that fails on Windows.
///
/// Nothing is stood in for: each call goes on to the plugin and its answer comes
/// back to the framework unchanged, so on Windows the plugin's own failure still
/// fails the test. The check runs when the answer arrives, which is after the
/// platform handled the call. A destroy that overtook the call has happened by
/// then, and an answer that arrives first proves the view was alive.
class TextInputViewRuleCheck {
  TextInputViewRuleCheck(this._messenger) {
    _messenger.setMockMessageHandler(_channel, _forward);
  }

  static final String _channel = SystemChannels.textInput.name;
  static const JSONMethodCodec _codec = JSONMethodCodec();

  static const Set<String> _needsView = {
    'TextInput.setEditableSizeAndTransform',
    'TextInput.setMarkedTextRect',
    'TextInput.clearClient',
  };

  final TestDefaultBinaryMessenger _messenger;

  /// One line per call the Windows embedder would have failed.
  final List<String> errors = [];

  /// The open text input client, as the platform knows it, or null.
  int? clientId;

  /// The view the last `TextInput.setClient` named, or null.
  int? viewId;

  Future<ByteData?> _forward(ByteData? message) async {
    final call = _codec.decodeMethodCall(message);
    switch (call.method) {
      case 'TextInput.setClient':
        final arguments = call.arguments as List<Object?>;
        clientId = arguments[0]! as int;
        viewId = (arguments[1]! as Map<Object?, Object?>)['viewId'] as int?;
      case 'TextInput.clearClient':
        clientId = null;
    }
    final view = viewId;
    final reply = await _messenger.delegate.send(_channel, message);
    if (_needsView.contains(call.method) && view != null && !_isAlive(view)) {
      errors.add('${call.method}: view $view is gone');
    }
    return reply;
  }

  /// Asks the engine, not the test binding: only the engine's views count.
  bool _isAlive(int view) =>
      PlatformDispatcher.instance.views.any((v) => v.viewId == view);

  /// Takes this out of the channel again.
  void dispose() => _messenger.setMockMessageHandler(_channel, null);
}
