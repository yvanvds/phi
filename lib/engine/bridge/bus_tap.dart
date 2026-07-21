import 'dart:async';

/// Port for the engine's **host bus tap** — the outbound channel that delivers
/// script-bus publishes back to the host (design `docs/design/live-coding.md`
/// §4, §9).
///
/// The live-coding control plane publishes structural verbs to a reserved
/// `phi.ctl.*` address; the host taps that prefix, receives the `(address,
/// value)` frames, and dispatches each to the owning controller (clip sessions,
/// voices, the state machine, variables, the tempo stack). This is the seam
/// that carries those frames.
///
/// **The real implementation is an engine dependency that has not landed yet.**
/// The C API — subscribe the host to a bus-address prefix, delivering values on
/// the main thread during `update()`, mirroring the `yse_set_script_error_callback`
/// pattern — is filed on `yvanvds/yse-soundengine` (#389, blocking) and wrapped
/// in `dart-yse` (#43). Until those land, production wires a [NoOpBusTap] and
/// tests drive a fake publish through a `FakeBusTap`, so the whole control plane
/// downstream is testable now (design §9 step 1).
///
/// Frame delivery is prefix-scoped, exactly as the C API will be: a subscriber
/// for `phi.ctl` receives `phi.ctl` and any `phi.ctl.<...>` publish, and nothing
/// else.
abstract interface class BusTap {
  /// Subscribe to bus frames whose [address] is [prefix] or begins with
  /// `<prefix>.` (segment-aware — `phi.ctl` matches `phi.ctl.clip.play`, not
  /// `phi.ctlx`). The returned stream is a broadcast stream; late joiners miss
  /// earlier frames, matching the engine's fire-and-forget delivery.
  Stream<BusTapFrame> subscribe(String prefix);

  /// Release any native subscription and close the streams. Safe to call more
  /// than once.
  Future<void> dispose();
}

/// One tapped publish: the full bus [address] and its typed [value].
class BusTapFrame {
  const BusTapFrame(this.address, this.value);

  /// The full bus address the value was published to, e.g.
  /// `phi.ctl.clip.drums.play`.
  final String address;

  /// The published value, as one of the four bus value types ([BusValue]).
  final BusValue value;

  @override
  bool operator ==(Object other) =>
      other is BusTapFrame && other.address == address && other.value == value;

  @override
  int get hashCode => Object.hash(address, value);

  @override
  String toString() => 'BusTapFrame($address, $value)';
}

/// A value carried on the script bus — one of the engine's four bus value types
/// (yse DSL spec): [BusInt], [BusFloat], [BusString], [BusFloatList]. A sealed
/// hierarchy so a dispatcher can pattern-match exhaustively.
sealed class BusValue {
  const BusValue();
}

/// An `int` bus value.
class BusInt extends BusValue {
  const BusInt(this.value);
  final int value;

  @override
  bool operator ==(Object other) => other is BusInt && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BusInt($value)';
}

/// A `float` bus value.
class BusFloat extends BusValue {
  const BusFloat(this.value);
  final double value;

  @override
  bool operator ==(Object other) => other is BusFloat && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BusFloat($value)';
}

/// A `str` bus value.
class BusString extends BusValue {
  const BusString(this.value);
  final String value;

  @override
  bool operator ==(Object other) => other is BusString && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BusString($value)';
}

/// A `list[float]` bus value.
class BusFloatList extends BusValue {
  const BusFloatList(this.values);
  final List<double> values;

  @override
  bool operator ==(Object other) =>
      other is BusFloatList && _listEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(values);

  @override
  String toString() => 'BusFloatList($values)';
}

bool _listEquals(List<double> a, List<double> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether [address] falls under [prefix] — an exact match, or a `<prefix>.`
/// child (segment-aware). Shared by tap implementations so the host and its
/// fakes agree on what a prefix subscription covers.
bool busAddressMatchesPrefix(String address, String prefix) =>
    address == prefix || address.startsWith('$prefix.');
