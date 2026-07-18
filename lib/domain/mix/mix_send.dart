import '../project/entity_address.dart';

/// One aux send from a mix channel (or group bus) to a return bus — the routing
/// the engine's `send(slot, returnBus, level:, preFader:)` realises (design
/// `docs/design/mix.md` §4).
///
/// A send is identified by its **slot**, which is simply its index in the owning
/// [MixStrip]'s ordered `sends` list — the same convention the engine uses. The
/// [to] target must be a return bus; the mix domain validates that at edit time
/// (`SendTarget.isReturn`) so an illegal wiring never reaches the engine.
///
/// A plain, immutable value type: it (de)serialises to a JSON map and compares by
/// value so a payload round-trip is easy to assert. The address is stored in its
/// dotted string form (`mix.verb`) so the payload stays JSON-encodable — the
/// journal contract.
class MixSend {
  /// Builds a send. [level] is the send amount in `[0, 1]` (defaults to unity);
  /// [preFader] is `false` by default — sends are post-fader unless asked
  /// otherwise (design §2).
  const MixSend({required this.to, this.level = 1.0, this.preFader = false});

  /// Reads a send from a decoded map, tolerating missing keys by falling back to
  /// unity level, post-fader. Throws a [FormatException] if [to] is absent or not
  /// a well-formed address — a send with no destination is meaningless.
  factory MixSend.fromJson(Map<String, Object?> json) => MixSend(
    to: EntityAddress.parse(json['to'] as String),
    level: (json['level'] as num?)?.toDouble() ?? 1.0,
    preFader: json['preFader'] as bool? ?? false,
  );

  /// The return bus this send feeds — a top-level `mix.` entity carrying
  /// `return: true`.
  final EntityAddress to;

  /// The send amount in `[0.0, 1.0]`. A performance control: level drags are
  /// gesture-coalesced like fader drags (design §4).
  final double level;

  /// Whether the send is taken pre-fader. Post-fader by default (design §2).
  final bool preFader;

  MixSend copyWith({EntityAddress? to, double? level, bool? preFader}) =>
      MixSend(
        to: to ?? this.to,
        level: level ?? this.level,
        preFader: preFader ?? this.preFader,
      );

  /// The send as the JSON map stored inside a strip's `sends` list. The address
  /// is written in its dotted form so the payload stays JSON-encodable.
  Map<String, Object?> toJson() => {
    'to': to.format(),
    'level': level,
    'preFader': preFader,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MixSend &&
          other.to == to &&
          other.level == level &&
          other.preFader == preFader;

  @override
  int get hashCode => Object.hash(to, level, preFader);

  @override
  String toString() => 'MixSend(to: $to, level: $level, preFader: $preFader)';
}
