/// Which transform representation a MIDI clip uses — and therefore both which
/// editor the surface shows and which pipeline drives playback.
///
/// A clip is *either* linear or branching, never both at once: [chain] reads
/// the flat [MidiTransformChain] (the zero-overhead default), [graph] reads the
/// branching [MidiTransformGraph]'s `evaluate(context)`, so a state-guarded
/// edge re-routes the sounding notes as the live state flips. Promotion from
/// [chain] to [graph] is lossless (`MidiTransformGraph.linear` reproduces the
/// chain note-for-note); nothing syncs between the two — only the active one is
/// ever shown or heard.
enum MidiClipMode { chain, graph }
