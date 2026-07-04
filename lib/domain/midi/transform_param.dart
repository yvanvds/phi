/// One editable scalar parameter a [MidiTransform] exposes through
/// [MidiTransform.params].
///
/// A param is a *descriptor*, not a live binding: it names the parameter,
/// carries its current value, and (optionally) bounds it so a generic editor
/// can validate input without knowing the transform's type. Mutation goes the
/// other way, through [MidiTransform.withParam], which mints a fresh
/// transform — the descriptors themselves stay immutable.
///
/// Only the two numeric shapes exist here, which covers every scalar
/// transform. The transforms whose behaviour lives in a table or rule-list
/// (spectral map, routing rules, split voices, spawn axes, scale tuning) are
/// edited by dedicated typed editor widgets instead (issue #95), mutating in
/// place through each transform's own `copyWith` rather than this scalar seam.
/// The two callback-driven transforms (velocity curve #108, muting predicate
/// #109) first need a serialisable data model before they can be edited at
/// all, so they expose no params yet.
///
/// The subtypes are sealed variants of one concept, so they share this file
/// (`sealed` requires a single library) — the same bundling exception
/// [BuiltinTransform]/[BuiltinTransformCatalog] already use.
sealed class TransformParam {
  const TransformParam({required this.name});

  /// Stable identifier *and* display label: the editor shows it verbatim and
  /// passes it back to [MidiTransform.withParam] on edit.
  final String name;
}

/// An integer-valued parameter (semitones, repeat counts, RNG seeds).
final class IntParam extends TransformParam {
  const IntParam({
    required super.name,
    required this.value,
    this.min,
    this.max,
  });

  final int value;

  /// Inclusive bounds for editor-side clamping; `null` means unbounded.
  final int? min;
  final int? max;
}

/// A real-valued parameter (stretch factors, beat lengths, probabilities).
final class DoubleParam extends TransformParam {
  const DoubleParam({
    required super.name,
    required this.value,
    this.min,
    this.max,
  });

  final double value;

  /// Inclusive bounds for editor-side clamping; `null` means unbounded.
  final double? min;
  final double? max;
}
