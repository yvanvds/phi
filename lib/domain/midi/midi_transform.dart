import 'midi_note.dart';
import 'midi_transform_kind.dart';

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
}
