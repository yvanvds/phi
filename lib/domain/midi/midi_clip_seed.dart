import 'midi_clip.dart';
import 'midi_note.dart';
import 'midi_transform.dart';
import 'midi_transform_chain.dart';
import 'midi_transform_kind.dart';
import 'music_scale.dart';
import 'transforms/scale_conformance_transform.dart';
import 'transforms/stub_transform.dart';
import 'transforms/transpose_transform.dart';

/// The ten-note "phrase A" used as the on-load demo clip. Matches the
/// surface-midi.jsx mockup note-for-note — pitch classes include scale
/// degrees both inside and outside D-dorian so scale-conformance has
/// something visible to do when the user toggles it.
MidiClip phraseA() => const MidiClip(
  name: 'phrase A',
  bars: 4,
  notes: [
    MidiNote(pitch: 60, start: 0.00, duration: 0.25, velocity: 0.7),
    MidiNote(pitch: 63, start: 0.25, duration: 0.25, velocity: 0.6),
    MidiNote(pitch: 67, start: 0.50, duration: 0.50, velocity: 0.8),
    MidiNote(pitch: 70, start: 1.00, duration: 0.25, velocity: 0.5),
    MidiNote(pitch: 67, start: 1.25, duration: 0.25, velocity: 0.6),
    MidiNote(pitch: 65, start: 1.50, duration: 0.50, velocity: 0.7),
    MidiNote(pitch: 63, start: 2.00, duration: 0.25, velocity: 0.5),
    MidiNote(pitch: 67, start: 2.25, duration: 0.75, velocity: 0.9),
    MidiNote(pitch: 70, start: 3.00, duration: 0.50, velocity: 0.7),
    MidiNote(pitch: 72, start: 3.50, duration: 0.50, velocity: 0.8),
  ],
);

/// The eight-chip default sidebar from the design mockup — two working
/// transforms (transpose, scale-conform) and six stubs covering the rest
/// of the families. The last two structural chips ship `active: false` to
/// mirror the mockup state.
MidiTransformChain defaultDemoChain() => MidiTransformChain(
  source: phraseA(),
  transforms: <MidiTransform>[
    const ScaleConformanceTransform(
      scale: MusicScale.dorian,
      tonic: 62,
      label: 'scale · dorian D',
    ),
    const TransposeTransform(semitones: 3, label: 'transpose · +3 st'),
    const StubTransform(
      kind: MidiTransformKind.time,
      label: 'domain · drum @ 124',
    ),
    const StubTransform(
      kind: MidiTransformKind.time,
      label: 'quantize · gravity 0.6',
    ),
    const StubTransform(
      kind: MidiTransformKind.voice,
      label: 'route · osc.saw',
    ),
    const StubTransform(
      kind: MidiTransformKind.voice,
      label: 'spawn · agent @ p,v',
    ),
    const StubTransform(
      kind: MidiTransformKind.struct,
      label: 'loop · 4 bars',
      active: false,
    ),
    const StubTransform(
      kind: MidiTransformKind.struct,
      label: 'branch · state.break',
      active: false,
    ),
  ],
);
