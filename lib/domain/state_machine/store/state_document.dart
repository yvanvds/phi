import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../project/entity_address.dart';
import '../../project/reference_source.dart';
import '../slices/state_slices.dart';
import 'state_transition_spec.dart';

/// The complete persistable payload of a `state.` entity (design
/// `docs/design/state-graph.md` §3–§4, issue #240):
///
/// - [position] — the node's canvas position (the patcher precedent: layout
///   rides the entity).
/// - [transitions] — the **ordered** outbound transitions, each `{to, trigger,
///   label}` with the target as an entity address.
/// - [slices] — the explicitly captured per-category slices (§4 table).
/// - [onEnter] — an optional `code.` entity evaluated on entry (missing
///   references degrade gracefully — issue #243's concern).
///
/// Which state is *live* is deliberately **not** here: firing a transition is
/// performance, not authorship (§8 decision 2), so live-ness never persists —
/// a loaded project starts on the seeded default, keyed by the registry-backed
/// controller (issue #241).
///
/// **A [ReferenceSource].** A state points at its transition targets (and any
/// timed trigger's `domain.` clock), its on-enter `code.` script, and its
/// slice entries' clips / buses / domains — so those edges feed the registry's
/// back-reference index: delete-impact on a state lists its inbound
/// transitions, and rename-refactor rewrites them. Like every other kind the
/// *stored* payload is the JSON map (`toJson`, the journal contract) with the
/// references declared alongside; this typed view is what controllers decode,
/// edit and re-declare through (the [VoiceDefinition] pattern).
class StateDocument implements ReferenceSource {
  const StateDocument({
    this.position = Offset.zero,
    this.transitions = const [],
    this.slices = StateSlices.empty,
    this.onEnter,
  });

  /// Rebuilds a document from the map [toJson] produced. Absent keys default
  /// (origin position, no transitions, uncaptured slices, no on-enter);
  /// malformed addresses or entries throw a [FormatException] so a corrupt
  /// state file fails loudly.
  factory StateDocument.fromJson(Map<String, Object?> json) {
    final position = json['position'];
    final onEnter = json['onEnter'] as String?;
    return StateDocument(
      position: position is Map
          ? Offset(
              ((position['x'] as num?) ?? 0).toDouble(),
              ((position['y'] as num?) ?? 0).toDouble(),
            )
          : Offset.zero,
      transitions: [
        for (final raw in (json['transitions'] as List?) ?? const [])
          StateTransitionSpec.fromJson((raw as Map).cast<String, Object?>()),
      ],
      slices: json['slices'] is Map
          ? StateSlices.fromJson((json['slices'] as Map).cast())
          : StateSlices.empty,
      onEnter: onEnter == null ? null : EntityAddress.parse(onEnter),
    );
  }

  /// The node's top-left canvas position.
  final Offset position;

  /// The ordered outbound transitions, sourced from this state.
  final List<StateTransitionSpec> transitions;

  /// The captured slices — what this state constrains on entry.
  final StateSlices slices;

  /// The `code.` entity evaluated on entry, or `null` for none.
  final EntityAddress? onEnter;

  /// Every address this state points at: transition targets, trigger domains,
  /// the on-enter script, and slice entries' clips / buses / domains.
  @override
  Set<EntityAddress> get references => {
    for (final t in transitions) ...t.references,
    ...slices.references,
    ?onEnter,
  };

  /// A copy with every reference to [from] repointed to [to] — the refactor
  /// step a rename/move triggers. Applying the inverse restores the original,
  /// so undo round-trips.
  @override
  StateDocument withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      StateDocument(
        position: position,
        transitions: [
          for (final t in transitions) t.withReferenceUpdated(from, to),
        ],
        slices: slices.withReferenceUpdated(from, to),
        onEnter: onEnter == from ? to : onEnter,
      );

  /// A copy with the given fields replaced. [clearOnEnter] un-sets the
  /// on-enter script (a `null` [onEnter] means "keep the current one").
  StateDocument copyWith({
    Offset? position,
    List<StateTransitionSpec>? transitions,
    StateSlices? slices,
    EntityAddress? onEnter,
    bool clearOnEnter = false,
  }) => StateDocument(
    position: position ?? this.position,
    transitions: transitions ?? this.transitions,
    slices: slices ?? this.slices,
    onEnter: clearOnEnter ? null : (onEnter ?? this.onEnter),
  );

  /// The document as its JSON map — the stored payload form. Keys are in a
  /// stable order; the slices key is omitted when nothing is captured and the
  /// on-enter key when unset, so a minimal state stays minimal on disk.
  Map<String, Object?> toJson() => {
    'position': {'x': position.dx, 'y': position.dy},
    'transitions': [for (final t in transitions) t.toJson()],
    if (!slices.isEmpty) 'slices': slices.toJson(),
    if (onEnter != null) 'onEnter': onEnter!.format(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateDocument &&
          other.position == position &&
          listEquals(other.transitions, transitions) &&
          other.slices == slices &&
          other.onEnter == onEnter;

  @override
  int get hashCode =>
      Object.hash(position, Object.hashAll(transitions), slices, onEnter);

  @override
  String toString() =>
      'StateDocument(position: $position, '
      'transitions: ${transitions.length}, slices: ${slices.toJson()}, '
      'onEnter: $onEnter)';
}
