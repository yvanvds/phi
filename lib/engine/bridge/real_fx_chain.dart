import 'package:yse/yse.dart';

import 'fx_chain.dart';
import 'materialised_fx.dart';
import 'real_materialised_fx.dart';
import 'real_materialised_synth.dart' show MixBusResolver;

/// Production [FxChain] backed by `package:yse` (design
/// `docs/design/racks-and-voices.md` §5).
///
/// Links the placeable [RealMaterialisedFx] handles a bus's `inserts` resolve to
/// into a `DspObject` chain and attaches the head to the bus's [Channel] via
/// `Channel.dsp` (pre-fader). The [Channel] comes from the [MixBusResolver] the
/// gateway owns — the bridge stays the only place a real [Channel] is handled.
///
/// **Cycle-safe reorder without a wrapper unlink.** `DspObject.link` sets a
/// forward `next`; the wrapper cannot clear it (`link(NULL)` exists natively —
/// filed **yvanvds/dart-yse#42**). A plain re-link would leave a former
/// non-tail element pointing at a now-earlier element and close a cycle. So this
/// chain keeps a permanent bypassed **terminator** `DspObject` as the tail: on
/// every [setInserts] each real object is linked to its successor (the next
/// insert, or the terminator for the last), and the terminator — always last,
/// never linked onward — keeps its `next` null. Every prior edge is thus
/// overwritten and the walk always ends at the terminator, so no stale edge or
/// cycle survives. The terminator is bypassed, so it passes the chain output
/// through unchanged.
class RealFxChain implements FxChain {
  /// Binds an empty chain to [busChannelId], resolving the live [Channel]
  /// lazily through [_busResolver] on each (re)placement.
  RealFxChain(this.busChannelId, MixBusResolver busResolver)
    : _busResolver = busResolver;

  @override
  final int busChannelId;

  final MixBusResolver _busResolver;

  /// The permanent chain tail — a bypassed (passthrough) filter that gives the
  /// last real insert a stable `next` to link to (see the class doc). Built
  /// lazily so an all-empty chain (never placed) allocates nothing.
  DspObject? _terminator;

  final List<RealMaterialisedFx> _inserts = [];
  bool _attached = false;

  @override
  List<MaterialisedFx> get inserts => List.unmodifiable(_inserts);

  Channel get _channel => _busResolver(busChannelId) ?? Channel.master;

  DspObject _ensureTerminator() =>
      _terminator ??= DspObject.lowpass()..bypass = true;

  @override
  void setInserts(List<MaterialisedFx> ordered) {
    final placeable = [
      for (final fx in ordered)
        if (fx.isPlaceable && fx is RealMaterialisedFx) fx,
    ];
    _inserts
      ..clear()
      ..addAll(placeable);

    if (placeable.isEmpty) {
      _detach();
      return;
    }

    final terminator = _ensureTerminator();
    // Re-link every real object to its successor; the last links to the
    // terminator, whose own `next` stays null — no stale edge can survive.
    for (var i = 0; i < placeable.length; i++) {
      final next = i + 1 < placeable.length
          ? placeable[i + 1].dspObject!
          : terminator;
      placeable[i].dspObject!.link(next);
    }
    _channel.dsp = placeable.first.dspObject;
    _attached = true;
  }

  void _detach() {
    if (_attached) {
      _channel.dsp = null;
      _attached = false;
    }
  }

  @override
  void dispose() {
    _detach();
    _inserts.clear();
    _terminator?.dispose();
    _terminator = null;
  }
}
