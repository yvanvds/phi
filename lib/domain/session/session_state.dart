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

  /// Session tempo in beats-per-minute. Drives MIDI playback (issue #29);
  /// no toolbar control yet — the time-domain layer owns tempo UI later.
  final ValueNotifier<double> tempo = ValueNotifier<double>(120);

  final ValueNotifier<String> sceneName;

  /// Master-strip volume in `[0.0, 1.0]`. Master is not a registry entity, so its
  /// state lives in the project manifest (design `docs/design/mix.md` §3); this is
  /// the in-memory carrier the [ProjectController] round-trips through it, exactly
  /// like [tempo] and [sceneName]. The engine's master fader mirrors it.
  final ValueNotifier<double> masterVolume = ValueNotifier<double>(1);

  /// Whether the master strip is muted — persisted alongside [masterVolume].
  final ValueNotifier<bool> masterMuted = ValueNotifier<bool>(false);

  /// Cross-surface selection. Whichever surface publishes here, every
  /// other chrome region (notably the right inspector) can watch and
  /// react. Holds anything — a `StateEntitySelection`, a `PatchNode`, a
  /// `MidiClip`, etc. — keyed by reference.
  final ValueNotifier<Object?> selection = ValueNotifier<Object?>(null);

  bool get isPlaying => transport.value == TransportState.playing;

  void play() => transport.value = TransportState.playing;

  void stop() => transport.value = TransportState.idle;

  void toggleProjection() => projection.value = !projection.value;

  /// Set the session tempo. Ignores non-positive values.
  void setTempo(double bpm) {
    if (bpm <= 0) return;
    tempo.value = bpm;
  }

  void renameScene(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    sceneName.value = trimmed;
  }

  /// Set the master-strip volume, clamped to `[0.0, 1.0]`.
  void setMasterVolume(double value) =>
      masterVolume.value = value.clamp(0.0, 1.0);

  /// Mute or unmute the master strip.
  void setMasterMuted(bool value) => masterMuted.value = value;

  /// Publish a selection. Pass `null` (or call [clearSelection]) to
  /// unset.
  void select(Object? value) => selection.value = value;

  /// Clear the cross-surface selection.
  void clearSelection() => selection.value = null;

  void dispose() {
    transport.dispose();
    projection.dispose();
    tempo.dispose();
    sceneName.dispose();
    masterVolume.dispose();
    masterMuted.dispose();
    selection.dispose();
  }
}
