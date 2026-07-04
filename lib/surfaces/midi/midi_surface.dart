import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/custom_transform_registry.dart';
import '../../domain/midi/midi_clip_seed.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/state_machine/state_graph.dart';
import '../../engine/engine.dart';
import '../../engine/state/midi_graph_controller.dart';
import '../surface.dart';
import 'midi_file_io.dart';
import 'midi_viewport.dart';

/// MIDI surface — piano-roll editor for a single seeded clip plus the
/// eight-chip transformation chain sidebar.
///
/// The `chain` and `editor` are injected by the shell so editing state (undo
/// history, selection) and chip toggles persist across surface switches. When
/// omitted (widget tests) a default demo chain is built and the viewport owns
/// the editor. `registry` (issue #38) feeds the chain `+` menu with
/// performer-authored transforms; `null` leaves the `+` inert. `playhead` is
/// the engine player's beat position (issue #29);
/// when present the roll renders and animates a playhead line, otherwise it
/// stays parked at the origin.
class MidiSurface extends Surface {
  MidiSurface({
    required PhiEngine engine,
    MidiTransformChain? chain,
    ClipEditor? editor,
    CustomTransformRegistry? registry,
    ValueListenable<double>? playhead,
    MidiFileIo? fileIo,
    MidiGraphController? graphController,
    StateGraph? stateGraph,
    RuntimeVariableRegistry? runtimeVariables,
    super.key,
  }) : _engine = engine,
       _chain = chain ?? defaultDemoChain(),
       _editor = editor,
       _registry = registry,
       _playhead = playhead,
       _fileIo = fileIo,
       _graphController = graphController,
       _stateGraph = stateGraph,
       _runtimeVariables = runtimeVariables;

  final PhiEngine _engine;
  final MidiTransformChain _chain;
  final ClipEditor? _editor;
  final CustomTransformRegistry? _registry;
  final ValueListenable<double>? _playhead;
  final MidiFileIo? _fileIo;

  /// The branching transform-graph controller (issue #65). When `null` the
  /// viewport seeds and owns its own from [_chain].
  final MidiGraphController? _graphController;

  /// The state machine driving the graph's live evaluation context. `null`
  /// falls back to an empty context.
  final StateGraph? _stateGraph;

  /// The runtime-variable registry backing the graph's `var · name = value`
  /// guards and its variables bar (issue #78). `null` falls back to the
  /// engine's, so the shell need not thread it explicitly.
  final RuntimeVariableRegistry? _runtimeVariables;

  @override
  Widget build(BuildContext context) => MidiViewport(
    chain: _chain,
    editor: _editor,
    registry: _registry,
    playhead: _playhead,
    fileIo: _fileIo,
    graphController: _graphController ?? _engine.midiOrNull?.graphController,
    stateGraph: _stateGraph ?? _engine.stateMachineOrNull?.graph,
    runtimeVariables: _runtimeVariables ?? _engine.runtimeVariablesOrNull,
  );
}
