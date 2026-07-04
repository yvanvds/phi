import 'package:flutter/material.dart';

import '../design/tokens/phi_colors.dart';
import '../domain/midi/clip_editor.dart';
import '../domain/midi/custom_transform_registry.dart';
import '../domain/midi/midi_clip_seed.dart';
import '../domain/midi/midi_transform_chain.dart';
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
import 'right_inspector/right_inspector.dart';
import 'top_toolbar/top_toolbar.dart';

/// Phi workstation chrome — composes the four fixed regions (top toolbar,
/// left rail, right inspector, bottom status) around the active surface in
/// the centre.
class Workstation extends StatefulWidget {
  const Workstation({
    required this.engine,
    required this.session,
    this.midiFileIo,
    this.codeEvaluator,
    this.customTransformRegistry,
    super.key,
  });

  final PhiEngine engine;
  final SessionState session;

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

    // The app boots on Mix, so the Scene surface starts offstage — tell the
    // renderer to keep its ticker paused until Scene is first selected.
    _syncSceneVisibility();

    // Transport play/stop drives the MIDI player at the session tempo; tempo
    // changes mid-play take effect on the next tick.
    widget.session.transport.addListener(_onTransport);
    widget.session.tempo.addListener(_onTempo);
  }

  @override
  void dispose() {
    widget.session.transport.removeListener(_onTransport);
    widget.session.tempo.removeListener(_onTempo);
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
  }

  /// Pause macbear's render ticker whenever Scene is offstage; resume it when
  /// Scene is the selected surface. Keeps the shell renderer-agnostic — the
  /// macbear specifics stay inside `MacbearSceneRenderer`.
  void _syncSceneVisibility() {
    widget.engine.sceneRenderer?.setVisible(_selected == SurfaceId.scene);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PhiColors.bg0,
      child: Column(
        children: [
          TopToolbar(session: widget.session),
          Expanded(
            child: Row(
              children: [
                LeftRail(selected: _selected, onSelect: _onSelect),
                Expanded(child: _buildCentre()),
                RightInspector(engine: widget.engine, session: widget.session),
              ],
            ),
          ),
          BottomStatus(engine: widget.engine, session: widget.session),
        ],
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
