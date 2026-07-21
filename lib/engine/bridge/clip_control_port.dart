import '../../domain/project/entity_address.dart';

/// The clip-session controller as the live-coding **control plane** sees it —
/// the receiving end of `phi.ctl.clip.*` commands (design
/// `docs/design/live-coding.md` §4, issue #233).
///
/// The [ControlPlaneDispatcher] decodes a tapped `phi.ctl` frame into one of
/// these calls and routes it here; the owning controller (clip sessions, epic
/// #183) resolves [target] — which may name a **single clip or a whole group**,
/// the dispatcher cannot and need not tell them apart — and starts/stops through
/// the *normal* session path, so a script-started clip is indistinguishable from
/// a UI-started one (design §4).
///
/// A port, not the controller itself: the dispatcher lands with a fake here so
/// the whole control plane is testable before epic #183 merges; the real wiring
/// (an adapter over the live session manager) activates as that epic lands.
abstract interface class ClipControlPort {
  /// Start the clip or group at [target] (`clip.x.play()` / `clip.drums.play()`).
  void play(EntityAddress target);

  /// Stop the clip or group at [target] (`clip.x.stop()` / group stop).
  void stop(EntityAddress target);

  /// Pause the clip or group at [target] (`clip.x.pause()`).
  void pause(EntityAddress target);

  /// Set looping [on] or off for the clip or group at [target]
  /// (`clip.x.loop()` / `clip.x.loop(False)`).
  void loop(EntityAddress target, {required bool on});

  /// Stop **every** playing clip — the namespace-wide `clip.stop()` (design §4
  /// "stop-all"), addressed at the `clip` root with no entity segments.
  void stopAll();
}
