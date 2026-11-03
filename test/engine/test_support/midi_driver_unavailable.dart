/// Whether the engine log [line] is RtMidi reporting that the host has **no
/// MIDI system** to open a port on, such as a Linux CI runner without an ALSA
/// sequencer (`/dev/snd/seq`):
///
/// ```text
/// (Error)  A MIDI system driver error occured MidiInAlsa::initialize: error creating ALSA sequencer client object.
/// (Error)  A MIDI system driver error occured MidiOutAlsa::initialize: error creating ALSA sequencer client object.
/// ```
///
/// A MIDI input object logs the first when it opens its port on such a host;
/// a `.midiout` logs the second when it opens its own, on the first message it
/// receives (#509). It is a fact about the machine, not about a patch, so the
/// checks that every tutorial opens without an engine error (#539) set it
/// apart, but only when the tutorial really holds a MIDI port object
/// ([holdsMidiPort]). Every other error still fails them.
///
/// The match is deliberately tight: RtMidi's driver-error prefix followed by
/// one of its `MidiIn…` or `MidiOut…` API classes (`MidiInAlsa`,
/// `MidiOutAlsa`, `MidiInWinMM`, …). Any other message does not match.
bool isMidiDriverUnavailable(String line) => _pattern.hasMatch(line);

final _pattern = RegExp(
  r'^\(Error\)\s+A MIDI system driver error occured '
  r'Midi(In|Out)[A-Za-z]+::[A-Za-z]+: ',
);

/// Whether the patch [dump] holds an object that opens a MIDI port: one of
/// [midiInputTypes], or a `.midiout`.
bool holdsMidiPort(Map<String, Object?> dump) =>
    dump.values.any((o) => o is Map && midiPortTypes.contains(o['type']));

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

/// Every object type that opens a MIDI port: the inputs and `.midiout`.
const midiPortTypes = {...midiInputTypes, '.midiout'};

/// The MIDI output types the MIDI output tutorials cover (#509): the message
/// builders, `.midiout` that sends them, and the two flush objects. Of these,
/// only `.midiout` opens a port.
const midiOutputTypes = {
  '.noteon',
  '.noteoff',
  '.xnoteout',
  '.controlchange',
  '.xctlout',
  '.programchange',
  '.channelpressure',
  '.polypressure',
  '.bendout',
  '.xbendout',
  '.xbendout2',
  '.rpnout',
  '.nrpnout',
  '.midiout',
  '.midiformat',
  '.sxformat',
  '.midiflush',
  '.flush',
};
