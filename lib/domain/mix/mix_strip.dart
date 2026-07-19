import '../project/entity_address.dart';
import '../project/reference_source.dart';
import 'mix_send.dart';

/// The persisted state of a mix channel — a `mix.` registry entity's (or group
/// bus's) payload (design `docs/design/project-registry.md` §2 and
/// `docs/design/mix.md` §3–§4).
///
/// A strip carries what must survive a save/reload: its voice-swatch [voice], the
/// live mixing state the performer dials in ([volume], [muted], [soloed]),
/// whether it is a return bus ([isReturn]), and its ordered aux [sends].
///
/// **One name, re-aligned (issue #166, design §10 decision 1).** A strip has no
/// display-name field: it is named by its entity **address leaf** (`mix.kick` →
/// `kick`), so the stored payload and the live address can never disagree. A
/// pre-#166 payload's `name` key is simply no longer read — no compat shim, no
/// migration.
///
/// **Sends, inserts and the back-reference index (design §4).** A strip points at
/// return buses through its [sends] and at `fx.` instances through its ordered
/// [inserts] list (`mix.inserts → fx`, racks design §5), so [MixStrip] is a
/// [ReferenceSource]: its [references] are the send targets *and* the insert
/// effects (feeding delete-impact and rename-refactor), and [withReferenceUpdated]
/// rewrites a send's `to` or an insert address when its target is renamed or
/// moved.
///
/// A plain, immutable value type. It (de)serialises to a JSON map so the strip is
/// journal-friendly (a `mix.` entity is created and edited through the ordinary
/// registry command layer, whose `toJson` must be JSON-encodable) and compares by
/// value so a round-trip is easy to assert.
class MixStrip implements ReferenceSource {
  /// Builds a strip. [voice] is the 1..6 swatch index; it is not range-checked
  /// here (the engine assigns it). [volume] is the user-set fader value in
  /// `[0, 1]`; [muted]/[soloed] default to off; [isReturn] defaults to a normal
  /// channel; [sends] defaults to none — a fresh channel is at unity, unmuted,
  /// unsoloed, not a return, with no sends.
  const MixStrip({
    required this.voice,
    this.volume = 1.0,
    this.muted = false,
    this.soloed = false,
    this.isReturn = false,
    this.sends = const [],
    this.inserts = const [],
  });

  /// Reads a strip from a decoded payload map, tolerating missing keys by
  /// falling back to sensible defaults so a hand-edited or older file still
  /// loads. Any legacy `name` key is ignored (issue #166 — one-name re-alignment).
  factory MixStrip.fromJson(Map<String, Object?> json) => MixStrip(
    voice: (json['voice'] as num?)?.toInt() ?? 1,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    muted: json['muted'] as bool? ?? false,
    soloed: json['soloed'] as bool? ?? false,
    isReturn: json['return'] as bool? ?? false,
    sends: [
      for (final send in (json['sends'] as List<Object?>? ?? const []))
        MixSend.fromJson((send as Map).cast<String, Object?>()),
    ],
    inserts: [
      for (final insert in (json['inserts'] as List<Object?>? ?? const []))
        EntityAddress.parse(insert as String),
    ],
  );

  /// The voice-swatch index in `[1, 6]`.
  final int voice;

  /// The user-set fader volume in `[0.0, 1.0]` — what the performer dialled in,
  /// independent of the *effective* gateway volume mute/solo may collapse it to.
  final double volume;

  /// Whether the channel is muted.
  final bool muted;

  /// Whether the channel is soloed.
  final bool soloed;

  /// Whether this strip is a **return bus** (a top-level aux beside master,
  /// design §4). Only a return may be the target of a send; returns are exempt
  /// from solo (design §5).
  final bool isReturn;

  /// The channel's aux sends, in slot order (slot = list index). Each targets a
  /// return bus; the mix domain validates that at edit time.
  final List<MixSend> sends;

  /// The channel's insert effects, in chain order (design racks §5). Each is the
  /// address of an `fx.` instance; the ordered list is materialised as a linked
  /// `DspObject` chain. An instance sits on at most one bus, enforced through the
  /// back-reference index (the placement UI + move-with-impact land in a later
  /// issue; the domain schema and edges are here).
  final List<EntityAddress> inserts;

  /// The addresses this strip points at — its send targets *and* its insert
  /// effects — feeding the registry's back-reference index (design §4).
  @override
  Set<EntityAddress> get references => {
    for (final send in sends) send.to,
    ...inserts,
  };

  /// A copy with every send target *and* insert address equal to [from]
  /// repointed to [to] — the refactor a return's or an fx's rename/move triggers.
  /// Applying the inverse restores the original, so undo round-trips.
  @override
  MixStrip withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      copyWith(
        sends: [
          for (final send in sends)
            send.to == from ? send.copyWith(to: to) : send,
        ],
        inserts: [for (final insert in inserts) insert == from ? to : insert],
      );

  MixStrip copyWith({
    int? voice,
    double? volume,
    bool? muted,
    bool? soloed,
    bool? isReturn,
    List<MixSend>? sends,
    List<EntityAddress>? inserts,
  }) => MixStrip(
    voice: voice ?? this.voice,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    soloed: soloed ?? this.soloed,
    isReturn: isReturn ?? this.isReturn,
    sends: sends ?? this.sends,
    inserts: inserts ?? this.inserts,
  );

  /// The strip as the JSON map stored in the `mix.` entity's (or group bus's)
  /// payload. Keys are emitted in a stable order so re-encoding an unchanged
  /// strip is byte-identical (the persistence de-dupe relies on it). Insert
  /// addresses are written in dotted form so the payload stays JSON-encodable.
  Map<String, Object?> toJson() => {
    'voice': voice,
    'volume': volume,
    'muted': muted,
    'soloed': soloed,
    'return': isReturn,
    'sends': [for (final send in sends) send.toJson()],
    'inserts': [for (final insert in inserts) insert.format()],
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MixStrip &&
          other.voice == voice &&
          other.volume == volume &&
          other.muted == muted &&
          other.soloed == soloed &&
          other.isReturn == isReturn &&
          _sendsEqual(other.sends, sends) &&
          _insertsEqual(other.inserts, inserts);

  @override
  int get hashCode => Object.hash(
    voice,
    volume,
    muted,
    soloed,
    isReturn,
    Object.hashAll(sends),
    Object.hashAll(inserts),
  );

  @override
  String toString() =>
      'MixStrip(voice: $voice, volume: $volume, muted: $muted, '
      'soloed: $soloed, isReturn: $isReturn, sends: $sends, inserts: $inserts)';

  /// Element-wise list equality — `List.==` is identity, and the domain stays
  /// Flutter-free so it cannot borrow `foundation`'s `listEquals`.
  static bool _sendsEqual(List<MixSend> a, List<MixSend> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Element-wise insert-list equality (order matters — the chain is ordered).
  static bool _insertsEqual(List<EntityAddress> a, List<EntityAddress> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
