/// Whether the engine log [line] is RtMidi reporting that the host has **no
/// MIDI input system** to open, such as a Linux CI runner without an ALSA
/// sequencer (`/dev/snd/seq`):
///
/// ```text
/// (Error)  A MIDI system driver error occured MidiInAlsa::initialize: error creating ALSA sequencer client object.
/// ```
///
/// A MIDI input object logs it when it opens its port on such a host. It is a
/// fact about the machine, not about a patch, so the checks that every
/// tutorial opens without an engine error (#539) set it apart, but only when
/// the tutorial really holds a MIDI input object. Every other error still
/// fails them.
///
/// The match is deliberately tight: RtMidi's driver-error prefix followed by
/// one of its `MidiIn…` API classes (`MidiInAlsa`, `MidiInJack`,
/// `MidiInWinMM`, …). A MIDI output error or any other message does not match.
bool isMidiInDriverUnavailable(String line) => _pattern.hasMatch(line);

final _pattern = RegExp(
  r'^\(Error\)\s+A MIDI system driver error occured MidiIn[A-Za-z]+::[A-Za-z]+: ',
);

/// Whether the patch [dump] holds a MIDI input object, one of
/// [midiInputTypes].
bool holdsMidiInput(Map<String, Object?> dump) =>
    dump.values.any((o) => o is Map && midiInputTypes.contains(o['type']));

/// The MIDI input types the MIDI input tutorials cover (#508): the objects
/// that open a MIDI input port.
const midiInputTypes = {
  '.midiin',
  '.xmidiin',
  '.midiparse',
  '.notein',
  '.xnotein',
  '.ctlin',
  '.xctlin',
  '.bendin',
  '.xbendin',
  '.xbendin2',
  '.touchin',
  '.polyin',
  '.pgmin',
  '.rtin',
  '.sysexin',
  '.rpnin',
  '.nrpnin',
  '.midiinfo',
};
