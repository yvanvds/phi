import 'midi_note.dart';
import 'midi_transform_kind.dart';

/// One stage in a [MidiTransformChain].
///
/// Implementations are immutable; [copyWith] is how the chain toggles
/// activeness or swaps parameters. [apply] is pure — same input, same
/// output — so the chain can memoise.
///
/// The chain itself decides whether to call [apply] on inactive transforms;
/// current behaviour is to skip them entirely.
abstract class MidiTransform {
  const MidiTransform();

  MidiTransformKind get kind;
  String get label;
  bool get active;

  List<MidiNote> apply(List<MidiNote> input);

  MidiTransform copyWith({bool? active});
}
