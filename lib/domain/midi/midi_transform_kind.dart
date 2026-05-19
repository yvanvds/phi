/// Phi groups MIDI transformations into four families (vision §3.7).
///
/// The chain UI renders the [tag] as the 36px kind label next to each chip;
/// voice colour is the kind's index + 1 so pitch=voice1, time=voice2,
/// voice=voice3, struct=voice4 — matching the design mockup.
enum MidiTransformKind {
  pitch('pitch'),
  time('time'),
  voice('voice'),
  struct('struct');

  const MidiTransformKind(this.tag);

  final String tag;

  int get voiceIndex => index + 1;
}
