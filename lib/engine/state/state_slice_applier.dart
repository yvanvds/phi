import '../../domain/project/entity_address.dart';
import '../../domain/state_machine/slices/clip_slice_entry.dart';

/// The write-side seam a state entry applies its captured slices through — the
/// mirror of [StateSliceSource]'s read side (design `docs/design/state-graph.md`
/// §4, issue #243).
///
/// Each method drives the *owning controller's* live performance state and
/// nothing else: values through the runtime-variable registry, tempos through
/// the clock binding, mix levels as live (engine-ramped) values, clip play/stop
/// through the sessions. Nothing here writes a payload or journals — application
/// is performance, not authorship (§8 decision 2). Implemented over the real
/// controllers by `EngineStateSliceApplier`; faked in tests so the ordered
/// application is provable without an engine.
abstract class StateSliceApplier {
  /// Set the runtime variable [name] to [value] through the registry. Returns
  /// whether the value could be applied — `false` when the variable is
  /// undefined or [value] is not one of its candidates (the caller surfaces
  /// the skip as a notice); `true` when it applied, including the no-op case
  /// where [value] was already current.
  bool applyVariable(String name, String value);

  /// Run the `domain.` clock at [domain] at [bpm] — a live override laid over
  /// the authored tempo, never a payload write.
  void applyTempo(EntityAddress domain, double bpm);

  /// Set the live level of the bus at [bus]: [volume] as the fader value and
  /// [muted] as the mute flag, ramped by the engine's fades. The authored
  /// `mix.` payload is untouched.
  void applyMix(
    EntityAddress bus, {
    required double volume,
    required bool muted,
  });

  /// Make the set of playing clips match [entries] — play each captured clip
  /// at its captured loop flag, stop every playing clip the capture does not
  /// name. Clips neither captured nor playing are untouched, so a
  /// captured-but-empty list stops everything ("no clips playing" is a
  /// meaningful constraint, design §4). Returns the captured clips that could
  /// not be brought to play (no decodable document) — the caller surfaces
  /// them as a notice.
  Set<EntityAddress> applyClips(List<ClipSliceEntry> entries);
}
