import 'package:flutter/material.dart';
import 'package:yse/yse.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../engine/bridge/patch_object_descriptor.dart';
import '../../engine/engine.dart';
import '../../engine/state/node_type_registry.dart';
import '../../engine/state/patcher_controller.dart';
import '../surface.dart';
import 'library/patch_entity_strip.dart';
import 'palette/patcher_palette.dart';
import 'patch_canvas_mode.dart';
import 'patch_gui_poller.dart';
import 'patcher_canvas.dart';
import 'patcher_node_types.dart';
import 'placement/patch_placement_bar.dart';
import 'reference/patch_reference_panel.dart';

/// A verb on the node context menu (issue #356). Every one of them already has
/// a keyboard route; the menu is what makes them discoverable without one.
enum _NodeAction { duplicate, delete }

/// Patcher surface — pan/zoom canvas of nodes and cables.
///
/// Requires the engine to be started: the [PatcherController] is created
/// in [PhiEngine.start] and torn down in `stop`. Before start the surface
/// renders a low-key placeholder.
class PatcherSurface extends Surface {
  const PatcherSurface({required this.engine, this.active = true, super.key});

  final PhiEngine engine;

  /// Whether this surface is the visible tab of its pane. The shell keeps
  /// background tabs mounted (so their state survives a switch), so a surface
  /// cannot work its own visibility out — the shell hands it down, exactly as
  /// it does for the Scene renderer. Here it gates the live-value refresh
  /// ([PatchGuiPoller], issue #357): a patcher nobody is looking at polls
  /// nothing. Defaults to true, which is what a surface mounted on its own —
  /// in a widget test, or any host with no tab stack — always is.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      child: engine.patcherOrNull != null
          ? _PatcherViewport(engine: engine, active: active)
          : const _Offline(),
    );
  }
}

/// Inner widget that owns the one-shot seeding of the default graph.
///
/// Kept separate so the seed runs once on first mount, not on every
/// Flutter rebuild of the surrounding chrome.
class _PatcherViewport extends StatefulWidget {
  const _PatcherViewport({required this.engine, required this.active});

  final PhiEngine engine;

  /// Passed through to the [PatchGuiPoller] — see [PatcherSurface.active].
  final bool active;

  @override
  State<_PatcherViewport> createState() => _PatcherViewportState();
}

class _PatcherViewportState extends State<_PatcherViewport> {
  /// The engine's object catalogue — stable for the surface's lifetime, so it
  /// is read once rather than on every rebuild.
  late final List<PatchObjectDescriptor> _objectTypes;

  /// The type reflected in the reference panel (from a palette tap or a canvas
  /// node tap), or null for the empty state.
  PatchObjectDescriptor? _selected;

  /// The canvas node the reference panel is documenting, when the reference
  /// came from a node rather than a palette entry — the panel then shows that
  /// node's *current* argument values beside each documented parameter
  /// (issue #356). Null for a palette tap, which documents a type.
  PatchNodeId? _selectedNodeId;

  /// Whether the canvas quantises a node drop to the grid (issue #368). A view
  /// preference of the surface, not of the patch: it belongs to how this user
  /// is arranging things right now, so it lives here beside the reference-panel
  /// selection rather than in the payload or the engine.
  bool _snapToGrid = false;

  /// Whether the canvas is being edited or played (issue #378, design §6).
  ///
  /// **Performance state**, so it lives here and nowhere else: per open
  /// surface, never written to the payload, and therefore a reopened project
  /// starts in [PatchCanvasMode.edit]. Held above the canvas rather than inside
  /// it because the placement bar's indicator names the same mode — and because
  /// the canvas is re-keyed per open patch, while the mode deliberately is not.
  PatchCanvasMode _mode = PatchCanvasMode.edit;

  @override
  void initState() {
    super.initState();
    registerBuiltInPatcherNodes();
    _seedDefaultGraphIfEmpty(widget.engine.patcher);
    _objectTypes = widget.engine.patcher.objectTypes();
  }

  /// Switch the canvas between editing and playing (issue #378) — from the
  /// placement bar's toggle or from the canvas's own `Ctrl+E`.
  ///
  /// Leaving edit mode drops the selection: a selection is an editing state,
  /// and a run-mode canvas that cannot select or deselect anything must not
  /// keep drawing rings around nodes nothing can do anything to.
  void _setMode(PatchCanvasMode mode) {
    if (mode == _mode) return;
    if (mode.isRun) widget.engine.patchLibrary.openEditor?.clearSelection();
    setState(() => _mode = mode);
  }

  void _select(PatchObjectDescriptor desc) => setState(() {
    _selected = desc;
    // A palette entry documents a type — there is no instance to read values
    // from, so any previously-selected node's values are dropped.
    _selectedNodeId = null;
  });

  void _selectNode(PatchNode node) {
    final desc = _descriptorForType(node.type);
    if (desc == null) return;
    setState(() {
      _selected = desc;
      _selectedNodeId = node.id;
    });
  }

  /// Create [desc] at [position] — the one creation path both canvas gestures
  /// come through: a palette entry dropped on the canvas (design §5) and the
  /// inline object box's Enter (issue #358). [args] is the box's checked
  /// argument string; null means the type's documented defaults, which is what
  /// a drop wants. Journaled either way, so `Ctrl+Z` un-creates.
  ///
  /// The reference panel follows the object just made (issue #437): pointed at
  /// the created *node* — so the values it actually holds sit beside each
  /// documented parameter — falling back to the bare type documentation when
  /// the node cannot be resolved. This is what makes a drop teach: the object
  /// lands, and its arguments are already on screen.
  void _createObject(
    PatchObjectDescriptor desc,
    Offset position, {
    String? args,
  }) {
    final controller = widget.engine.patcher;
    final id = controller.createObject(
      desc: desc,
      position: position,
      args: args,
    );
    final node = id == null ? null : controller.graph.nodeById(id);
    node == null ? _select(desc) : _selectNode(node);
  }

  /// Right-click on a node: the standard affordances, named (issue #356).
  ///
  /// The canvas has already pointed the selection at [node] — either alone, or
  /// as one member of a multi-selection it was already part of — so `duplicate`
  /// and `delete` act on exactly what the pointer named. They are the same
  /// controller verbs `Ctrl+D` and `Delete` reach, journaled the same way; the
  /// menu only makes them findable without the shortcut.
  ///
  /// `edit parameters…` is **not** among them any more (issue #382): the verb's
  /// whole content was "open the params dialog", and with the box as the editor
  /// there is no dialog to open — arguments are typed on the object itself,
  /// double-click, and documented by the reference panel beside it (design
  /// §7/§12.3).
  ///
  /// The editor is resolved *after* the menu closes, since the open patch can
  /// change while it is up.
  Future<void> _onNodeContextMenu(PatchNode node, Offset global) async {
    final action = await _showNodeMenu(global);
    if (action == null || !mounted) return;
    final controller = widget.engine.patcherOrNull;
    if (controller == null) return;
    switch (action) {
      case _NodeAction.duplicate:
        controller.duplicateSelection();
      case _NodeAction.delete:
        controller.deleteSelection();
    }
  }

  /// The node context menu, anchored at the global pointer position — same
  /// styling as the state canvas's menus so the two surfaces feel of a piece.
  Future<_NodeAction?> _showNodeMenu(Offset global) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return showMenu<_NodeAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(global, global),
        Offset.zero & overlay.size,
      ),
      color: PhiColors.bg2,
      items: [
        _menuItem('duplicate · ctrl+d', _NodeAction.duplicate),
        _menuItem('delete · del', _NodeAction.delete),
      ],
    );
  }

  PopupMenuItem<_NodeAction> _menuItem(String label, _NodeAction action) {
    return PopupMenuItem<_NodeAction>(
      value: action,
      height: 32,
      child: Text(
        label,
        style: PhiType.monoS().copyWith(fontSize: 11, color: PhiColors.fg0),
      ),
    );
  }

  PatchObjectDescriptor? _descriptorForType(String type) {
    for (final d in _objectTypes) {
      if (d.type == type) return d;
    }
    return null;
  }

  void _seedDefaultGraphIfEmpty(PatcherController controller) {
    if (controller.graph.nodes.isNotEmpty) return;
    final registry = NodeTypeRegistry.instance;
    // Note: gSlider outputs raw [0, 1] and `~sine` reads inlet[0] as a
    // frequency in Hz, so the slider's range only sweeps 0–1 Hz here —
    // sub-audible. A math-node mapping arrives in a follow-up; for now
    // the demo proves the architecture, not the musicality.
    final slider = controller.addNode(
      desc: registry.find(Obj.gSlider)!,
      position: const Offset(120, 180),
      voice: 1,
    );
    final sine = controller.addNode(
      desc: registry.find(Obj.dSine)!,
      position: const Offset(280, 220),
      voice: 2,
    );
    final dac = controller.addNode(
      desc: registry.find(Obj.dDac)!,
      position: const Offset(500, 240),
      voice: 3,
    );
    controller.connect(
      _portId(slider.id, PatchPortSide.output, 0),
      _portId(sine.id, PatchPortSide.input, 0),
    );
    controller.connect(
      _portId(sine.id, PatchPortSide.output, 0),
      _portId(dac.id, PatchPortSide.input, 0),
    );
    // Now that the patcher has a `~dac`, it's safe to bind a Sound to it.
    controller.mountAudio();
  }

  PatchPortId _portId(PatchNodeId id, PatchPortSide side, int index) =>
      PatchPortId(nodeId: id, side: side, index: index);

  @override
  Widget build(BuildContext context) {
    final library = widget.engine.patchLibrary;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final editor = library.openEditor;
        return Row(
          children: [
            PatchEntityStrip(controller: library),
            PatcherPalette(
              objectTypes: _objectTypes,
              selected: _selected,
              onSelect: _select,
            ),
            Expanded(
              child: Column(
                children: [
                  PatchPlacementBar(
                    controller: library,
                    snapToGrid: _snapToGrid,
                    onSnapChanged: (on) => setState(() => _snapToGrid = on),
                    mode: _mode,
                    onModeChanged: _setMode,
                  ),
                  Expanded(
                    child: editor == null
                        ? const _NoPatchOpen()
                        // The live-value refresh is scoped to an open patch:
                        // with none, there is nothing to poll and no poller
                        // (issue #357).
                        : PatchGuiPoller(
                            controller: editor,
                            active: widget.active,
                            child: PatcherCanvas(
                              // Re-key on the open address so switching patches
                              // rebuilds the canvas against the new editor.
                              key: ValueKey(library.openAddress),
                              controller: editor,
                              objectTypes: _objectTypes,
                              snapToGrid: _snapToGrid,
                              mode: _mode,
                              onToggleMode: () => _setMode(_mode.flipped),
                              onCreateObject: _createObject,
                              onNodeTap: _selectNode,
                              onNodeContextMenu: _onNodeContextMenu,
                              // The panel switches the moment the inline box's
                              // typed name settles on a type, so the arguments
                              // are documented while they are being typed
                              // (issue #437).
                              onTypeResolved: _select,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            _reference(editor),
          ],
        );
      },
    );
  }

  /// The reference panel, fed the selected node's **live** arguments when the
  /// reference came from the canvas (issue #356).
  ///
  /// Bound to the graph rather than read once: a params apply and its undo/redo
  /// wake the node, the graph re-broadcasts that, and the panel's values follow
  /// the edit without the user having to re-select anything.
  ///
  /// Values are shown only while the remembered node is still there **and still
  /// of the documented type**. Node ids are native handles, unique only inside
  /// their own patcher, so after switching patches the id could otherwise
  /// resolve to an unrelated object and print its arguments against the wrong
  /// parameter list. Failing that check leaves the type documentation standing
  /// on its own, which is exactly what a palette tap shows.
  Widget _reference(PatcherController? editor) {
    final id = _selectedNodeId;
    if (editor == null || id == null) {
      return PatchReferencePanel(descriptor: _selected);
    }
    return ListenableBuilder(
      listenable: editor.graph,
      builder: (context, _) {
        final node = editor.graph.nodeById(id);
        final documented = node != null && node.type == _selected?.type;
        return PatchReferencePanel(
          descriptor: _selected,
          args: documented ? editor.argsOf(id) : null,
        );
      },
    );
  }
}

/// Shown in the canvas area when the `patch.` namespace is empty — every patch
/// was deleted, so there is nothing to edit until one is created from the strip.
class _NoPatchOpen extends StatelessWidget {
  const _NoPatchOpen();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      alignment: Alignment.center,
      child: Text(
        'no patch open · add one from the strip'.toUpperCase(),
        style: PhiType.caption(),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'patcher offline · start the engine'.toUpperCase(),
        style: PhiType.caption(),
      ),
    );
  }
}
