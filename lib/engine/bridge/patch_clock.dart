/// A named engine domain clock that Phi publishes for patches to follow
/// (issue #529).
///
/// Patcher clock objects (`.when`, `.timepoint`, `.tempo`, `.translate`, and
/// `.metro` / `.delay` / `.clocker` after `clock <name>`) find an engine clock
/// by [name]. Phi mints one per time domain through
/// [PatcherGateway.publishClock] and keeps its tempo in step with the domain;
/// this is the handle it keeps to do that. Production wraps a `package:yse`
/// `DomainClock` (see `real_patch_clock.dart`); tests use a fake.
abstract interface class PatchClock {
  /// The engine name patches bind to, e.g. `domain.drum`.
  String get name;

  /// Set the clock's tempo in BPM, at once.
  void setTempo(double bpm);

  /// The clock's beat position: beats counted since it was published.
  double get beatPosition;

  /// The clock's current tempo in BPM, as the engine reports it.
  double get currentTempo;

  /// Destroy the clock in the engine. Objects still bound to it read a frozen
  /// beat. Idempotent.
  void dispose();
}
