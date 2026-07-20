import 'package:yse/yse.dart';

import '../../domain/fx/fx_definition.dart';
import '../../domain/fx/fx_kind.dart';
import 'materialised_fx.dart';

/// Production [MaterialisedFx] backed by `package:yse` (design
/// `docs/design/racks-and-voices.md` §5).
///
/// Owns one engine [DspObject] (or [Compressor]) built from the definition's
/// [FxKind], and maps the definition's flat `name → value` [FxDefinition.params]
/// onto that object's setters. Every setter is click-free (ramped where the
/// engine ramps), so re-applying an edited definition of the *same* kind is
/// glitch-free; a kind change rebuilds the underlying object (its identity
/// changes, so the owning chain must re-place).
///
/// **Recognised param keys** (unknown keys are ignored, missing keys leave the
/// engine default):
///
/// - all kinds: `impact` (wet/dry `0..1`), `bypass` (`!= 0` bypasses);
/// - `lowpass`/`highpass`: `frequency` (Hz);
/// - `bandpass`: `frequency`, `q`;
/// - `sweep`: `speed` (Hz), `depth` (`0..100`), `centre` (`0..100`);
/// - `basicDelay`/`lowpassDelay`/`highpassDelay`: `tap1Time`/`tap1Gain` …
///   `tap3Time`/`tap3Gain` (ms / linear), plus `frequency` for the two filtered
///   delays' in-loop filter;
/// - `phaser`: `frequency`, `range`;
/// - `ringModulator`: `frequency`;
/// - `difference`: `frequency`, `amplitude`;
/// - `granulator`: `grainFrequency` (grains/s), `grainLength` (samples),
///   `grainTranspose` (ratio), `gain`;
/// - `compressor`: `threshold` (dB), `ratio`, `attack` (ms), `release` (ms),
///   `makeup` (dB);
/// - `patcherInsert`: reserved — builds **no** object ([isPlaceable] is
///   `false`) until the patcher epic wires it (design §5).
class RealMaterialisedFx implements MaterialisedFx {
  /// Builds the engine effect for [definition] and applies its params.
  RealMaterialisedFx(this._definition) {
    _dsp = _build(_definition);
    if (_dsp != null) _applyParams(_dsp!, _definition);
  }

  FxDefinition _definition;
  DspObject? _dsp;

  @override
  FxKind get kind => _definition.kind;

  @override
  FxDefinition get definition => _definition;

  @override
  bool get isPlaceable => _dsp != null;

  /// The live engine effect, for the [RealFxChain] that links it. `null` for a
  /// reserved `patcherInsert`. Not part of the yse-free surface.
  DspObject? get dspObject => _dsp;

  @override
  void applyDefinition(FxDefinition next) {
    if (next.kind != _definition.kind) {
      // A kind change is a different effect entirely — rebuild the object. The
      // owning chain re-places afterwards (the DspObject identity changed).
      _dsp?.dispose();
      _dsp = _build(next);
    }
    if (_dsp != null) _applyParams(_dsp!, next);
    _definition = next;
  }

  @override
  void dispose() {
    _dsp?.dispose();
    _dsp = null;
  }

  // ─── build ──────────────────────────────────────────────────────────────

  DspObject? _build(FxDefinition def) => switch (def.kind) {
    FxKind.lowpass => DspObject.lowpass(),
    FxKind.highpass => DspObject.highpass(),
    FxKind.bandpass => DspObject.bandpass(),
    FxKind.sweep => DspObject.sweep(),
    FxKind.basicDelay => DspObject.basicDelay(),
    FxKind.lowpassDelay => DspObject.lowpassDelay(),
    FxKind.highpassDelay => DspObject.highpassDelay(),
    FxKind.phaser => DspObject.phaser(),
    FxKind.ringModulator => DspObject.ringModulator(),
    FxKind.difference => DspObject.difference(),
    FxKind.granulator => DspObject.granulator(),
    FxKind.compressor => Compressor(),
    // Reserved until the patcher epic lands its entities (design §5).
    FxKind.patcherInsert => null,
  };

  // ─── params ─────────────────────────────────────────────────────────────

  void _applyParams(DspObject dsp, FxDefinition def) {
    final p = def.params;
    // Inherited control surface — every kind.
    final impact = p['impact'];
    if (impact != null) dsp.impact = impact;
    final bypass = p['bypass'];
    if (bypass != null) dsp.bypass = bypass != 0;

    switch (def.kind) {
      case FxKind.lowpass:
      case FxKind.highpass:
        _setFrequency(dsp, p);
      case FxKind.bandpass:
        _setFrequency(dsp, p);
        final q = p['q'];
        if (q != null) dsp.q = q;
      case FxKind.sweep:
        final speed = p['speed'];
        if (speed != null) dsp.sweepSpeed = speed;
        final depth = p['depth'];
        if (depth != null) dsp.sweepDepth = depth.round();
        final centre = p['centre'];
        if (centre != null) dsp.sweepCentre = centre.round();
      case FxKind.basicDelay:
        _setDelayTaps(dsp, p);
      case FxKind.lowpassDelay:
      case FxKind.highpassDelay:
        _setDelayTaps(dsp, p);
        _setFrequency(dsp, p);
      case FxKind.phaser:
        _setFrequency(dsp, p);
        final range = p['range'];
        if (range != null) dsp.phaserRange = range;
      case FxKind.ringModulator:
        _setFrequency(dsp, p);
      case FxKind.difference:
        _setFrequency(dsp, p);
        final amplitude = p['amplitude'];
        if (amplitude != null) dsp.differenceAmplitude = amplitude;
      case FxKind.granulator:
        final grainFrequency = p['grainFrequency'];
        if (grainFrequency != null) dsp.grainFrequency = grainFrequency.round();
        final grainLength = p['grainLength'];
        if (grainLength != null) {
          dsp.setGrainLength(samples: grainLength.round());
        }
        final grainTranspose = p['grainTranspose'];
        if (grainTranspose != null) {
          dsp.setGrainTranspose(pitch: grainTranspose);
        }
        final gain = p['gain'];
        if (gain != null) dsp.grainGain = gain;
      case FxKind.compressor:
        final c = dsp as Compressor;
        final threshold = p['threshold'];
        if (threshold != null) c.threshold = threshold;
        final ratio = p['ratio'];
        if (ratio != null) c.ratio = ratio;
        final attack = p['attack'];
        if (attack != null) c.attack = attack;
        final release = p['release'];
        if (release != null) c.release = release;
        final makeup = p['makeup'];
        if (makeup != null) c.makeup = makeup;
      case FxKind.patcherInsert:
        break; // No object — nothing to apply.
    }
  }

  void _setFrequency(DspObject dsp, Map<String, double> p) {
    final frequency = p['frequency'];
    if (frequency != null) dsp.frequency = frequency;
  }

  void _setDelayTaps(DspObject dsp, Map<String, double> p) {
    for (final (index, tap) in const [
      DelayTap.first,
      DelayTap.second,
      DelayTap.third,
    ].indexed) {
      final time = p['tap${index + 1}Time'];
      final gain = p['tap${index + 1}Gain'];
      if (time != null || gain != null) {
        dsp.setDelayTap(
          tap,
          timeMs: time ?? dsp.delayTime(tap),
          gain: gain ?? dsp.delayGain(tap),
        );
      }
    }
  }
}
