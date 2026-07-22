import '../../domain/state_machine/slices/clip_slice_entry.dart';
import '../../domain/state_machine/slices/mix_slice_entry.dart';
import '../../domain/state_machine/slices/tempo_slice_entry.dart';

/// What the live performance currently holds, per slice category — the seam
/// `StateMachineController.captureSlice` reads when the performer presses a
/// per-category capture button (design `docs/design/state-graph.md` §4, issue
/// #242).
///
/// Each method reads the *owning controller's* current state at call time:
/// the playing clip sessions, the materialised mix buses, the runtime-variable
/// registry, and the `domain.` tempos. Implemented over the real controllers
/// by `EngineStateSliceSource`; faked in tests so capture correctness is
/// provable without an engine.
abstract class StateSliceSource {
  /// The clips slice of the live performance: one entry per playing clip
  /// entity, carrying its live loop flag. Empty when nothing plays —
  /// capturing that is the meaningful "no clips playing" constraint.
  List<ClipSliceEntry> captureClips();

  /// The mix slice: one entry per live bus (strips and group buses), carrying
  /// its current volume and mute.
  List<MixSliceEntry> captureMix();

  /// The variables slice: the runtime-variable registry's current
  /// `name → value` map.
  Map<String, String> captureVariables();

  /// The tempos slice: one entry per `domain.` entity, carrying its tempo.
  List<TempoSliceEntry> captureTempos();
}
