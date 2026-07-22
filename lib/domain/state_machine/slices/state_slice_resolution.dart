import '../../project/entity_address.dart';
import 'state_slices.dart';

/// The apply-time partition of a state's captured [StateSlices] into what can
/// still be applied and what now points at deleted entities (design
/// `docs/design/state-graph.md` §4, issue #242).
///
/// Slice entries are entity addresses, so a rename-refactor rewrites them —
/// but a *deleted* referent leaves a dangling address behind (the delete-impact
/// dialog warned). Entering the state must then degrade gracefully: the
/// surviving entries apply, the dangling ones are skipped, and the performer
/// sees a notice naming what was skipped. This value type is that partition;
/// the application engine (#243) consumes [applicable] and surfaces [missing].
///
/// Variables are names, not entities, so a captured variables map is always
/// applicable — an undefined name is the *registry's* graceful no-op, not a
/// dangling address. Uncaptured categories stay `null` and captured-but-empty
/// ones stay empty, so the resolution never changes what a state constrains.
class StateSliceResolution {
  const StateSliceResolution({required this.applicable, required this.missing});

  /// Partitions [slices] against [exists] — the registry's containment check.
  /// Entries whose referent exists are kept in [applicable]; the rest are
  /// dropped and their addresses collected into [missing].
  factory StateSliceResolution.of(
    StateSlices slices, {
    required bool Function(EntityAddress) exists,
  }) {
    final missing = <EntityAddress>{};
    List<T>? keep<T>(List<T>? entries, EntityAddress Function(T) referent) {
      if (entries == null) return null;
      final kept = <T>[];
      for (final entry in entries) {
        final address = referent(entry);
        if (exists(address)) {
          kept.add(entry);
        } else {
          missing.add(address);
        }
      }
      return kept;
    }

    final applicable = StateSlices(
      clips: keep(slices.clips, (e) => e.clip),
      mix: keep(slices.mix, (e) => e.bus),
      variables: slices.variables,
      tempos: keep(slices.tempos, (e) => e.domain),
    );
    return StateSliceResolution(
      applicable: applicable,
      missing: Set.unmodifiable(missing),
    );
  }

  /// The captured slices with every dangling entry dropped — what #243's
  /// ordered application actually applies.
  final StateSlices applicable;

  /// The addresses of deleted referents whose entries were dropped — what the
  /// notice names. Empty when everything resolved.
  final Set<EntityAddress> missing;

  /// Whether anything was dropped — the notice trigger.
  bool get hasMissing => missing.isNotEmpty;
}
