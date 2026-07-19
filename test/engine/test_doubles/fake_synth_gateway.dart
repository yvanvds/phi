import 'package:phi/domain/synth/synth_definition.dart';
import 'package:phi/domain/synth/synth_kind.dart';
import 'package:phi/engine/bridge/materialised_synth.dart';
import 'package:phi/engine/bridge/synth_gateway.dart';
import 'package:phi/engine/bridge/synth_materialisation.dart';

/// In-memory [SynthGateway] used in unit, widget, and integration tests.
///
/// Mints [FakeMaterialisedSynth]s that model the whole surface — materialisation
/// per kind, live-vs-rebuild param re-application, bus binding, and disposal —
/// without touching `package:yse`. Mirrors `FakeYseGateway` / `FakeMidiGateway`
/// for the synth side. Tests reach the minted handles through [synths] / [last].
class FakeSynthGateway implements SynthGateway {
  /// Every handle minted by [materialiseSynth], in creation order.
  final List<FakeMaterialisedSynth> synths = [];

  /// The most recently minted handle, or `null` before the first call.
  FakeMaterialisedSynth? get last => synths.isEmpty ? null : synths.last;

  @override
  MaterialisedSynth materialiseSynth(
    SynthDefinition definition, {
    required int channel,
  }) {
    final s = FakeMaterialisedSynth(definition, channel: channel);
    synths.add(s);
    return s;
  }
}

/// The [MaterialisedSynth] a [FakeSynthGateway] mints.
///
/// Records the lifecycle so tests can assert it: [materialiseCount] rises on
/// every (re)build, [liveApplyCount] on every in-place param apply, and [calls]
/// keeps an ordered log (`materialise:<kind>` / `apply:<kind>` / `bind:<bus>` /
/// `dispose:sound` / `dispose:synth`). It shares the real gateway's
/// re-materialisation rule via [SynthMaterialisation.needsRematerialise], so a
/// test that drives the fake exercises the same decision the real gateway makes.
class FakeMaterialisedSynth implements MaterialisedSynth {
  FakeMaterialisedSynth(this._definition, {required this.channel}) {
    calls.add('materialise:${_definition.kind.name}');
  }

  SynthDefinition _definition;

  @override
  final int channel;

  int? _boundBus;
  bool _hasSound = false;
  bool _disposed = false;

  /// How many times the engine voice pool was (re)built — starts at 1 for the
  /// initial materialisation, then rises on each rebuild-forcing edit.
  int materialiseCount = 1;

  /// How many edits were applied in place (live setters, no rebuild).
  int liveApplyCount = 0;

  /// How many times [bindToBus] created or moved the sound binding.
  int bindCount = 0;

  /// Ordered lifecycle log — see the class doc for the vocabulary.
  final List<String> calls = [];

  @override
  SynthKind get kind => _definition.kind;

  @override
  SynthDefinition get definition => _definition;

  @override
  int? get boundBus => _boundBus;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  @override
  void applyDefinition(SynthDefinition next) {
    if (SynthMaterialisation.needsRematerialise(_definition, next)) {
      materialiseCount++;
      calls.add('materialise:${next.kind.name}');
      // A rebuild re-binds the sound to the same bus, mirroring the real handle.
      if (_hasSound) {
        bindCount++;
        calls.add('bind:$_boundBus');
      }
    } else {
      liveApplyCount++;
      calls.add('apply:${next.kind.name}');
    }
    _definition = next;
  }

  @override
  void bindToBus(int? busChannelId) {
    _boundBus = busChannelId;
    _hasSound = true;
    bindCount++;
    calls.add('bind:$busChannelId');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Sound before synth — the leak-safe order the real handle enforces.
    if (_hasSound) calls.add('dispose:sound');
    calls.add('dispose:synth');
  }
}
