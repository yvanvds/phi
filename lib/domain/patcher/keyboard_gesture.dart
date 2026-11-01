/// One note message a keyboard press asks for: [pitch] at [velocity], where
/// velocity 0 is a release.
typedef KeyNote = ({int pitch, int velocity});

/// The note-on / note-off bookkeeping of a pointer on a `.kslider` keyboard
/// (issue #473).
///
/// A press plays the key under it; sliding onto another key releases the one
/// held and plays the new one, a glissando; lifting releases what is held.
/// Each call answers the messages to send, in order — the release always
/// before the next note-on — so a held key is never left sounding.
class KeyboardGesture {
  int? _held;

  /// The key the pointer is holding, or null.
  int? get held => _held;

  /// The pointer is over [pitch] (null when off every key), asking for
  /// [velocity] should it start a note there.
  List<KeyNote> moveTo(int? pitch, int velocity) {
    if (pitch == _held) return const [];
    final notes = <KeyNote>[
      if (_held case final held?) (pitch: held, velocity: 0),
      if (pitch != null) (pitch: pitch, velocity: velocity < 1 ? 1 : velocity),
    ];
    _held = pitch;
    return notes;
  }

  /// The pointer lifted (or the gesture was cancelled).
  List<KeyNote> release() => moveTo(null, 0);
}
