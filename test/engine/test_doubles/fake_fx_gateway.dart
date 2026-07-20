import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/engine/bridge/fx_chain.dart';
import 'package:phi/engine/bridge/fx_gateway.dart';
import 'package:phi/engine/bridge/materialised_fx.dart';

/// In-memory [FxGateway] used in unit, widget, and integration tests.
///
/// Mints [FakeMaterialisedFx] handles and [FakeFxChain]s that model the whole
/// surface — per-kind materialisation, live-vs-rebuild re-application, and
/// cycle-safe chain build/reorder/detach — without touching `package:yse`.
/// Mirrors `FakeSynthGateway` for the fx side. Tests reach the minted objects
/// through [handles] / [chains].
class FakeFxGateway implements FxGateway {
  /// Every handle minted by [materialiseFx], in creation order.
  final List<FakeMaterialisedFx> handles = [];

  /// Every chain minted by [createChain], in creation order.
  final List<FakeFxChain> chains = [];

  /// The most recently minted handle, or `null` before the first call.
  FakeMaterialisedFx? get lastHandle => handles.isEmpty ? null : handles.last;

  @override
  MaterialisedFx materialiseFx(FxDefinition definition) {
    final fx = FakeMaterialisedFx(definition);
    handles.add(fx);
    return fx;
  }

  @override
  FxChain createChain({required int busChannelId}) {
    final chain = FakeFxChain(busChannelId);
    chains.add(chain);
    return chain;
  }
}

/// The [MaterialisedFx] a [FakeFxGateway] mints.
///
/// Records the lifecycle so tests can assert it: [materialiseCount] rises on
/// every (re)build (starts at 1), [liveApplyCount] on every in-place same-kind
/// param apply, and [calls] keeps an ordered log
/// (`materialise:<kind>` / `apply:<kind>` / `dispose`). Mirrors the real handle:
/// a same-kind edit applies live; a kind change rebuilds.
class FakeMaterialisedFx implements MaterialisedFx {
  FakeMaterialisedFx(this._definition) {
    calls.add('materialise:${_definition.kind.name}');
  }

  FxDefinition _definition;
  bool _disposed = false;

  /// How many times the effect was (re)built — 1 at construction, +1 per
  /// kind-changing edit.
  int materialiseCount = 1;

  /// How many same-kind edits were applied in place (click-free setters).
  int liveApplyCount = 0;

  /// Ordered lifecycle log — see the class doc for the vocabulary.
  final List<String> calls = [];

  @override
  FxKind get kind => _definition.kind;

  @override
  FxDefinition get definition => _definition;

  @override
  bool get isPlaceable => _definition.kind != FxKind.patcherInsert;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  @override
  void applyDefinition(FxDefinition next) {
    if (next.kind != _definition.kind) {
      materialiseCount++;
      calls.add('materialise:${next.kind.name}');
    } else {
      liveApplyCount++;
      calls.add('apply:${next.kind.name}');
    }
    _definition = next;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calls.add('dispose');
  }
}

/// The [FxChain] a [FakeFxGateway] mints.
///
/// Faithfully simulates the real chain's cycle-safe linking discipline so a
/// test can prove reorder never closes a cycle *without* `package:yse`: it keeps
/// a persistent `next` map (identity → identity) and a terminator sentinel, and
/// [setInserts] re-links every placeable handle to its successor (the next
/// insert, or the terminator for the last). [walkFromHead] then follows those
/// links from the head — matching what the engine would traverse — and detects a
/// cycle, so a broken discipline surfaces as a failed walk. [attached] reports
/// whether a head is on the bus.
class FakeFxChain implements FxChain {
  FakeFxChain(this.busChannelId);

  @override
  final int busChannelId;

  /// Sentinel standing in for the real bypassed terminator DspObject.
  final Object _terminator = Object();

  /// Persistent forward links, exactly as the real `DspObject.link` leaves
  /// them — never wholesale-cleared, only overwritten per element, so a stale
  /// edge would survive here just as it would in the engine.
  final Map<Object, Object> _next = {};

  final List<FakeMaterialisedFx> _inserts = [];
  Object? _head;
  bool _attached = false;
  bool _disposed = false;

  @override
  List<MaterialisedFx> get inserts => List.unmodifiable(_inserts);

  /// Whether a head is currently attached to the bus.
  bool get attached => _attached;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  @override
  void setInserts(List<MaterialisedFx> ordered) {
    final placeable = [
      for (final fx in ordered)
        if (fx.isPlaceable && fx is FakeMaterialisedFx) fx,
    ];
    _inserts
      ..clear()
      ..addAll(placeable);

    if (placeable.isEmpty) {
      _head = null;
      _attached = false;
      return;
    }
    for (var i = 0; i < placeable.length; i++) {
      _next[placeable[i]] = i + 1 < placeable.length
          ? placeable[i + 1]
          : _terminator;
    }
    _head = placeable.first;
    _attached = true;
  }

  /// The handles reachable by following the links from the head, in order —
  /// what the engine's audio thread would traverse. Throws [StateError] if the
  /// links form a cycle (never terminating at the terminator).
  List<FakeMaterialisedFx> walkFromHead() {
    final walked = <FakeMaterialisedFx>[];
    var node = _head;
    // A correct chain visits each placed handle once then hits the terminator;
    // cap the walk one past that to catch a cycle instead of looping forever.
    final limit = _inserts.length + 1;
    while (node != null && node != _terminator) {
      if (walked.length > limit) {
        throw StateError('fx chain links form a cycle');
      }
      walked.add(node as FakeMaterialisedFx);
      node = _next[node];
    }
    return walked;
  }

  @override
  void dispose() {
    _head = null;
    _attached = false;
    _inserts.clear();
    _disposed = true;
  }
}
