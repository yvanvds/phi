import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../design/tokens/phi_colors.dart';
import '../domain/midi/clip_editor.dart';
import '../domain/midi/custom_transform_registry.dart';
import '../domain/midi/midi_clip_seed.dart';
import '../domain/midi/midi_transform_chain.dart';
import '../domain/midi/store/midi_transform_codec.dart';
import '../domain/project/lifecycle/project_controller.dart';
import '../domain/project/lifecycle/project_directory_picker.dart';
import '../domain/project/undo_scopes.dart';
import '../domain/session/session_state.dart';
import '../domain/shell_layout/layout_node.dart';
import '../engine/bridge/code_evaluator.dart';
import '../engine/bridge/dx7_fm_bank_reader.dart';
import '../engine/bridge/no_op_code_evaluator.dart';
import '../engine/engine.dart';
import '../engine/state/clip_library_controller.dart';
import '../engine/state/rack_definitions_controller.dart';
import '../engine/state/voice_audition_controller.dart';
import '../surfaces/code/code_surface.dart';
import '../surfaces/midi/midi_file_io.dart';
import '../surfaces/midi/midi_surface.dart';
import '../surfaces/mix/mix_surface.dart';
import '../surfaces/patcher/patcher_surface.dart';
import '../surfaces/racks/file_selector_rack_asset_source.dart';
import '../surfaces/racks/racks_surface.dart';
import '../surfaces/scene/scene_surface.dart';
import '../surfaces/state/state_surface.dart';
import 'bottom_status/bottom_status.dart';
import 'layout/shell_layout_controller.dart';
import 'layout/split_tree_view.dart';
import 'layout/splitter_resize.dart';
import 'layout/workstation_pane.dart';
import 'left_rail/left_rail.dart';
import 'left_rail/surface_id.dart';
import 'project/close_confirm_dialog.dart';
import 'project/close_decision.dart';
import 'project/close_guard.dart';
import 'project/project_actions.dart';
import 'right_inspector/right_inspector.dart';
import 'settings/settings_dialog.dart';
import 'top_toolbar/top_toolbar.dart';

/// Phi workstation chrome — composes the four fixed regions (top toolbar,
/// left rail, right inspector, bottom status) around the active surface in
/// the centre.
class Workstation extends StatefulWidget {
  const Workstation({
    required this.engine,
    required this.session,
    this.projectController,
    this.directoryPicker,
    this.autoStartProject = false,
    this.midiFileIo,
    this.codeEvaluator,
    this.customTransformRegistry,
    this.layoutController,
    super.key,
  });

  final PhiEngine engine;
  final SessionState session;

  /// The workspace layout controller — the split tree + tab stacks the centre
  /// renders (design `docs/design/shell-layout.md` §2). `null` lets the shell
  /// build its own seeded controller (one pane, Mix open); tests inject one to
  /// drive dock moves and assert state survives a re-parent.
  final ShellLayoutController? layoutController;

  /// The project lifecycle controller. When present (with [directoryPicker]),
  /// the toolbar shows the project menu + dirty indicator, Ctrl+S saves, and the
  /// app confirms-on-close while dirty. `null` in the bare Phase-1 tests that
  /// don't exercise the project stack.
  final ProjectController? projectController;

  /// The folder picker backing the project menu's Open/Save-location dialogs.
  final ProjectDirectoryPicker? directoryPicker;

  /// Whether to restore the last project (and offer recovery) on first frame.
  /// The production entry point sets this; tests opt in with a controller wired
  /// to fakes so launch recovery is driven deterministically.
  final bool autoStartProject;

  /// File-dialog backend for the MIDI surface's SMF import/export. `null` in
  /// production (the surface falls back to the real `file_selector` backend);
  /// tests inject a fake to drive the flow without native dialogs.
  final MidiFileIo? midiFileIo;

  /// Runs Code-surface blocks. `null` in production today (the shell builds a
  /// [NoOpCodeEvaluator]); tests inject a `FakeCodeEvaluator` to drive the
  /// live-coding → custom-transform handshake (issue #38). When the shell owns
  /// the evaluator it also disposes it.
  final CodeEvaluator? codeEvaluator;

  /// Catalogue of performer-authored MIDI transforms shared by the Code and
  /// MIDI surfaces (issue #38). `null` lets the shell build its own; tests
  /// inject one so a fake evaluator can register into the same instance the
  /// MIDI `+` menu reads.
  final CustomTransformRegistry? customTransformRegistry;

  @override
  State<Workstation> createState() => _WorkstationState();
}

class _WorkstationState extends State<Workstation> {
  /// Owns the split tree + tab stacks the centre renders; the rail summons
  /// surfaces into it and the Scene visibility + undo focus follow its focused
  /// surface. Built here (seed: one pane, Mix open) unless a test injected one.
  late final ShellLayoutController _layout;
  late final bool _ownsLayout;

  /// One stable key per surface, so a surface keeps its element (and all its
  /// state) when it re-parents from one pane to another — single-instance
  /// content moves, it never rebuilds (design §2). Scene is the exception: it
  /// mounts only while it is the visible tab, so its slot is keyless when
  /// offstage.
  final Map<SurfaceId, GlobalKey> _surfaceKeys = {
    for (final id in SurfaceId.values) id: GlobalKey(debugLabel: id.name),
  };

  /// Tracks the last Scene-visibility signal so the renderer is only told when
  /// it actually flips (a layout change that leaves Scene where it was is
  /// silent).
  bool? _sceneVisible;

  /// True while a manifest-restored layout is being pushed into [_layout], so
  /// the resulting change notification is not echoed straight back to the
  /// project controller as a fresh edit (which would dirty a just-opened
  /// project). Editing flows the other way — [_layout] → controller.
  bool _restoringLayout = false;

  /// Every surface id the app knows — the universe fit-fallback keeps a restored
  /// layout within (a tab naming a surface not in here is dropped, design §3).
  static final Set<String> _knownSurfaceIds = {
    for (final id in SurfaceId.values) id.name,
  };

  late final CodeEvaluator _codeEvaluator;
  late final bool _ownsCodeEvaluator;
  late final CustomTransformRegistry _customTransforms;
  late final bool _ownsCustomTransforms;

  // The MIDI chain + editor are owned by the engine's player when one is
  // wired (production, and tests that exercise playback), so playback and the
  // piano-roll editor share one source clip. When the engine has no MIDI
  // gateway (widget tests without playback) the shell owns a fallback pair so
  // the surface still renders. Either way the state lives above the surface
  // widget, so undo history + chip toggles survive rail switches — the
  // IndexedStack keeps the surface mounted but its widget is rebuilt.
  late final MidiTransformChain _midiChain;
  late final ClipEditor _midiEditor;
  late final bool _ownsMidiState;

  /// Per-surface undo stacks with a focused one — *undo follows focus* (#119).
  /// The shell routes Ctrl+Z/Y here (see [build]) and points the focus at the
  /// active surface's scope in [_onSelect], so an undo never yanks an edit from
  /// a surface you're not looking at. The MIDI editor is the first (and, today,
  /// only) registered scope.
  final UndoScopes _undoScopes = UndoScopes();

  /// The project-menu action orchestrator, present only when a project
  /// controller + picker were wired. Shared by the menu and the Ctrl+S shortcut.
  ProjectActions? _actions;

  /// Drives the MIDI surface's library panel (issue #188) — the `clip.` tree,
  /// selection, context menu, drag, and per-row play state. Built only when the
  /// engine has a MIDI subsystem and a project controller supplies the registry;
  /// rebound alongside the engine whenever New / Open swaps the registry.
  ClipLibraryController? _libraryController;

  /// Drives the Racks surface's definitions panel (issue #209) — the `synth.` /
  /// `fx.` trees, selection routing to the editor pane, and the voices scaffold.
  /// Built only when a project controller supplies the registry (no engine
  /// dependency); rebound alongside the engine whenever New / Open swaps it.
  RackDefinitionsController? _rackDefinitions;

  /// Drives arm-for-input + audition in the racks voices pane (issue #211) —
  /// the single armed voice, the MIDI-in subscription, and the test strip. Built
  /// only when the engine has a MIDI subsystem; disposed with the shell.
  VoiceAuditionController? _voiceAudition;

  /// Imports FM banks / SFZ instruments / samples into the open project's
  /// `assets/` folder for the Racks editors (issue #210), resolving the live
  /// project location on each pick. Constructing it touches no plugins.
  late final FileSelectorRackAssetSource _rackAssetSource =
      FileSelectorRackAssetSource(
        directoryProvider: () => widget.projectController?.location.value,
      );

  /// Browses an FM bank's patch names for the Racks FM editor (issue #210),
  /// resolving a definition's project-relative `.syx` ref against the open
  /// project's folder. No yse is touched until a bank is actually read.
  late final Dx7FmBankReader _fmBankReader = Dx7FmBankReader(
    resolveAsset: (ref) {
      final location = widget.projectController?.location.value;
      return location == null ? ref : p.join(location, ref);
    },
  );

  /// Listens for OS exit requests so a dirty project can confirm-on-close
  /// (design §9). Present only when the project stack is wired.
  AppLifecycleListener? _exitListener;

  @override
  void initState() {
    super.initState();

    _ownsCodeEvaluator = widget.codeEvaluator == null;
    _codeEvaluator = widget.codeEvaluator ?? NoOpCodeEvaluator();
    _ownsCustomTransforms = widget.customTransformRegistry == null;
    _customTransforms =
        widget.customTransformRegistry ?? CustomTransformRegistry();

    _ownsLayout = widget.layoutController == null;
    _layout = widget.layoutController ?? ShellLayoutController();
    _layout.addListener(_onLayoutChanged);

    final midi = widget.engine.midiOrNull;
    _ownsMidiState = midi == null;
    _midiChain = midi?.chain ?? defaultDemoChain();
    _midiEditor = midi?.editor ?? ClipEditor(_midiChain.source);

    _undoScopes.register(_midiEditor.undoScope);
    _undoScopes.focus(_scopeIdFor(_layout.focusedSurface));

    // The app boots on Mix, so the Scene surface starts offstage — tell the
    // renderer to keep its ticker paused until Scene is first summoned.
    _syncSceneVisibility();

    // Transport play/stop drives the MIDI player at the session tempo; tempo
    // changes mid-play take effect on the next tick.
    widget.session.transport.addListener(_onTransport);
    widget.session.tempo.addListener(_onTempo);

    // Master volume/mute are session-owned manifest state (design
    // `docs/design/mix.md` §3); mirror them onto the engine so a fader move — or
    // a project open that loads them from the manifest — reaches the audio path.
    widget.session.masterVolume.addListener(_onMasterVolume);
    widget.session.masterMuted.addListener(_onMasterMuted);
    _onMasterVolume();
    _onMasterMuted();

    _setUpProject();
  }

  /// Wires the engine's registry-backed channel sync, the project menu, the
  /// confirm-on-close guard, and (when asked) the launch-time restore + recovery
  /// flow. No-op unless a project controller was injected.
  void _setUpProject() {
    final controller = widget.projectController;
    if (controller == null) return;
    // Build the clip-library controller over the engine's MIDI session manager
    // and the project's registry — the seam the library panel drives (issue
    // #188). Present only with a MIDI subsystem; rebound below on registry swaps.
    final midi = widget.engine.midiOrNull;
    if (midi != null) {
      _libraryController = ClipLibraryController(
        registry: controller.registry,
        sessions: midi,
        recordCommand: controller.recordCommand,
        transformCodec: MidiTransformCodec(customRegistry: _customTransforms),
      );
    }
    // The Racks definitions panel reads the same registry — no MIDI dependency,
    // so build it whenever a project supplies the registry (issue #209).
    _rackDefinitions = RackDefinitionsController(
      registry: controller.registry,
      recordCommand: controller.recordCommand,
    );
    // Arm-for-input + audition need the MIDI subsystem (the parsed input stream
    // and the voice → synth audition path); build the seam only when it exists
    // (issue #211). The voices pane degrades to editing-only without it.
    if (midi != null) {
      _voiceAudition = VoiceAuditionController(midi: midi);
    }
    // The engine consumes the registry as its channel source of truth (design
    // §8): bind it to the controller's registry now, and rebind whenever New /
    // Open swaps the registry instance (the controller notifies on that).
    _bindEngineRegistry();
    controller.addListener(_bindEngineRegistry);
    // The manifest owns the persisted layout (issue #253); adopt it into the
    // live layout controller whenever a New / Open restores one (design §3).
    controller.layoutRestored.addListener(_onLayoutRestored);

    final picker = widget.directoryPicker;
    if (picker != null) {
      _actions = ProjectActions(controller: controller, picker: picker);
      _exitListener = AppLifecycleListener(onExitRequested: _onExitRequested);
    }
    if (widget.autoStartProject) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_startProject()),
      );
    }
  }

  /// Points the engine at the controller's current registry. `bindProject`
  /// early-returns when it is already the bound one, so this is cheap to call on
  /// every controller notification.
  void _bindEngineRegistry() {
    final controller = widget.projectController;
    if (controller == null) return;
    widget.engine.bindProject(
      controller.registry,
      recordCommand: controller.recordCommand,
      customTransforms: _customTransforms,
    );
    // The library panel reads the same registry — rebind it too so a New / Open
    // that swaps the registry re-points the clip tree.
    _libraryController?.rebind(
      registry: controller.registry,
      recordCommand: controller.recordCommand,
    );
    _rackDefinitions?.rebind(
      registry: controller.registry,
      recordCommand: controller.recordCommand,
    );
  }

  /// Loads settings and restores the most-recent project (offering recovery if
  /// its journal is dirty), or starts a fresh project when there are no recents.
  Future<void> _startProject() async {
    final controller = widget.projectController;
    final actions = _actions;
    if (controller == null || actions == null) return;
    await controller.loadSettings();
    if (!mounted) return;
    // Boot audio from the just-loaded settings (design §5): the engine came up
    // on the platform default in `start()`; move it to the stored device now,
    // reverting to the default (with a notice) if it is missing or refuses to
    // open. A no-op when no device was chosen.
    widget.engine.switchAudioDevice(controller.audioSettings);
    // Apply the stored MIDI choice too (design §5): set the output port by name
    // and open the enabled input ports. A no-op when nothing was chosen.
    widget.engine.applyMidiSettings(controller.midiSettings);
    final recents = controller.recentProjects.value;
    if (recents.isEmpty) {
      controller.newProject();
    } else {
      await actions.openRecent(context, recents.first);
    }
  }

  /// Vetoes an OS close while the project is dirty, offering to save/discard/
  /// keep working (design §9). Delegates the decision to a widget-free
  /// [CloseGuard] so the mapping is unit-testable.
  Future<AppExitResponse> _onExitRequested() async {
    final controller = widget.projectController;
    final actions = _actions;
    if (controller == null || actions == null) return AppExitResponse.exit;
    final guard = CloseGuard(
      isDirty: () => controller.isDirty.value,
      confirm: () async {
        if (!mounted) return CloseDecision.discard;
        return CloseConfirmDialog.show(context);
      },
      save: () => actions.save(context),
    );
    return guard.onExitRequested();
  }

  void _onSaveShortcut() {
    final actions = _actions;
    if (actions != null) unawaited(actions.save(context));
  }

  /// Opens the settings dialog (design `settings-and-devices.md` §6) over the
  /// engine and the project's single settings owner. Wired only when a project
  /// controller is present — the settings owner lives on it.
  void _openSettings() {
    final controller = widget.projectController;
    if (controller == null) return;
    unawaited(
      SettingsDialog.show(
        context,
        engine: widget.engine,
        settings: controller.settingsController,
      ),
    );
  }

  @override
  void dispose() {
    _layout.removeListener(_onLayoutChanged);
    if (_ownsLayout) _layout.dispose();
    widget.projectController?.removeListener(_bindEngineRegistry);
    widget.projectController?.layoutRestored.removeListener(_onLayoutRestored);
    _libraryController?.dispose();
    _rackDefinitions?.dispose();
    _voiceAudition?.dispose();
    _exitListener?.dispose();
    widget.session.transport.removeListener(_onTransport);
    widget.session.tempo.removeListener(_onTempo);
    widget.session.masterVolume.removeListener(_onMasterVolume);
    widget.session.masterMuted.removeListener(_onMasterMuted);
    // The router only references scopes; it never owns them, so disposing it
    // won't touch the MIDI editor's scope (disposed with the editor below).
    _undoScopes.dispose();
    // Only dispose what the shell owns; injected doubles are the test's to own.
    if (_ownsCodeEvaluator) _codeEvaluator.dispose();
    if (_ownsCustomTransforms) _customTransforms.dispose();
    // Only dispose the MIDI state the shell owns; the engine disposes its own.
    if (_ownsMidiState) {
      _midiEditor.dispose();
      _midiChain.dispose();
    }
    super.dispose();
  }

  void _onTransport() {
    final midi = widget.engine.midiOrNull;
    if (midi == null) return;
    if (widget.session.isPlaying) {
      midi.bpm = widget.session.tempo.value;
      midi.play();
    } else {
      midi.stop();
    }
  }

  void _onTempo() => widget.engine.midiOrNull?.bpm = widget.session.tempo.value;

  void _onMasterVolume() =>
      widget.engine.setMasterVolume(widget.session.masterVolume.value);

  void _onMasterMuted() =>
      widget.engine.setMasterMuted(muted: widget.session.masterMuted.value);

  /// A rail tap summons the surface (design §2, §3): focus it wherever it is
  /// docked, or open it in the active pane if closed.
  void _onSelect(SurfaceId id) => _layout.summon(id.name);

  /// Reacts to a layout change (a summon, a dock move): repaint the centre + rail
  /// and follow the focused surface with the Scene ticker and the undo focus.
  void _onLayoutChanged() {
    setState(() {});
    _syncSceneVisibility();
    // Undo follows focus: point Ctrl+Z/Y at the focused surface's stack.
    _undoScopes.focus(_scopeIdFor(_layout.focusedSurface));
    // Persist the new arrangement into the manifest — journal-free (issue #253).
    // Suppressed while adopting a restored layout, so an open never self-dirties.
    if (!_restoringLayout) {
      widget.projectController?.updateLayout(_layout.layout);
    }
  }

  /// Adopts the project's manifest-restored layout into the live [_layout]
  /// controller on a New / Open (design §3). Fit-fallback clamps splitter
  /// fractions and drops any tab whose surface the app no longer knows, so a set
  /// arranged on a wider screen still opens usable here. Guarded so the resulting
  /// notification is not pushed back to the controller as an edit.
  void _onLayoutRestored() {
    final controller = widget.projectController;
    if (controller == null) return;
    _restoringLayout = true;
    try {
      _layout.replaceLayout(controller.layout.fit(_knownSurfaceIds));
    } finally {
      _restoringLayout = false;
    }
  }

  /// The undo-scope id owned by the surface with layout id [surfaceId], or `null`
  /// for surfaces (or an empty focus) with no undo stack yet. Only the MIDI
  /// surface has one today.
  String? _scopeIdFor(String? surfaceId) =>
      surfaceId == SurfaceId.midi.name ? _midiEditor.undoScope.id : null;

  /// The focused surface as a [SurfaceId], or null when the active pane is empty
  /// — what the rail highlights.
  SurfaceId? get _focusedSurfaceId {
    final focused = _layout.focusedSurface;
    return focused == null ? null : _surfaceIdOf(focused);
  }

  /// Whether the Scene surface is the visible (active) tab of whatever pane holds
  /// it — Scene is single-instance, so it is active in at most one pane.
  bool get _sceneOnstage =>
      _layout.layout.panes.any((p) => p.active == SurfaceId.scene.name);

  /// Pause macbear's render ticker whenever Scene is offstage; resume it when
  /// Scene is the visible surface. Only signals the renderer on an actual flip,
  /// so a layout change elsewhere stays silent. Keeps the shell
  /// renderer-agnostic — the macbear specifics stay inside `MacbearSceneRenderer`.
  void _syncSceneVisibility() {
    final visible = _sceneOnstage;
    if (visible == _sceneVisible) return;
    _sceneVisible = visible;
    widget.engine.sceneRenderer?.setVisible(visible);
  }

  @override
  Widget build(BuildContext context) {
    // Ctrl+Z/Y route to the focused surface's undo stack (#119). These bindings
    // sit above every surface, so a key a focused widget (a piano roll, a text
    // field) leaves unhandled bubbles up to here; a text field's own undo still
    // wins because it consumes the combo first.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _undoScopes.undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _undoScopes.redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _undoScopes.redo,
        // Ctrl+S saves the project (choosing a location first if it is new).
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _onSaveShortcut,
        // Ctrl+Tab cycles the focused pane's tabs; Shift reverses (design §2).
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            _layout.cycleTabInActivePane(),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () =>
            _layout.cycleTabInActivePane(forward: false),
      },
      child: Material(
        color: PhiColors.bg0,
        child: Column(
          children: [
            TopToolbar(
              session: widget.session,
              projectController: widget.projectController,
              directoryPicker: widget.directoryPicker,
              onOpenSettings: widget.projectController != null
                  ? _openSettings
                  : null,
            ),
            Expanded(
              child: Row(
                children: [
                  LeftRail(selected: _focusedSurfaceId, onSelect: _onSelect),
                  Expanded(child: _buildCentre()),
                  RightInspector(session: widget.session),
                ],
              ),
            ),
            BottomStatus(engine: widget.engine, session: widget.session),
          ],
        ),
      ),
    );
  }

  /// The centre region: the split tree of panes (design §2). In the
  /// behaviour-neutral default it is one pane whose tab stack the rail summons
  /// into — so the app looks identical to the pre-refactor single surface until
  /// the performer splits. Splitter drags route through [_onResizeSplit].
  Widget _buildCentre() => SplitTreeView(
    root: _layout.layout.root,
    buildPane: _buildPane,
    onResize: _onResizeSplit,
  );

  /// Renders one pane fully dressed ([WorkstationPane]): its tab strip, resident
  /// surface content ([_surfaceContent]), the drag-to-dock zones, and — when it
  /// is the focused pane — the focus ring.
  Widget _buildPane(LayoutPane pane) => WorkstationPane(
    pane: pane,
    isActivePane: pane.id == _layout.activePaneId,
    controller: _layout,
    contentFor: _surfaceContent,
    labelFor: _labelFor,
  );

  /// The tab label for a surface id — its [SurfaceId.label], or the raw id when
  /// it names no known surface (fit-fallback would drop such a tab first).
  String _labelFor(String surfaceId) =>
      _surfaceIdOf(surfaceId)?.label ?? surfaceId;

  /// Applies a splitter drag: re-derives the flanking fractions of [splitId]
  /// from the *current* layout (so incremental drag deltas accumulate correctly)
  /// and commits them, clamped to the minima.
  void _onResizeSplit(String splitId, int leadingIndex, double deltaFraction) {
    final node = _layout.layout.nodeById(splitId);
    if (node is! LayoutSplit) return;
    _layout.resize(
      splitId,
      resizeSiblings(
        fractions: node.fractions,
        leadingIndex: leadingIndex,
        deltaFraction: deltaFraction,
      ),
    );
  }

  /// The resident content for the surface with layout id [surfaceId]. Every
  /// surface is wrapped in its stable [GlobalKey] so moving it between panes
  /// re-parents the element (its state survives) instead of rebuilding.
  ///
  /// Scene is the exception: its `M3View` drives a process-wide GL context, so
  /// it mounts only while it is its pane's [active] (visible) tab — keeping ANGLE
  /// init off the boot path when the app opens elsewhere and letting the GPU
  /// context idle when Scene is a background tab or closed. Re-parenting an
  /// *active* Scene between panes is the one interaction verified by hand (the
  /// GL path is not CI-testable); the fork's `M3AppEngine` keeps the engine warm.
  Widget _surfaceContent(String surfaceId, {required bool active}) {
    final id = _surfaceIdOf(surfaceId);
    if (id == null) return const SizedBox.shrink();
    if (id == SurfaceId.scene && !active) return const SizedBox.shrink();
    return KeyedSubtree(key: _surfaceKeys[id], child: _surfaceFor(id));
  }

  /// The [SurfaceId] whose [SurfaceId.name] is [surfaceId], or null when the id
  /// names no known surface (fit-fallback drops such tabs, so this is defensive).
  SurfaceId? _surfaceIdOf(String surfaceId) {
    for (final id in SurfaceId.values) {
      if (id.name == surfaceId) return id;
    }
    return null;
  }

  Widget _surfaceFor(SurfaceId id) {
    switch (id) {
      case SurfaceId.scene:
        return SceneSurface(engine: widget.engine);
      case SurfaceId.mix:
        return MixSurface(engine: widget.engine);
      case SurfaceId.racks:
        return RacksSurface(
          controller: _rackDefinitions,
          audition: _voiceAudition,
          assetSource: _rackAssetSource,
          bankReader: _fmBankReader,
        );
      case SurfaceId.patcher:
        return PatcherSurface(engine: widget.engine);
      case SurfaceId.code:
        return CodeSurface(
          engine: widget.engine,
          session: widget.session,
          evaluator: _codeEvaluator,
        );
      case SurfaceId.midi:
        return MidiSurface(
          engine: widget.engine,
          chain: _midiChain,
          editor: _midiEditor,
          registry: _customTransforms,
          playhead: widget.engine.midiOrNull?.playhead,
          fileIo: widget.midiFileIo,
          libraryController: _libraryController,
        );
      case SurfaceId.state:
        return StateSurface(engine: widget.engine, session: widget.session);
    }
  }
}
