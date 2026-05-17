import 'package:flutter/foundation.dart';

import 'transport_state.dart';

/// Cross-cutting session state: transport intent, projection mode, scene
/// name. Owned by `PhiApp` for the duration of the run; passed alongside
/// `PhiEngine` to every chrome region that needs it.
///
/// Pure-Dart-ish — uses `ValueNotifier`/`ChangeNotifier` from
/// `package:flutter/foundation.dart` (no Flutter widgets), so this layer
/// is testable without a widget tree.
class SessionState {
  SessionState({String initialSceneName = 'untitled'})
    : sceneName = ValueNotifier<String>(initialSceneName);

  final ValueNotifier<TransportState> transport = ValueNotifier<TransportState>(
    TransportState.idle,
  );

  final ValueNotifier<bool> projection = ValueNotifier<bool>(false);

  final ValueNotifier<String> sceneName;

  bool get isPlaying => transport.value == TransportState.playing;

  void play() => transport.value = TransportState.playing;

  void stop() => transport.value = TransportState.idle;

  void toggleProjection() => projection.value = !projection.value;

  void renameScene(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    sceneName.value = trimmed;
  }

  void dispose() {
    transport.dispose();
    projection.dispose();
    sceneName.dispose();
  }
}
