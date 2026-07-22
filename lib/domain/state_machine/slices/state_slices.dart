import 'package:flutter/foundation.dart';

import '../../project/entity_address.dart';
import 'clip_slice_entry.dart';
import 'mix_slice_entry.dart';
import 'state_slice_category.dart';
import 'tempo_slice_entry.dart';

/// The explicitly captured, per-category slices a `state.` entity carries —
/// what the state constrains when it goes live (design
/// `docs/design/state-graph.md` §4, issue #240).
///
/// Never an automatic whole-world snapshot: each of the four v1 categories is
/// captured (or cleared) on its own, and an **uncaptured category is `null`**
/// — left untouched on entry. A captured-but-empty list is meaningful ("no
/// clips playing" stops everything the state knows about), so `null` and
/// `[]`/`{}` are distinct and both round-trip.
///
/// This is the payload's data model; capture-from-live and per-entry editing
/// land with issue #242, application with #243. Immutable — replace via
/// [copyWith].
class StateSlices {
  const StateSlices({this.clips, this.mix, this.variables, this.tempos});

  /// Rebuilds slices from the map [toJson] produced. Absent categories stay
  /// `null` (uncaptured). Throws a [FormatException] on a malformed entry.
  factory StateSlices.fromJson(Map<String, Object?> json) => StateSlices(
    clips: (json['clips'] as List?)
        ?.map((e) => ClipSliceEntry.fromJson((e as Map).cast()))
        .toList(),
    mix: (json['mix'] as List?)
        ?.map((e) => MixSliceEntry.fromJson((e as Map).cast()))
        .toList(),
    variables: _stringMap(json['variables']),
    tempos: (json['tempos'] as List?)
        ?.map((e) => TempoSliceEntry.fromJson((e as Map).cast()))
        .toList(),
  );

  static Map<String, String>? _stringMap(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw const FormatException('A "variables" slice must be a map.');
    }
    return {
      for (final entry in raw.entries)
        entry.key as String: entry.value is String
            ? entry.value as String
            : throw FormatException(
                'Variable "${entry.key}" must capture a string value.',
              ),
    };
  }

  /// The all-uncaptured slices — every fresh state starts here.
  static const StateSlices empty = StateSlices();

  /// The captured set of playing clips (+ loop flags), or `null` when the
  /// category is uncaptured.
  final List<ClipSliceEntry>? clips;

  /// The captured volume/mute per chosen bus, or `null` when uncaptured.
  final List<MixSliceEntry>? mix;

  /// The captured runtime-variable values (`name → value`, string values per
  /// the issue-#78 decision), or `null` when uncaptured.
  final Map<String, String>? variables;

  /// The captured per-domain tempos, or `null` when uncaptured.
  final List<TempoSliceEntry>? tempos;

  /// Whether nothing is captured — every category `null`.
  bool get isEmpty =>
      clips == null && mix == null && variables == null && tempos == null;

  /// The addresses the captured entries point at — clip entities, mix buses
  /// and tempo domains. Variable names are not entities, so they contribute
  /// nothing. Feeds [StateDocument.references].
  Set<EntityAddress> get references => {
    ...?clips?.map((e) => e.clip),
    ...?mix?.map((e) => e.bus),
    ...?tempos?.map((e) => e.domain),
  };

  /// A copy with every captured reference to [from] repointed to [to] — the
  /// refactor step a rename/move of a clip, bus or domain applies. Uncaptured
  /// categories stay `null`.
  StateSlices withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      StateSlices(
        clips: clips?.map((e) => e.withReferenceUpdated(from, to)).toList(),
        mix: mix?.map((e) => e.withReferenceUpdated(from, to)).toList(),
        variables: variables,
        tempos: tempos?.map((e) => e.withReferenceUpdated(from, to)).toList(),
      );

  /// Whether [category] is captured on this state. A captured-but-empty
  /// list/map counts — it constrains ("nothing playing"), unlike `null`.
  bool isCaptured(StateSliceCategory category) => switch (category) {
    StateSliceCategory.clips => clips != null,
    StateSliceCategory.mix => mix != null,
    StateSliceCategory.variables => variables != null,
    StateSliceCategory.tempos => tempos != null,
  };

  /// A copy with [category] back to uncaptured (`null`) — entering the state
  /// then leaves that category untouched. The other categories are unchanged.
  StateSlices cleared(StateSliceCategory category) => switch (category) {
    StateSliceCategory.clips => copyWith(clearClips: true),
    StateSliceCategory.mix => copyWith(clearMix: true),
    StateSliceCategory.variables => copyWith(clearVariables: true),
    StateSliceCategory.tempos => copyWith(clearTempos: true),
  };

  // ─── per-entry editing (issue #242) ───────────────────────────────────────
  //
  // Remove one captured entry without recapturing the category. Removing the
  // last entry keeps the category captured-but-empty — the performer edited
  // the capture down, they did not un-capture it. Each returns `this` when
  // the category is uncaptured or the entry is absent.

  /// A copy without the clips entry for [clip].
  StateSlices withoutClip(EntityAddress clip) {
    final entries = clips;
    if (entries == null || !entries.any((e) => e.clip == clip)) return this;
    return copyWith(
      clips: [
        for (final e in entries)
          if (e.clip != clip) e,
      ],
    );
  }

  /// A copy without the mix entry for [bus].
  StateSlices withoutBus(EntityAddress bus) {
    final entries = mix;
    if (entries == null || !entries.any((e) => e.bus == bus)) return this;
    return copyWith(
      mix: [
        for (final e in entries)
          if (e.bus != bus) e,
      ],
    );
  }

  /// A copy without the captured variable named [name].
  StateSlices withoutVariable(String name) {
    final captured = variables;
    if (captured == null || !captured.containsKey(name)) return this;
    return copyWith(
      variables: {
        for (final entry in captured.entries)
          if (entry.key != name) entry.key: entry.value,
      },
    );
  }

  /// A copy without the tempo entry for [domain].
  StateSlices withoutTempo(EntityAddress domain) {
    final entries = tempos;
    if (entries == null || !entries.any((e) => e.domain == domain)) return this;
    return copyWith(
      tempos: [
        for (final e in entries)
          if (e.domain != domain) e,
      ],
    );
  }

  /// A copy with the given categories replaced. Passing a value captures (or
  /// re-captures) that category; the paired `clear…` flag un-captures it back
  /// to `null` — needed because `null` already means "keep the current one".
  StateSlices copyWith({
    List<ClipSliceEntry>? clips,
    bool clearClips = false,
    List<MixSliceEntry>? mix,
    bool clearMix = false,
    Map<String, String>? variables,
    bool clearVariables = false,
    List<TempoSliceEntry>? tempos,
    bool clearTempos = false,
  }) => StateSlices(
    clips: clearClips ? null : (clips ?? this.clips),
    mix: clearMix ? null : (mix ?? this.mix),
    variables: clearVariables ? null : (variables ?? this.variables),
    tempos: clearTempos ? null : (tempos ?? this.tempos),
  );

  /// The slices as their JSON map. Uncaptured categories are omitted, so the
  /// empty slices encode as `{}`.
  Map<String, Object?> toJson() => {
    if (clips != null) 'clips': [for (final e in clips!) e.toJson()],
    if (mix != null) 'mix': [for (final e in mix!) e.toJson()],
    if (variables != null) 'variables': variables,
    if (tempos != null) 'tempos': [for (final e in tempos!) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateSlices &&
          listEquals(other.clips, clips) &&
          listEquals(other.mix, mix) &&
          mapEquals(other.variables, variables) &&
          listEquals(other.tempos, tempos);

  @override
  int get hashCode => Object.hash(
    clips == null ? null : Object.hashAll(clips!),
    mix == null ? null : Object.hashAll(mix!),
    variables == null
        ? null
        : Object.hashAllUnordered(
            variables!.entries.map((e) => Object.hash(e.key, e.value)),
          ),
    tempos == null ? null : Object.hashAll(tempos!),
  );
}
