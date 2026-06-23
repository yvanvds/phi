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
/// the editor. The `engine` parameter is accepted but unused while playback
/// wiring is out of scope.
class MidiSurface extends Surface {
  MidiSurface({
    required PhiEngine engine,
    MidiTransformChain? chain,
    ClipEditor? editor,
    super.key,
  }) : _engine = engine,
       _chain = chain ?? defaultDemoChain(),
       _editor = editor;

  // ignore: unused_field
  final PhiEngine _engine;
  final MidiTransformChain _chain;
  final ClipEditor? _editor;

  @override
  Widget build(BuildContext context) =>
      MidiViewport(chain: _chain, editor: _editor);
}
