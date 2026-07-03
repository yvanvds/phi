import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../domain/midi/builtin_transform_catalog.dart';
import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/custom_transform_registry.dart';
import '../../domain/midi/graph/graph_eval_context.dart';
import '../../domain/midi/midi_clip.dart';
import '../../domain/midi/midi_clip_mode.dart';
import '../../domain/midi/midi_transform.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/midi_transform_kind.dart';
import '../../domain/midi/smf/smf_exception.dart';
import '../../domain/midi/smf/smf_reader.dart';
import '../../domain/midi/smf/smf_writer.dart';
import '../../domain/state_machine/state_graph.dart';
import '../../engine/state/midi_graph_controller.dart';
import 'file_selector_midi_file_io.dart';
import 'graph/graph_preview_strip.dart';
import 'graph/transform_graph_canvas.dart';
import 'midi_file_io.dart';
import 'midi_header_strip.dart';
import 'piano_roll_editor.dart';
import 'transform_chain_panel.dart';
import 'velocity_lane.dart';

/// Stateful host for the [MidiTransformChain] and its [ClipEditor]. Listens to
/// both (merged) so toggling a chip *or* editing a note repaints the roll, the
/// velocity lane and the chain panel without manual setState calls.
///
/// The editor is injected by the shell so its undo history and selection
/// survive surface switches; when none is supplied (widget tests) the viewport
/// owns one built from the chain's source clip.
///
/// SMF import/export (issue #30) is wired here: the whole surface is a drop
/// target for `.mid` files, and the header carries import/export buttons.
/// Importing rewrites the shared source clip in place (so the chain, editor
/// and engine player keep their references) and resets the editor history;
/// exporting encodes the chain's transformed [MidiTransformChain.output].
class MidiViewport extends StatefulWidget {
  const MidiViewport({
    required this.chain,
    this.editor,
    this.registry,
    this.playhead,
    this.fileIo,
    this.graphController,
    this.stateGraph,
    super.key,
  });

  final MidiTransformChain chain;
  final ClipEditor? editor;

  /// The branching transform-graph controller (issue #65). When `null` the
  /// viewport seeds and owns a fallback from [chain] so the graph view is
  /// always available; the shell/engine pass a shared one so the graph state
  /// survives surface switches.
  final MidiGraphController? graphController;

  /// The state machine, for the graph's live evaluation context and its
  /// condition picker. `null` when no state machine is wired — the graph then
  /// evaluates against an empty context (only unconditional edges fire).
  final StateGraph? stateGraph;

  /// Catalogue of performer-authored transforms surfaced in the chain `+` menu
  /// (issue #38). `null` in setups without a live-coding registry; the `+`
  /// then stays inert.
  final CustomTransformRegistry? registry;

  /// The engine player's beat position (issue #29). `null` in setups without
  /// a wired MIDI player; the editor then parks the playhead at the origin.
  final ValueListenable<double>? playhead;

  /// File-dialog backend for the import/export buttons. Defaults to the real
  /// `file_selector`-backed implementation; tests inject a fake.
  final MidiFileIo? fileIo;

  @override
  State<MidiViewport> createState() => _MidiViewportState();
}

class _MidiViewportState extends State<MidiViewport> {
  late final ClipEditor _editor;
  late final bool _ownsEditor;
  late final MidiGraphController _graph;
  late final bool _ownsGraph;
  late final Listenable _listenable;
  late final MidiFileIo _fileIo;

  static const _reader = SmfReader();
  static const _writer = SmfWriter();

  /// Transient import error surfaced in the header; cleared on the next
  /// successful import or when a new one is attempted.
  String? _importError;

  @override
  void initState() {
    super.initState();
    _ownsEditor = widget.editor == null;
    _editor = widget.editor ?? ClipEditor(widget.chain.source);
    _ownsGraph = widget.graphController == null;
    _graph =
        widget.graphController ?? MidiGraphController.seededFrom(widget.chain);
    // Merge the registry (for the `+` menu), the graph controller (mode +
    // layout), the graph (structure), and the state graph (live evaluation
    // context) so a change to any repaints the roll ghost, the graph, the
    // preview — and swaps the whole editor when the clip's mode flips.
    _listenable = Listenable.merge([
      widget.chain,
      _editor,
      _graph,
      _graph.graph,
      if (widget.registry != null) widget.registry,
      if (widget.stateGraph != null) widget.stateGraph,
    ]);
    _fileIo = widget.fileIo ?? const FileSelectorMidiFileIo();
  }

  @override
  void dispose() {
    if (_ownsEditor) _editor.dispose();
    if (_ownsGraph) _graph.dispose();
    super.dispose();
  }

  GraphEvalContext get _evalContext =>
      GraphEvalContext(activeStateId: widget.stateGraph?.activeStateId);

  // ── Import / export ────────────────────────────────────────────────────────

  Future<void> _pickAndImport() async {
    final bytes = await _fileIo.openSmf();
    if (bytes != null) _importBytes(bytes);
  }

  /// Parse [bytes] as SMF and swap them into the shared source clip. The
  /// chain, editor and engine player all hold the *same* clip reference, so a
  /// mutate-in-place keeps every wiring point intact; the editor history is
  /// reset because its note indices no longer line up.
  void _importBytes(Uint8List bytes) {
    try {
      final imported = _reader.read(bytes);
      widget.chain.source.replaceWith(imported);
      _editor.reset();
      widget.chain.notifySourceChanged();
      if (mounted) setState(() => _importError = null);
    } on SmfFormatException catch (e) {
      if (mounted) {
        setState(() => _importError = 'import failed · ${e.message}');
      }
    }
  }

  Future<void> _export() async {
    final source = widget.chain.source;
    // Export the transformed output, not the raw source — per the vision the
    // clip is "interpreted, not played", and the file should carry what the
    // chain currently yields.
    final rendered = MidiClip(
      name: source.name,
      notes: widget.chain.output,
      bars: source.bars,
      beatsPerBar: source.beatsPerBar,
    );
    await _fileIo.saveSmf('${source.name}.mid', _writer.write(rendered));
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    // Import the first dropped file that looks like a MIDI file; ignore the
    // rest (Phi has one clip per surface).
    for (final file in details.files) {
      if (_isMidiName(file.name)) {
        _importBytes(await file.readAsBytes());
        return;
      }
    }
  }

  static bool _isMidiName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mid') || lower.endsWith('.midi');
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: _onDrop,
      child: ListenableBuilder(
        listenable: _listenable,
        builder: (context, _) {
          final clip = widget.chain.source;
          final showGhost = widget.chain.transforms.any((t) => t.active);
          return Container(
            color: PhiColors.bg0,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MidiHeaderStrip(
                  clipName: clip.name,
                  noteCount: clip.notes.length,
                  bars: clip.bars,
                  onImport: _pickAndImport,
                  onExport: _export,
                  errorText: _importError,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ViewToolbar(
                              mode: _graph.mode,
                              onSelect: (v) => _graph.mode = v,
                              onAddNode: _graph.mode == MidiClipMode.graph
                                  ? _pickAndAddNode
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _graph.mode == MidiClipMode.chain
                                  ? _buildChainBody(clip, showGhost)
                                  : _buildGraphBody(clip),
                            ),
                          ],
                        ),
                      ),
                      // The chip sidebar edits the *linear* chain, so it belongs
                      // to a chain clip only — a graph clip authors its
                      // transforms as nodes on the canvas, which takes the full
                      // width (issue #77).
                      if (_graph.mode == MidiClipMode.chain) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 250,
                          child: TransformChainPanel(
                            chain: widget.chain,
                            registry: widget.registry,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChainBody(MidiClip clip, bool showGhost) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PianoRollEditor(
            editor: _editor,
            ghostNotes: widget.chain.output,
            showGhost: showGhost,
            bars: clip.bars,
            beatsPerBar: clip.beatsPerBar,
            playhead: widget.playhead,
          ),
        ),
        const SizedBox(height: 8),
        VelocityLane(
          editor: _editor,
          notes: clip.notes,
          bars: clip.bars,
          beatsPerBar: clip.beatsPerBar,
        ),
      ],
    );
  }

  Widget _buildGraphBody(MidiClip clip) {
    // Evaluate the active subgraph for the live context, so the preview strip
    // reflects the state the performance is in (issue #65).
    final notes = _graph.graph.evaluate(_evalContext);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TransformGraphCanvas(
            controller: _graph,
            evalContext: _evalContext,
            stateGraph: widget.stateGraph,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: GraphPreviewStrip(
            notes: notes,
            bars: clip.bars,
            beatsPerBar: clip.beatsPerBar,
          ),
        ),
      ],
    );
  }

  /// Open the built-in + custom transform catalogue and append the picked
  /// transform as a fresh, disconnected node the performer then wires in.
  Future<void> _pickAndAddNode() async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final build = await showMenu<MidiTransform Function()>(
      context: context,
      position: RelativeRect.fromLTRB(120, 120, overlay.size.width - 120, 0),
      color: PhiColors.bg2,
      constraints: const BoxConstraints(maxHeight: 320),
      items: _addMenuItems(),
    );
    if (build == null || !mounted) return;
    _graph.addNodeAt(build(), _nextNodePosition());
  }

  List<PopupMenuEntry<MidiTransform Function()>> _addMenuItems() {
    final items = <PopupMenuEntry<MidiTransform Function()>>[];
    for (final kind in MidiTransformKind.values) {
      final color = PhiVoices.color(kind.voiceIndex);
      items.add(
        PopupMenuItem<MidiTransform Function()>(
          enabled: false,
          height: 24,
          child: Text(
            kind.tag.toUpperCase(),
            style: PhiType.monoS().copyWith(
              fontSize: 8,
              color: color,
              letterSpacing: 0.08 * 8,
            ),
          ),
        ),
      );
      for (final entry in BuiltinTransformCatalog.forKind(kind)) {
        items.add(_addRow(entry.name, entry.build));
      }
      final customs =
          widget.registry?.definitions
              .where((d) => d.kind == kind)
              .toList(growable: false) ??
          const [];
      for (final def in customs) {
        items.add(_addRow('${def.name} · custom', def.instantiate));
      }
    }
    return items;
  }

  PopupMenuItem<MidiTransform Function()> _addRow(
    String label,
    MidiTransform Function() build,
  ) {
    return PopupMenuItem<MidiTransform Function()>(
      value: build,
      height: 30,
      child: Text(
        label,
        style: PhiType.monoS().copyWith(fontSize: 11, color: PhiColors.fg0),
      ),
    );
  }

  /// A staggered scene position for a freshly added node, below the seeded
  /// row so it doesn't land on top of an existing node.
  Offset _nextNodePosition() {
    final n = _graph.graph.nodes.length;
    return Offset(200 + (n % 4) * 190, 380 + (n ~/ 4) * 80);
  }
}

/// The `CHAIN | GRAPH` mode toggle plus, in graph mode, an add-node `+`. This
/// picks the clip's representation (issue #77), not a throwaway view: the
/// selected segment is both what the performer edits and what they hear.
class _ViewToolbar extends StatelessWidget {
  const _ViewToolbar({
    required this.mode,
    required this.onSelect,
    this.onAddNode,
  });

  final MidiClipMode mode;
  final void Function(MidiClipMode mode) onSelect;

  /// Add-node handler, shown only in graph mode (`null` in chain mode).
  final VoidCallback? onAddNode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Segment(
          label: 'chain',
          selected: mode == MidiClipMode.chain,
          onTap: () => onSelect(MidiClipMode.chain),
        ),
        const SizedBox(width: 4),
        _Segment(
          label: 'graph',
          selected: mode == MidiClipMode.graph,
          onTap: () => onSelect(MidiClipMode.graph),
        ),
        const Spacer(),
        if (onAddNode != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAddNode,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '+ node',
                style: PhiType.monoS().copyWith(color: PhiColors.fg1),
              ),
            ),
          ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? PhiColors.bg2 : null,
          border: Border.all(
            color: selected ? PhiColors.line2 : PhiColors.line1,
          ),
          borderRadius: PhiRadii.all1,
        ),
        child: Text(
          label.toUpperCase(),
          style: PhiType.caption().copyWith(
            color: selected ? PhiColors.fg0 : PhiColors.fg2,
          ),
        ),
      ),
    );
  }
}
