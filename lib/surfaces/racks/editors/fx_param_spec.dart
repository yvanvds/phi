import '../../../domain/fx/fx_kind.dart';

/// A UI descriptor for one continuous `fx.` parameter — the label and range the
/// [FxEditor] renders a row from (design `docs/design/racks-and-voices.md` §5,
/// §8 — "one labelled row per param, per kind").
///
/// The `fx.` payload keeps params as an untyped `name → value` map (the engine
/// owns each key's meaning); this spec is the *presentation* layer that says how
/// to show and bound each one. The recognised keys mirror the engine's
/// `RealMaterialisedFx` param surface, so an edited value lands where the
/// gateway reads it.
class FxParamSpec {
  const FxParamSpec({
    required this.name,
    required this.label,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.isInt = false,
  });

  /// The payload param key (e.g. `frequency`, `tap1Time`).
  final String name;

  /// The row label shown to the performer.
  final String label;

  final double min;
  final double max;

  /// The value shown (and committed on first touch) when the param is absent
  /// from the payload — a sensible starting point per key.
  final double defaultValue;

  /// Round committed / displayed values to whole numbers.
  final bool isInt;
}

const List<FxParamSpec> _delayTaps = [
  FxParamSpec(
    name: 'tap1Time',
    label: 'tap 1 time',
    min: 0,
    max: 2000,
    defaultValue: 250,
    isInt: true,
  ),
  FxParamSpec(
    name: 'tap1Gain',
    label: 'tap 1 gain',
    min: 0,
    max: 1,
    defaultValue: 0.5,
  ),
  FxParamSpec(
    name: 'tap2Time',
    label: 'tap 2 time',
    min: 0,
    max: 2000,
    defaultValue: 500,
    isInt: true,
  ),
  FxParamSpec(
    name: 'tap2Gain',
    label: 'tap 2 gain',
    min: 0,
    max: 1,
    defaultValue: 0.3,
  ),
  FxParamSpec(
    name: 'tap3Time',
    label: 'tap 3 time',
    min: 0,
    max: 2000,
    defaultValue: 750,
    isInt: true,
  ),
  FxParamSpec(
    name: 'tap3Gain',
    label: 'tap 3 gain',
    min: 0,
    max: 1,
    defaultValue: 0.15,
  ),
];

const FxParamSpec _frequency = FxParamSpec(
  name: 'frequency',
  label: 'frequency',
  min: 20,
  max: 20000,
  defaultValue: 1000,
  isInt: true,
);

/// The continuous params to show for [kind], in row order. Excludes the two
/// universal controls (`impact`, `bypass`), which the editor renders for every
/// kind. A reserved `patcherInsert` has none.
List<FxParamSpec> fxParamsFor(FxKind kind) => switch (kind) {
  FxKind.lowpass || FxKind.highpass => const [_frequency],
  FxKind.bandpass => const [
    _frequency,
    FxParamSpec(name: 'q', label: 'q', min: 0.1, max: 20, defaultValue: 1),
  ],
  FxKind.sweep => const [
    FxParamSpec(
      name: 'speed',
      label: 'speed',
      min: 0,
      max: 20,
      defaultValue: 1,
    ),
    FxParamSpec(
      name: 'depth',
      label: 'depth',
      min: 0,
      max: 100,
      defaultValue: 50,
      isInt: true,
    ),
    FxParamSpec(
      name: 'centre',
      label: 'centre',
      min: 0,
      max: 100,
      defaultValue: 50,
      isInt: true,
    ),
  ],
  FxKind.basicDelay => _delayTaps,
  FxKind.lowpassDelay ||
  FxKind.highpassDelay => const [..._delayTaps, _frequency],
  FxKind.phaser => const [
    _frequency,
    FxParamSpec(name: 'range', label: 'range', min: 0, max: 1, defaultValue: 1),
  ],
  FxKind.ringModulator => const [
    FxParamSpec(
      name: 'frequency',
      label: 'frequency',
      min: 1,
      max: 8000,
      defaultValue: 440,
      isInt: true,
    ),
  ],
  FxKind.difference => const [
    _frequency,
    FxParamSpec(
      name: 'amplitude',
      label: 'amplitude',
      min: 0,
      max: 1,
      defaultValue: 1,
    ),
  ],
  FxKind.granulator => const [
    FxParamSpec(
      name: 'grainFrequency',
      label: 'grain freq',
      min: 1,
      max: 200,
      defaultValue: 20,
      isInt: true,
    ),
    FxParamSpec(
      name: 'grainLength',
      label: 'grain length',
      min: 1,
      max: 44100,
      defaultValue: 4410,
      isInt: true,
    ),
    FxParamSpec(
      name: 'grainTranspose',
      label: 'transpose',
      min: 0.25,
      max: 4,
      defaultValue: 1,
    ),
    FxParamSpec(name: 'gain', label: 'gain', min: 0, max: 1, defaultValue: 1),
  ],
  FxKind.compressor => const [
    FxParamSpec(
      name: 'threshold',
      label: 'threshold',
      min: -60,
      max: 0,
      defaultValue: -20,
    ),
    FxParamSpec(
      name: 'ratio',
      label: 'ratio',
      min: 1,
      max: 20,
      defaultValue: 4,
    ),
    FxParamSpec(
      name: 'attack',
      label: 'attack',
      min: 0,
      max: 500,
      defaultValue: 10,
      isInt: true,
    ),
    FxParamSpec(
      name: 'release',
      label: 'release',
      min: 0,
      max: 2000,
      defaultValue: 100,
      isInt: true,
    ),
    FxParamSpec(
      name: 'makeup',
      label: 'makeup',
      min: 0,
      max: 24,
      defaultValue: 0,
    ),
  ],
  FxKind.patcherInsert => const [],
};
