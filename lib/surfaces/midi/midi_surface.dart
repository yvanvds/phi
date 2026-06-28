import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_clip_seed.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../engine/engine.dart';
import '../surface.dart';
import 'midi_viewport.dart';

/// MIDI surface — piano-roll editor for a single seeded clip plus the
/// eight-chip transformation chain sidebar.
///
/// The `chain` and `editor` are injected by the shell so editing state (undo
/// history, selection) and chip toggles persist across surface switches. When
/// omitted (widget tests) a default demo chain is built and the viewport owns
/// the editor. `playhead` is the engine player's beat position (issue #29);
/// when present the roll renders and animates a playhead line, otherwise it
/// stays parked at the origin.
class MidiSurface extends Surface {
  MidiSurface({
    required PhiEngine engine,
    MidiTransformChain? chain,
    ClipEditor? editor,
    ValueListenable<double>? playhead,
    super.key,
  }) : _engine = engine,
       _chain = chain ?? defaultDemoChain(),
       _editor = editor,
       _playhead = playhead;

  // ignore: unused_field
  final PhiEngine _engine;
  final MidiTransformChain _chain;
  final ClipEditor? _editor;
  final ValueListenable<double>? _playhead;

  @override
  Widget build(BuildContext context) =>
      MidiViewport(chain: _chain, editor: _editor, playhead: _playhead);
}
