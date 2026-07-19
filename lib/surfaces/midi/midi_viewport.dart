import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../design/widgets/dialog/confirm_dialog.dart';
import '../../domain/midi/builtin_transform_catalog.dart';
import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/custom_transform_registry.dart';
import '../../domain/midi/graph/graph_eval_context.dart';
import '../../domain/midi/midi_clip.dart';
import '../../domain/midi/midi_clip_mode.dart';
import '../../domain/midi/midi_clip_seed.dart';
import '../../domain/midi/midi_note.dart';
import '../../domain/midi/midi_transform.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/midi_transform_kind.dart';
import '../../domain/midi/smf/smf_exception.dart';
import '../../domain/midi/smf/smf_reader.dart';
import '../../domain/midi/smf/smf_writer.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/state_machine/state_graph.dart';
import '../../engine/state/midi_graph_controller.dart';
import 'file_selector_midi_file_io.dart';
import 'graph/graph_preview_strip.dart';
import 'graph/runtime_variables_bar.dart';
import 'graph/transform_graph_canvas.dart';
import 'midi_file_io.dart';
import 'midi_header_strip.dart';
import 'piano_roll_editor.dart';
import 'piano_roll_view.dart';
import 'transform_chain_panel.dart';
import 'velocity_lane.dart';

/// Which pane graph mode's `NOTES | GRAPH` tabs show: the editable piano roll
/// (notes) or the node-and-cable canvas (graph). Local UI state — unlike the
/// clip's [MidiClipMode], it doesn't affect playback.
enum _GraphTab { notes, graph }

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
    this.runtimeVariables,
    this.clipName = phraseASlug,
    super.key,
  });

  final MidiTransformChain chain;
  final ClipEditor? editor;

  /// The clip's display name — its registry address leaf (issue #184), shown in
  /// the header and used as the SMF export filename. Defaults to the seeded
  /// clip's leaf; per-clip plumbing arrives with the library panel (#188).
  final String clipName;

  /// The branching transform-graph controller (issue #65). When `null` the
  /// viewport seeds and owns a fallback from [chain] so the graph view is
  /// always available; the shell/engine pass a shared one so the graph state
  /// survives surface switches.
  final MidiGraphController? graphController;

  /// The state machine, for the graph's live evaluation context and its
  /// condition picker. `null` when no state machine is wired — the graph then
  /// evaluates against an empty context (only unconditional edges fire).
  final StateGraph? stateGraph;

  /// The runtime-variable registry backing the graph's `var · name = value`
  /// guards, its live evaluation context, and the variables bar (issue #78).
  /// `null` when none is wired — the variables bar is hidden and the picker
  /// offers no variables.
  final RuntimeVariableRegistry? runtimeVariables;

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

  /// Which tab graph mode shows; defaults to the graph canvas (you convert to
  /// graph to work on the topology). Only meaningful while in graph mode.
  _GraphTab _graphTab = _GraphTab.graph;

  static const _reader = SmfReader();
  static const _writer = SmfWriter();

  /// Transient import error surfaced in the header; cleared on the next
  /// successful import or when a new one is attempted.
  String? _importError;

  /// Session-local pan/zoom for the roll + velocity lane (issue #189). `null`
  /// until the first zoom gesture (fit-to-viewport); shared between the roll and
  /// the velocity lane so their time axes never drift. Not persisted — with the
  /// library panel this viewport is keyed by clip address, so selecting another
  /// clip rebuilds it and the zoom resets, exactly as "session-local" intends.
  PianoRollView? _view;

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
      if (widget.runtimeVariables != null) widget.runtimeVariables,
    ]);
    _fileIo = widget.fileIo ?? const FileSelectorMidiFileIo();
  }

  @override
  void dispose() {
    if (_ownsEditor) _editor.dispose();
    if (_ownsGraph) _graph.dispose();
    super.dispose();
  }

  GraphEvalContext get _evalContext => GraphEvalContext(
    activeStateId: widget.stateGraph?.activeStateId,
    variables: widget.runtimeVariables?.snapshot() ?? const {},
  );

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
      notes: widget.chain.output,
      bars: source.bars,
      beatsPerBar: source.beatsPerBar,
    );
    await _fileIo.saveSmf(
      '${widget.clipName}.mid',
      _writer.write(rendered, name: widget.clipName),
    );
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
                  clipName: widget.clipName,
                  noteCount: clip.notes.length,
                  bars: clip.bars,
                  onImport: _pickAndImport,
                  onExport: _export,
                  errorText: _importError,
                  gridDivision: _editor.gridDivision,
                  onGridChanged: (value) =>
                      setState(() => _editor.gridDivision = value),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _graph.mode == MidiClipMode.chain
                      ? _buildChainMode(clip, showGhost)
                      : _buildGraphMode(clip),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Chain mode — the default: the piano roll edits the source clip, the
  /// `TRANSFORM CHAIN` sidebar manages the linear transforms, and the bar
  /// carries the one-way-ish "convert to graph" action (issue #77).
  Widget _buildChainMode(MidiClip clip, bool showGhost) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChainModeBar(onConvertToGraph: _confirmConvertToGraph),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildRoll(
                  clip,
                  ghostNotes: widget.chain.output,
                  showGhost: showGhost,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 250,
                child: TransformChainPanel(
                  chain: widget.chain,
                  registry: widget.registry,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Graph mode — the branching representation. The canvas needs the full area,
  /// so a `NOTES | GRAPH` tab pair keeps the piano roll a first-class editor
  /// (the roll is the clip; you never have to leave graph mode to edit notes)
  /// while the graph gets its own full-width tab (issue #77).
  Widget _buildGraphMode(MidiClip clip) {
    final onGraphTab = _graphTab == _GraphTab.graph;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GraphModeBar(
          tab: _graphTab,
          onSelectTab: (t) => setState(() => _graphTab = t),
          onAddNode: onGraphTab ? _pickAndAddNode : null,
          onConvertToChain: _confirmConvertToChain,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: onGraphTab
              ? _buildGraphBody(clip)
              : _buildRoll(
                  clip,
                  // The ghost is the graph's live output, so editing a note on
                  // the roll shows how the active subgraph transforms it.
                  ghostNotes: _graph.graph.evaluate(_evalContext),
                  showGhost: _graph.graph.nodes.isNotEmpty,
                ),
        ),
      ],
    );
  }

  /// The piano roll + velocity lane over the shared source clip. Used by chain
  /// mode and by graph mode's `NOTES` tab, with the [ghostNotes] behind the
  /// source differing per mode (chain output vs. graph evaluate).
  Widget _buildRoll(
    MidiClip clip, {
    required List<MidiNote> ghostNotes,
    required bool showGhost,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PianoRollEditor(
            editor: _editor,
            ghostNotes: ghostNotes,
            showGhost: showGhost,
            bars: clip.bars,
            beatsPerBar: clip.beatsPerBar,
            playhead: widget.playhead,
            view: _view,
            onViewChanged: (view) => setState(() => _view = view),
          ),
        ),
        const SizedBox(height: 8),
        VelocityLane(
          editor: _editor,
          notes: clip.notes,
          bars: clip.bars,
          beatsPerBar: clip.beatsPerBar,
          view: _view,
        ),
      ],
    );
  }

  // ── Chain ↔ graph conversion ───────────────────────────────────────────────

  /// Convert the linear chain clip to a branching graph clip, after a
  /// confirmation that flags the near-one-way nature. Re-seeds the graph from
  /// the *current* chain so it opens on exactly what was sounding.
  Future<void> _confirmConvertToGraph() async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'convert to graph',
      message:
          'A graph lets transforms branch and route on the live state. Once you '
          'add branches you may not be able to convert everything back to a '
          'chain. Continue?',
      confirmLabel: 'convert',
    );
    if (!ok || !mounted) return;
    _graph.loadFromChain(widget.chain);
    _graph.mode = MidiClipMode.graph;
    setState(() => _graphTab = _GraphTab.graph);
  }

  /// Convert the graph clip back to a linear chain, after a confirmation that
  /// warns about dropped branches when the graph is not already linear. Writes
  /// the graph's spine into the chain so playback follows the moment the mode
  /// flips.
  Future<void> _confirmConvertToChain() async {
    final branched = !_graph.graph.isLinear;
    final ok = await ConfirmDialog.show(
      context,
      title: 'convert to chain',
      message: branched
          ? 'This graph branches or routes on state — a linear chain can\'t '
                'hold that. Converting keeps only the main path and drops the '
                'rest. Continue?'
          : 'Convert this graph back to a linear chain?',
      confirmLabel: 'convert',
    );
    if (!ok || !mounted) return;
    widget.chain.setTransforms(_graph.graph.linearTransforms());
    _graph.mode = MidiClipMode.chain;
  }

  Widget _buildGraphBody(MidiClip clip) {
    // Evaluate the active subgraph for the live context, so the preview strip
    // reflects the state the performance is in (issue #65) and the runtime
    // variables it holds (issue #78).
    final notes = _graph.graph.evaluate(_evalContext);
    final registry = widget.runtimeVariables;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (registry != null) ...[
          RuntimeVariablesBar(registry: registry),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: TransformGraphCanvas(
            controller: _graph,
            evalContext: _evalContext,
            stateGraph: widget.stateGraph,
            runtimeVariables: registry,
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

/// Chain mode's bar: a static `CHAIN` tag on the left (so the current
/// representation reads at a glance) and the `convert to graph →` action on the
/// right (issue #77).
class _ChainModeBar extends StatelessWidget {
  const _ChainModeBar({required this.onConvertToGraph});

  final VoidCallback onConvertToGraph;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _ModeTag(label: 'chain'),
        const Spacer(),
        _BarAction(label: 'convert to graph →', onTap: onConvertToGraph),
      ],
    );
  }
}

/// Graph mode's bar: the `NOTES | GRAPH` tab pair on the left, and on the right
/// the add-node `+` (graph tab only) and the `← convert to chain` action
/// (issue #77).
class _GraphModeBar extends StatelessWidget {
  const _GraphModeBar({
    required this.tab,
    required this.onSelectTab,
    required this.onConvertToChain,
    this.onAddNode,
  });

  final _GraphTab tab;
  final void Function(_GraphTab tab) onSelectTab;
  final VoidCallback onConvertToChain;

  /// Add-node handler, shown only on the graph tab (`null` on the notes tab).
  final VoidCallback? onAddNode;

  @override
  Widget build(BuildContext context) {
    final addNode = onAddNode;
    return Row(
      children: [
        _Segment(
          label: 'notes',
          selected: tab == _GraphTab.notes,
          onTap: () => onSelectTab(_GraphTab.notes),
        ),
        const SizedBox(width: 4),
        _Segment(
          label: 'graph',
          selected: tab == _GraphTab.graph,
          onTap: () => onSelectTab(_GraphTab.graph),
        ),
        const Spacer(),
        if (addNode != null) ...[
          _BarAction(label: '+ node', onTap: addNode),
          const SizedBox(width: 12),
        ],
        _BarAction(label: '← convert to chain', onTap: onConvertToChain),
      ],
    );
  }
}

/// A non-interactive capsule naming the current clip mode — the static twin of
/// a selected [_Segment], so a mode reads at a glance without looking clickable.
class _ModeTag extends StatelessWidget {
  const _ModeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        border: Border.all(color: PhiColors.line2),
        borderRadius: PhiRadii.all1,
      ),
      child: Text(
        label.toUpperCase(),
        style: PhiType.caption().copyWith(color: PhiColors.fg0),
      ),
    );
  }
}

/// A slim text action button for the mode bars (`convert …`, `+ node`).
class _BarAction extends StatelessWidget {
  const _BarAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: PhiType.monoS().copyWith(color: PhiColors.fg1),
        ),
      ),
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
