import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/custom_transform_registry.dart';
import '../../domain/midi/midi_clip_seed.dart';
import '../../domain/midi/midi_note.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/smf/smf_exception.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/state_machine/state_graph.dart';
import '../../engine/engine.dart';
import '../../engine/state/clip_library_controller.dart';
import '../../engine/state/midi_graph_controller.dart';
import '../surface.dart';
import 'clip_transport_row.dart';
import 'library/library_panel.dart';
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
    ClipLibraryController? libraryController,
    super.key,
  }) : _engine = engine,
       _chain = chain ?? defaultDemoChain(),
       _editor = editor,
       _registry = registry,
       _playhead = playhead,
       _fileIo = fileIo,
       _graphController = graphController,
       _stateGraph = stateGraph,
       _runtimeVariables = runtimeVariables,
       _libraryController = libraryController;

  final PhiEngine _engine;
  final MidiTransformChain _chain;
  final ClipEditor? _editor;
  final CustomTransformRegistry? _registry;
  final ValueListenable<double>? _playhead;
  final MidiFileIo? _fileIo;

  /// The clip-library seam driving the collapsible left library panel (issue
  /// #188). When present the panel is shown and clip selection swaps the edited
  /// session, so the roll rebinds to the selected clip. `null` (widget tests
  /// without a project / MIDI subsystem) hides the panel and keeps the injected
  /// [_chain] / [_editor] bound, exactly as before.
  final ClipLibraryController? _libraryController;

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

  /// Preview a clicked / stepped note through its **routed voice** (design §7,
  /// issue #211): a momentary audition on the engine's audition path, so editing
  /// a note in the roll is heard through the voice it routes to. A no-op without
  /// a MIDI subsystem (bare tests).
  void _auditionNote(MidiNote note) {
    _engine.midiOrNull?.auditionPreview(
      note.voice,
      note.pitch.round(),
      velocity: (note.velocity * 127).round().clamp(1, 127),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = _libraryController;
    if (library == null) return _viewport();
    // The record arm + capture flow for the edited session (issue #261); its arm
    // / recording state lights the transport row's record button. `null` in
    // setups without a MIDI subsystem — the record button is then hidden.
    final record = _engine.midiOrNull?.record;
    // With a library controller the roll binds to the *edited* session, so a
    // clip selection swaps it. The panel persists across selections (it sits
    // outside the keyed viewport); the viewport is rebuilt on every controller
    // change and keyed by the edited address so a new selection re-captures the
    // session's chain / editor / graph.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LibraryPanel(controller: library),
        Expanded(
          child: ListenableBuilder(
            listenable: record == null
                ? library
                : Listenable.merge([library, record]),
            builder: (context, _) {
              final session = library.sessions.editedSession;
              final address = session.address;
              return _viewport(
                key: ValueKey(address?.format() ?? '<boot>'),
                chain: session.chain,
                editor: session.editor,
                graphController: session.graphController,
                playhead: session.playhead,
                clipName: address?.name ?? phraseASlug,
                // Import lands a dropped / picked `.mid` as a new clip entity in
                // the selected group (design §3, issue #191), not an in-place
                // overwrite; a malformed stream returns a message the header shows.
                onImportSmf: (bytes, fileName) async {
                  try {
                    library.importFromSmf(bytes, fileName: fileName);
                    return null;
                  } on SmfFormatException catch (e) {
                    return 'import failed · ${e.message}';
                  }
                },
                transport: ClipTransportControls(
                  isPlaying: library.isEditedPlaying,
                  isPaused: library.isEditedPaused,
                  loop: library.editedLoops,
                  onPlay: library.playEdited,
                  onPause: library.pauseEdited,
                  onStop: library.stopEdited,
                  onToggleLoop: library.toggleEditedLoop,
                  isArmed: record?.armed ?? false,
                  isRecording: record?.isRecording ?? false,
                  onToggleRecordArm: record?.toggleArm,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Builds the piano-roll viewport. Without a library controller it binds to the
  /// injected [_chain] / [_editor]; with one the caller passes the edited
  /// session's objects so selection swaps what the roll shows.
  Widget _viewport({
    Key? key,
    MidiTransformChain? chain,
    ClipEditor? editor,
    MidiGraphController? graphController,
    ValueListenable<double>? playhead,
    String? clipName,
    ClipTransportControls? transport,
    Future<String?> Function(Uint8List bytes, String fileName)? onImportSmf,
  }) => MidiViewport(
    key: key,
    chain: chain ?? _chain,
    editor: editor ?? _editor,
    registry: _registry,
    playhead: playhead ?? _playhead,
    fileIo: _fileIo,
    onImportSmf: onImportSmf,
    graphController:
        graphController ??
        _graphController ??
        _engine.midiOrNull?.graphController,
    stateGraph: _stateGraph ?? _engine.stateMachineOrNull?.graph,
    runtimeVariables: _runtimeVariables ?? _engine.runtimeVariablesOrNull,
    transport: transport,
    onAuditionNote: _auditionNote,
    clipName: clipName ?? phraseASlug,
  );
}
