import 'midi_note.dart';
import 'midi_transform_kind.dart';
import 'transform_param.dart';

/// One stage in a [MidiTransformChain].
///
/// Implementations are immutable; [copyWith] is how the chain toggles
/// activeness, renames the chip's [label], or swaps parameters. [apply] is
/// pure — same input, same output — so the chain can memoise.
///
/// The chain itself decides whether to call [apply] on inactive transforms;
/// current behaviour is to skip them entirely.
abstract class MidiTransform {
  const MidiTransform();

  MidiTransformKind get kind;
  String get label;
  bool get active;

  /// Bumps whenever this transform's behaviour changes *in place* without the
  /// containing chain's transform list changing — e.g. a live-coded
  /// [CustomTransform] hot-reloaded under the same name. Pure transforms (the
  /// vast majority) never change and stay at `0`; a [MidiTransformChain] folds
  /// this into its output-cache key so a hot-reload invalidates the cache.
  int get revision => 0;

  List<MidiNote> apply(List<MidiNote> input);

  MidiTransform copyWith({bool? active, String? label});

  /// The editable scalar parameters, in display order. Empty (the default)
  /// means a generic editor has nothing to mutate — either the transform is
  /// genuinely parameterless or its behaviour lives in a table/callback that
  /// awaits a typed editor (issue #95).
  List<TransformParam> get params => const [];

  /// Returns a copy with the parameter named [name] set to [value], where
  /// [name] is one of [params]' names. Unknown names throw an [ArgumentError]
  /// so an editor typo fails loudly instead of silently dropping the edit.
  ///
  /// Out-of-range values are the editor's problem: it clamps to the param's
  /// declared bounds before calling this, and [apply] keeps its own guards
  /// (identity on non-positive grids/factors, pitch clamping) regardless.
  MidiTransform withParam(String name, num value) =>
      throw ArgumentError.value(name, 'name', 'not an editable parameter');
}
