import 'package:flutter/widgets.dart';

import '../../domain/midi/midi_clip_seed.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../engine/engine.dart';
import '../surface.dart';
import 'midi_viewport.dart';

/// MIDI surface scaffold — piano-roll viewer for a single seeded clip plus
/// the eight-chip transformation chain sidebar.
///
/// The viewport owns its [MidiTransformChain]; the `engine` parameter is
/// accepted but unused while playback wiring is out of scope. Keeping it
/// in the constructor means the playback follow-up doesn't have to touch
/// [Workstation] again.
class MidiSurface extends Surface {
  MidiSurface({required PhiEngine engine, MidiTransformChain? chain, super.key})
    : _engine = engine,
      _chain = chain ?? defaultDemoChain();

  // ignore: unused_field
  final PhiEngine _engine;
  final MidiTransformChain _chain;

  @override
  Widget build(BuildContext context) => MidiViewport(chain: _chain);
}
