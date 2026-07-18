import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens/phi_colors.dart';
import '../domain/midi/clip_editor.dart';
import '../domain/midi/custom_transform_registry.dart';
import '../domain/midi/midi_clip_seed.dart';
import '../domain/midi/midi_transform_chain.dart';
import '../domain/project/lifecycle/project_controller.dart';
import '../domain/project/lifecycle/project_directory_picker.dart';
import '../domain/project/undo_scopes.dart';
import '../domain/session/session_state.dart';
import '../engine/bridge/code_evaluator.dart';
import '../engine/bridge/no_op_code_evaluator.dart';
import '../engine/engine.dart';
import '../surfaces/code/code_surface.dart';
import '../surfaces/midi/midi_file_io.dart';
import '../surfaces/midi/midi_surface.dart';
import '../surfaces/mix/mix_surface.dart';
import '../surfaces/patcher/patcher_surface.dart';
import '../surfaces/scene/scene_surface.dart';
import '../surfaces/state/state_surface.dart';
import 'bottom_status/bottom_status.dart';
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
    super.key,
  });

  final PhiEngine engine;
  final SessionState session;

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
  SurfaceId _selected = SurfaceId.mix;
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

    final midi = widget.engine.midiOrNull;
    _ownsMidiState = midi == null;
    _midiChain = midi?.chain ?? defaultDemoChain();
    _midiEditor = midi?.editor ?? ClipEditor(_midiChain.source);

    _undoScopes.register(_midiEditor.undoScope);
    _undoScopes.focus(_scopeIdFor(_selected));

    // The app boots on Mix, so the Scene surface starts offstage — tell the
    // renderer to keep its ticker paused until Scene is first selected.
    _syncSceneVisibility();

    // Transport play/stop drives the MIDI player at the session tempo; tempo
    // changes mid-play take effect on the next tick.
    widget.session.transport.addListener(_onTransport);
    widget.session.tempo.addListener(_onTempo);

    _setUpProject();
  }

  /// Wires the engine's registry-backed channel sync, the project menu, the
  /// confirm-on-close guard, and (when asked) the launch-time restore + recovery
  /// flow. No-op unless a project controller was injected.
  void _setUpProject() {
    final controller = widget.projectController;
    if (controller == null) return;
    // The engine consumes the registry as its channel source of truth (design
    // §8): bind it to the controller's registry now, and rebind whenever New /
    // Open swaps the registry instance (the controller notifies on that).
    _bindEngineRegistry();
    controller.addListener(_bindEngineRegistry);

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
    widget.projectController?.removeListener(_bindEngineRegistry);
    _exitListener?.dispose();
    widget.session.transport.removeListener(_onTransport);
    widget.session.tempo.removeListener(_onTempo);
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

  void _onSelect(SurfaceId id) {
    setState(() => _selected = id);
    _syncSceneVisibility();
    // Undo follows focus: point Ctrl+Z/Y at the newly active surface's stack.
    _undoScopes.focus(_scopeIdFor(id));
  }

  /// The undo-scope id owned by surface [id], or `null` for surfaces that have
  /// no undo stack yet. Only the MIDI surface has one today.
  String? _scopeIdFor(SurfaceId id) =>
      id == SurfaceId.midi ? _midiEditor.undoScope.id : null;

  /// Pause macbear's render ticker whenever Scene is offstage; resume it when
  /// Scene is the selected surface. Keeps the shell renderer-agnostic — the
  /// macbear specifics stay inside `MacbearSceneRenderer`.
  void _syncSceneVisibility() {
    widget.engine.sceneRenderer?.setVisible(_selected == SurfaceId.scene);
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
                  LeftRail(selected: _selected, onSelect: _onSelect),
                  Expanded(child: _buildCentre()),
                  RightInspector(
                    engine: widget.engine,
                    session: widget.session,
                  ),
                ],
              ),
            ),
            BottomStatus(engine: widget.engine, session: widget.session),
          ],
        ),
      ),
    );
  }

  Widget _buildCentre() {
    // Every surface except Scene stays resident: IndexedStack keeps each in the
    // element tree so its transient UI state (scroll, selection, in-progress
    // edits) survives rail switches while only the selected one paints.
    //
    // Scene is the exception. It hosts macbear's `M3View`, which drives a
    // process-wide GL context, so we mount it only while Scene is selected —
    // keeping ANGLE init off the boot path when the app opens elsewhere and
    // letting the GPU context idle when Scene is offstage. The fork's
    // `M3AppEngine.unmount()`/`remount()` (issue #19) keeps the engine warm, so
    // leaving and re-entering Scene is cheap and crash-free.
    return IndexedStack(
      index: SurfaceId.values.indexOf(_selected),
      sizing: StackFit.expand,
      children: [for (final id in SurfaceId.values) _surfaceSlot(id)],
    );
  }

  /// The child for [id]'s IndexedStack slot. Every surface is built eagerly
  /// except Scene, whose `M3View` is kept out of the tree until Scene is
  /// selected (see [_buildCentre]); its slot is an empty box while offstage.
  Widget _surfaceSlot(SurfaceId id) {
    if (id == SurfaceId.scene && _selected != SurfaceId.scene) {
      return const SizedBox.shrink();
    }
    return _surfaceFor(id);
  }

  Widget _surfaceFor(SurfaceId id) {
    switch (id) {
      case SurfaceId.scene:
        return SceneSurface(engine: widget.engine);
      case SurfaceId.mix:
        return MixSurface(engine: widget.engine);
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
        );
      case SurfaceId.state:
        return StateSurface(engine: widget.engine, session: widget.session);
    }
  }
}
