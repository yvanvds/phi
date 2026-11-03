import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/project/undo_scope.dart';
import '../../domain/project/undo_scopes.dart';
import '../../engine/bridge/patch_object_descriptor.dart';
import '../../engine/engine.dart';
import '../../engine/state/patch_library_controller.dart';
import '../../engine/state/patcher_controller.dart';
import '../surface.dart';
import 'library/patch_entity_strip.dart';
import 'palette/patcher_palette.dart';
import 'palette/patcher_palette_tab.dart';
import 'patch_canvas_mode.dart';
import 'patch_gui_poller.dart';
import 'patcher_canvas.dart';
import 'patcher_node_types.dart';
import 'placement/patch_placement_bar.dart';
import 'reference/patch_reference_panel.dart';
import 'reference/patch_subpatch_summary.dart';
import 'subpatch/subpatch_window_entry.dart';
import 'subpatch/subpatch_window_view.dart';
import 'subpatch/subpatch_windows.dart';
import 'subpatch/subpatch_windows_host.dart';
import 'tutorial/patch_tutorial_bar.dart';

/// A verb on the node context menu (issue #356). Every one of them already has
/// a keyboard route; the menu is what makes them discoverable without one.
enum _NodeAction {
  openDefinition,
  openSubpatch,
  makeAbstraction,
  detach,
  encapsulate,
  deencapsulate,
  duplicate,
  delete,
}

/// Patcher surface — pan/zoom canvas of nodes and cables.
///
/// Requires the engine to be started: the [PatcherController] is created
/// in [PhiEngine.start] and torn down in `stop`. Before start the surface
/// renders a low-key placeholder.
class PatcherSurface extends Surface {
  const PatcherSurface({
    required this.engine,
    this.active = true,
    this.undoScopes,
    super.key,
  });

  final PhiEngine engine;

  /// Key on the node menu's `open subpatch` item (issue #481).
  static const Key openSubpatchItemKey = Key('PatcherSurface.openSubpatch');

  /// Key on the node menu's `open definition` item (issue #553).
  static const Key openDefinitionItemKey = Key('PatcherSurface.openDefinition');

  /// Key on the node menu's `make abstraction` item (issue #553).
  static const Key makeAbstractionItemKey = Key(
    'PatcherSurface.makeAbstraction',
  );

  /// Key on the node menu's `detach` item (issue #553).
  static const Key detachItemKey = Key('PatcherSurface.detach');

  /// Key on the node menu's `encapsulate` item (issue #552).
  static const Key encapsulateItemKey = Key('PatcherSurface.encapsulate');

  /// Key on the node menu's `de-encapsulate` item (issue #552).
  static const Key deencapsulateItemKey = Key('PatcherSurface.deencapsulate');

  /// The shell's undo router (#512). The surface registers the open patch's
  /// [UndoScope] here under [PatcherController.undoScopeId], so the shell's
  /// Ctrl+Z/Y reach the patch from anywhere in the pane — after a click in the
  /// palette, the placement bar or the reference panel has taken the keyboard
  /// off the canvas. Null (a surface mounted on its own) registers nothing.
  final UndoScopes? undoScopes;

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
          ? _PatcherViewport(
              engine: engine,
              active: active,
              undoScopes: undoScopes,
            )
          : const _Offline(),
    );
  }
}

/// Inner widget that owns the one-shot seeding of the default graph.
///
/// Kept separate so the seed runs once on first mount, not on every
/// Flutter rebuild of the surrounding chrome.
class _PatcherViewport extends StatefulWidget {
  const _PatcherViewport({
    required this.engine,
    required this.active,
    this.undoScopes,
  });

  final PhiEngine engine;

  /// Passed through to the [PatchGuiPoller] — see [PatcherSurface.active].
  final bool active;

  /// See [PatcherSurface.undoScopes].
  final UndoScopes? undoScopes;

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

  /// The editor [_selectedNodeId] belongs to: the open patch's, or the
  /// definition's when the node was tapped in a definition's window (issue
  /// #553). Null means the open patch's.
  PatcherController? _selectedEditor;

  /// The canvas's keyboard focus, held here so a pick in the reference panel
  /// can hand the keyboard straight back to the canvas (issue #511): the pane
  /// takes focus on any press inside it. Undo no longer depends on it — the
  /// shell reaches the patch's stack from the pane too (#512) — but the canvas's
  /// own keys (`N`, the arrows, `Delete`) do, so the hand-back stays.
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'patcher-canvas');

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

  /// Which list the palette shows (issue #489) — switched to the tutorials by
  /// the "Open Patcher Tutorial…" command through
  /// [PatchLibraryController.tutorialBrowserRequests].
  PatcherPaletteTab _paletteTab = PatcherPaletteTab.objects;

  /// The engine's patch library, held so its listener can be detached on
  /// dispose. Stable for the viewport's lifetime: a project swap rebinds it
  /// and a session restart re-opens through it, neither replaces it.
  late final PatchLibraryController _library;

  /// The stack this surface last registered with [_PatcherViewport.undoScopes],
  /// or null when it has none registered.
  UndoScope? _registeredScope;

  /// The subpatch windows open over this surface (issue #481). Owned here, so
  /// they go when the surface does, and pruned to the open patch's editor.
  final SubpatchWindows _subpatchWindows = SubpatchWindows();

  @override
  void initState() {
    super.initState();
    registerBuiltInPatcherNodes();
    _objectTypes = widget.engine.patcher.objectTypes();
    _library = widget.engine.patchLibrary;
    _library.addListener(_syncUndoScope);
    _library.addListener(_closeForeignSubpatches);
    _library.tutorialBrowserRequests.addListener(_showTutorials);
    _syncUndoScope();
  }

  /// A subpatch window never outlives the patch it was opened from being the
  /// open one: a switch, a tutorial, a project swap or a session restart (a
  /// fresh editor) closes them (issue #481). Nor does a definition's window
  /// outlive the definition's editor, which a rename or delete disposes (#553).
  void _closeForeignSubpatches() {
    _subpatchWindows
      ..closeAllExcept(_library.openEditor)
      ..closeUnless(_library.isLive);
  }

  /// Open [box] of [editor] in its own window, or focus it when it is open.
  ///
  /// An instance of an abstraction (issue #553) opens like any box and shows
  /// that instance's own objects, to be played: [_subpatchWindow] holds such a
  /// window in run mode. Editing happens in [_openDefinition].
  void _openSubpatch(PatcherController editor, PatchNode box) {
    final open = _library.openEditor;
    _subpatchWindows.open(
      editor,
      box.id,
      owner: open,
      root: identical(editor, open) ? null : _rootOf(editor),
    );
  }

  /// What a window showing part of [editor]'s patch calls that patch.
  String? _rootOf(PatcherController editor) =>
      _library.addressOf(editor)?.format();

  /// Open the patch the instance [box] follows in its own window, where editing
  /// it changes every instance (issue #553). A box whose definition is gone or
  /// is not followed has only its own contents to show.
  void _openDefinition(PatcherController editor, PatchNode box) {
    final definition = editor.abstractionOf(box.id);
    final target = definition != null && _library.canFollow(editor, definition)
        ? _library.editorFor(definition)
        : null;
    if (definition == null || target == null) {
      _openSubpatch(editor, box);
      return;
    }
    _subpatchWindows.open(
      target,
      null,
      owner: _library.openEditor,
      root: definition.format(),
    );
  }

  /// Every object [editor]'s patch can make: the engine's, and an instance of
  /// each patch it can use (issue #553).
  List<PatchObjectDescriptor> _typesFor(PatcherController editor) => [
    ..._objectTypes,
    ..._library.abstractionTypes(editor),
  ];

  void _showTutorials() =>
      setState(() => _paletteTab = PatcherPaletteTab.tutorials);

  /// A tutorial is open: the canvas is **read-only** (issue #489) — run mode
  /// only (its demo controls must be playable), no edit gesture, no undo.
  bool get _readOnly => _library.tutorial != null;

  /// The mode the canvas actually runs in: run while a tutorial is open,
  /// whatever the performer chose otherwise. [_mode] itself is left alone, so
  /// closing the tutorial puts the patch back the way it was.
  PatchCanvasMode get _effectiveMode => _readOnly ? PatchCanvasMode.run : _mode;

  /// Open [type]'s tutorial. The node the reference panel was reading values
  /// from belongs to the patch being left, so it is forgotten; the documented
  /// type stays, since the tutorial is about it.
  Future<void> _openTutorial(String type) async {
    final opened = await _library.openTutorial(type);
    if (!opened || !mounted) return;
    setState(() => _selectedNodeId = null);
  }

  @override
  void didUpdateWidget(_PatcherViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.undoScopes, widget.undoScopes)) {
      _withdrawUndoScope(oldWidget.undoScopes);
      _syncUndoScope();
    }
  }

  @override
  void dispose() {
    _library.removeListener(_syncUndoScope);
    _library.removeListener(_closeForeignSubpatches);
    _library.tutorialBrowserRequests.removeListener(_showTutorials);
    _subpatchWindows.dispose();
    _withdrawUndoScope(widget.undoScopes);
    _canvasFocus.dispose();
    super.dispose();
  }

  /// Keeps the shell's undo router pointed at the open patch's stack (#512):
  /// re-registered on a patch switch, a project swap and a session restart
  /// (each hands the library a different editor, and the library notifies),
  /// and withdrawn while there is no patch open or the canvas is in run mode —
  /// a played patch cannot be rearranged by a mistyped chord (design §6), from
  /// the canvas or from the shell.
  void _syncUndoScope() {
    final scopes = widget.undoScopes;
    if (scopes == null) return;
    final scope = _effectiveMode.isRun ? null : _library.openEditor?.undoScope;
    if (identical(scope, _registeredScope)) return;
    if (scope == null) {
      scopes.unregister(PatcherController.undoScopeId);
    } else {
      scopes.register(scope);
    }
    _registeredScope = scope;
  }

  /// Drops this surface's stack from [scopes], if it is still the one there.
  void _withdrawUndoScope(UndoScopes? scopes) {
    final mine = _registeredScope;
    _registeredScope = null;
    if (scopes == null || mine == null) return;
    if (scopes.scopes.any((s) => identical(s, mine))) {
      scopes.unregister(mine.id);
    }
  }

  /// Switch the canvas between editing and playing (issue #378) — from the
  /// placement bar's toggle or from the canvas's own `Ctrl+E`.
  ///
  /// Leaving edit mode drops the selection: a selection is an editing state,
  /// and a run-mode canvas that cannot select or deselect anything must not
  /// keep drawing rings around nodes nothing can do anything to.
  ///
  /// Refused while a tutorial is open: a tutorial is read-only (issue #489).
  void _setMode(PatchCanvasMode mode) {
    if (_readOnly) return;
    if (mode == _mode) return;
    if (mode.isRun) widget.engine.patchLibrary.openEditor?.clearSelection();
    setState(() => _mode = mode);
    _syncUndoScope();
  }

  void _select(PatchObjectDescriptor desc) => setState(() {
    _selected = desc;
    // A palette entry documents a type — there is no instance to read values
    // from, so any previously-selected node's values are dropped.
    _selectedNodeId = null;
    _selectedEditor = null;
  });

  void _selectNode(PatchNode node, {PatcherController? editor}) {
    final desc = _descriptorForType(node.type);
    if (desc == null) return;
    setState(() {
      _selected = desc;
      _selectedNodeId = node.id;
      _selectedEditor = editor;
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
  ///
  /// [container] is the subpatch box whose window the gesture was made in, or
  /// null for the main canvas (issue #481). [editor] is the patch it was made
  /// in, when that is not the open one: a definition's window (issue #553).
  void _createObject(
    PatchObjectDescriptor desc,
    Offset position, {
    String? args,
    PatchNodeId? container,
    PatcherController? editor,
  }) {
    if (_readOnly) return;
    final controller = editor ?? widget.engine.patcher;
    final id = controller.createObject(
      desc: desc,
      position: position,
      args: args,
      container: container,
    );
    final node = id == null ? null : controller.graph.nodeById(id);
    node == null ? _select(desc) : _selectNode(node, editor: editor);
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
  ///
  /// A subpatch box adds `open subpatch` on top (issue #481) — the way into
  /// its window from edit mode, where a double-click edits the box's text —
  /// and `de-encapsulate`; any selection that can move into a new box offers
  /// `encapsulate` (issue #552). An ordinary subpatch offers `make abstraction`,
  /// and an instance `open definition` and `detach` (issue #553).
  /// [menuContext] is where the menu opens: the surface for the main canvas,
  /// the subpatch window for its own. [editor] is the patch the node is in, when
  /// that is not the open one: a definition's window.
  Future<void> _onNodeContextMenu(
    PatchNode node,
    Offset global, {
    BuildContext? menuContext,
    PatcherController? editor,
  }) async {
    PatcherController? current() => editor ?? widget.engine.patcherOrNull;
    final controller = current();
    final isBox = controller?.isSubpatch(node.id) ?? false;
    final isInstance = controller?.abstractionOf(node.id) != null;
    final action = await _showNodeMenu(
      menuContext ?? context,
      global,
      subpatch: isBox,
      instance: isInstance,
      // A patch only a tutorial holds has no place to put a definition.
      canAbstract: controller != null && _library.addressOf(controller) != null,
      encapsulate: controller?.canEncapsulate ?? false,
    );
    if (action == null || !mounted) return;
    final target = current();
    if (target == null || !_library.isLive(target)) return;
    switch (action) {
      case _NodeAction.openDefinition:
        _openDefinition(target, node);
      case _NodeAction.openSubpatch:
        _openSubpatch(target, node);
      case _NodeAction.makeAbstraction:
        _library.makeAbstraction(target, node.id);
      case _NodeAction.detach:
        target.detachInstance(node.id);
      case _NodeAction.encapsulate:
        final box = target.encapsulateSelection();
        final boxNode = box == null ? null : target.graph.nodeById(box);
        if (boxNode != null) _selectNode(boxNode, editor: editor);
      case _NodeAction.deencapsulate:
        target.deencapsulateSelection();
      case _NodeAction.duplicate:
        target.duplicateSelection();
      case _NodeAction.delete:
        target.deleteSelection();
    }
  }

  /// The node context menu, anchored at the global pointer position — same
  /// styling as the state canvas's menus so the two surfaces feel of a piece.
  Future<_NodeAction?> _showNodeMenu(
    BuildContext menuContext,
    Offset global, {
    bool subpatch = false,
    bool instance = false,
    bool canAbstract = false,
    bool encapsulate = false,
  }) {
    final overlay =
        Overlay.of(menuContext).context.findRenderObject() as RenderBox;
    return showMenu<_NodeAction>(
      context: menuContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(global, global),
        Offset.zero & overlay.size,
      ),
      color: PhiColors.bg2,
      items: [
        if (instance) _menuItem('open definition', _NodeAction.openDefinition),
        if (subpatch)
          _menuItem(
            instance ? 'open instance' : 'open subpatch',
            _NodeAction.openSubpatch,
          ),
        if (subpatch && !instance && canAbstract)
          _menuItem('make abstraction', _NodeAction.makeAbstraction),
        if (instance) _menuItem('detach', _NodeAction.detach),
        if (encapsulate)
          _menuItem('encapsulate · ctrl+shift+e', _NodeAction.encapsulate),
        if (subpatch)
          _menuItem('de-encapsulate · ctrl+shift+d', _NodeAction.deencapsulate),
        _menuItem('duplicate · ctrl+d', _NodeAction.duplicate),
        _menuItem('delete · del', _NodeAction.delete),
      ],
    );
  }

  PopupMenuItem<_NodeAction> _menuItem(String label, _NodeAction action) {
    return PopupMenuItem<_NodeAction>(
      key: switch (action) {
        _NodeAction.openDefinition => PatcherSurface.openDefinitionItemKey,
        _NodeAction.makeAbstraction => PatcherSurface.makeAbstractionItemKey,
        _NodeAction.detach => PatcherSurface.detachItemKey,
        _NodeAction.openSubpatch => PatcherSurface.openSubpatchItemKey,
        _NodeAction.encapsulate => PatcherSurface.encapsulateItemKey,
        _NodeAction.deencapsulate => PatcherSurface.deencapsulateItemKey,
        _ => null,
      },
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

  /// One subpatch window's content (issue #481), configured from this
  /// surface's state on every rebuild — the mode and the read-only rule are
  /// the patch's, wherever it is shown.
  ///
  /// A window onto an instance of an abstraction (issue #553) is played, not
  /// edited: what is in there comes from the definition, so it stays in run
  /// mode with no gesture to change it. A window onto a patch other than the
  /// open one brings a value poll of its own, since the surface's follows only
  /// the open patch.
  Widget _subpatchWindow(BuildContext context, SubpatchWindowEntry entry) {
    final editor = entry.editor;
    final box = entry.box;
    final foreign = !identical(editor, _library.openEditor);
    final frozen = box != null && editor.isWithinInstance(box);
    final readOnly = _readOnly || frozen;
    final view = SubpatchWindowView(
      editor: editor,
      box: box,
      root: entry.root,
      objectTypes: _typesFor(editor),
      mode: frozen ? PatchCanvasMode.run : _effectiveMode,
      snapToGrid: _snapToGrid,
      onToggleMode: readOnly ? null : () => _setMode(_mode.flipped),
      onCreateObject: readOnly
          ? null
          : (desc, position, {args}) => _createObject(
              desc,
              position,
              args: args,
              container: box,
              editor: foreign ? editor : null,
            ),
      onNodeTap: (node) => _selectNode(node, editor: foreign ? editor : null),
      onNodeContextMenu: frozen
          ? null
          : (menuContext, node, global) => _onNodeContextMenu(
              node,
              global,
              menuContext: menuContext,
              editor: foreign ? editor : null,
            ),
      onOpenSubpatch: (node) => _openSubpatch(editor, node),
      onTypeResolved: _select,
    );
    final firstOfEditor = identical(
      _subpatchWindows.entries.firstWhere((e) => identical(e.editor, editor)),
      entry,
    );
    if (!foreign || !firstOfEditor) return view;
    return PatchGuiPoller(controller: editor, active: true, child: view);
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.engine.patchLibrary;
    return SubpatchWindowsHost(
      windows: _subpatchWindows,
      builder: _subpatchWindow,
      child: _buildMain(library),
    );
  }

  Widget _buildMain(PatchLibraryController library) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, _subpatchWindows]),
      builder: (context, _) {
        final editor = library.openEditor;
        final tutorial = library.tutorial;
        final mode = _effectiveMode;
        return Row(
          children: [
            PatchEntityStrip(controller: library),
            PatcherPalette(
              objectTypes: editor == null ? _objectTypes : _typesFor(editor),
              selected: _selected,
              onSelect: _select,
              tab: _paletteTab,
              onTabChanged: (tab) => setState(() => _paletteTab = tab),
              tutorialTypes: library.tutorials.types.toSet(),
              onOpenTutorial: (type) => unawaited(_openTutorial(type)),
            ),
            Expanded(
              child: Column(
                children: [
                  if (tutorial != null)
                    PatchTutorialBar(
                      title: tutorial.tutorial.title,
                      onCopyToProject: library.copyTutorialToProject,
                      onClose: library.closeTutorial,
                    )
                  else
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
                            // Keyed on the editor itself: an engine session
                            // restart (issue #448) re-binds the *same* open
                            // patch to a fresh editor, which must rebuild the
                            // poller and canvas just as a patch switch does.
                            key: ObjectKey(editor),
                            controller: editor,
                            // A subpatch window is on screen by itself, so
                            // its values keep moving while the patcher tab is
                            // in the background (issue #481).
                            active:
                                widget.active ||
                                _subpatchWindows.hasWindowsFor(editor),
                            child: PatcherCanvas(
                              // Re-key on the open address so switching patches
                              // rebuilds the canvas against the new editor.
                              // A tutorial is not a project patch: keyed on
                              // its session so opening / closing one rebuilds
                              // the canvas too (issue #489).
                              key: ValueKey<Object?>(
                                tutorial ?? library.openAddress,
                              ),
                              controller: editor,
                              objectTypes: _typesFor(editor),
                              snapToGrid: _snapToGrid,
                              mode: mode,
                              // Read-only: no way into edit mode, and no
                              // drop target to create through.
                              onToggleMode: tutorial != null
                                  ? null
                                  : () => _setMode(_mode.flipped),
                              onCreateObject: tutorial != null
                                  ? null
                                  : _createObject,
                              onNodeTap: _selectNode,
                              onNodeContextMenu: _onNodeContextMenu,
                              onOpenSubpatch: (box) =>
                                  _openSubpatch(editor, box),
                              // The panel switches the moment the inline box's
                              // typed name settles on a type, so the arguments
                              // are documented while they are being typed
                              // (issue #437).
                              onTypeResolved: _select,
                              focusNode: _canvasFocus,
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
  Widget _reference(PatcherController? openEditor) {
    final id = _selectedNodeId;
    final type = _selected?.type;
    // "Open tutorial" under the heading whenever the documented type has one
    // (issue #489) — palette tap and canvas selection alike.
    final onOpenTutorial = type != null && _library.hasTutorial(type)
        ? () => unawaited(_openTutorial(type))
        : null;
    // A node tapped in a definition's window is read through that patch's
    // editor (issue #553), for as long as it is still there.
    final selectedIn = _selectedEditor;
    final editor = selectedIn != null && _library.isLive(selectedIn)
        ? selectedIn
        : openEditor;
    if (editor == null || id == null) {
      return PatchReferencePanel(
        descriptor: _selected,
        onOpenTutorial: onOpenTutorial,
      );
    }
    return ListenableBuilder(
      listenable: editor.graph,
      builder: (context, _) {
        final node = editor.graph.nodeById(id);
        final documented = node != null && node.type == _selected?.type;
        final isBox = documented && editor.isSubpatch(id);
        final definition = isBox ? editor.abstractionOf(id) : null;
        // Nothing in a read-only tutorial is edited from the panel either, nor
        // anything an instance got from its definition (issue #553).
        final editable =
            documented && !_readOnly && !_withinInstance(editor, node);
        return PatchReferencePanel(
          descriptor: _selected,
          onOpenTutorial: onOpenTutorial,
          args: documented ? editor.argsOf(id) : null,
          // A selected note's colour (issue #511), journaled by the editor so
          // Ctrl+Z puts it back; the graph wakes this builder on every change.
          noteColor: editable ? editor.noteColorOf(id) : null,
          onNoteColor: editable
              ? (name) {
                  editor.setNoteColor(id, name);
                  _canvasFocus.requestFocus();
                }
              : null,
          // A selected keyboard's range and velocity (issue #515), journaled
          // the same way; the panel only shows them for a `.kslider`.
          keyboardRange: editable ? editor.keyboardLayoutOf(id) : null,
          keyboardVelocity: editable ? editor.keyboardVelocityOf(id) : null,
          onKeyboardRange: editable
              ? (range) {
                  editor.setKeyboardRange(id, range);
                  _canvasFocus.requestFocus();
                }
              : null,
          onKeyboardVelocity: editable
              ? (velocity) {
                  editor.setKeyboardVelocity(id, velocity);
                  _canvasFocus.requestFocus();
                }
              : null,
          // A selected subpatch's name and pins (issue #481), live: adding a
          // boundary object inside reshapes the box and wakes the graph.
          subpatch: isBox
              ? PatchSubpatchSummary(
                  name: editor.subpatchNameOf(id),
                  inlets: node.inputs.length,
                  outlets: node.outputs.length,
                  definition: definition?.format(),
                  definitionFollowed:
                      definition != null &&
                      _library.canFollow(editor, definition),
                )
              : null,
          onOpenSubpatch: isBox
              ? () => definition == null
                    ? _openSubpatch(editor, node)
                    : _openDefinition(editor, node)
              : null,
          onMakeAbstraction:
              isBox &&
                  definition == null &&
                  !_readOnly &&
                  _library.addressOf(editor) != null
              ? () => _library.makeAbstraction(editor, id)
              : null,
          onDetach: definition != null && !_readOnly
              ? () => editor.detachInstance(id)
              : null,
        );
      },
    );
  }

  /// Whether [node] came from a definition. An instance box itself did not:
  /// its name and its place are the parent's.
  bool _withinInstance(PatcherController editor, PatchNode node) {
    final container = node.container;
    return container != null && editor.isWithinInstance(container);
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
