import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../engine/state/patcher_controller.dart';

/// Drives the patcher's engine → canvas refresh: while the surface is on
/// screen, asks [PatcherController.refreshGuiValues] for the live display
/// values often enough that a value arriving over a *cable* shows up within a
/// frame or two (issue #357).
///
/// Wraps the canvas rather than living inside it, because what it does is not a
/// canvas concern and because it must be able to cost **nothing**. This is a
/// live-performance instrument: an open patcher on a background tab, a patch
/// with no live GUI bodies in it, a session where nobody has opened the patcher
/// at all — none of those may schedule so much as a timer tick. Three gates
/// enforce that:
///
/// - **Not on screen** — [active] is the pane's foreground-tab signal, the same
///   one the shell already uses to park the Scene renderer. The shell keeps
///   background tabs mounted so their state survives a switch, so a widget
///   cannot tell on its own that it is invisible; it has to be told.
/// - **No patch open** — the surface only builds this around a live editor, so
///   an empty `patch.` namespace never reaches it.
/// - **Nothing to poll** — [PatcherController.hasGuiValueNodes] is re-checked
///   on every graph change, so the timer starts when the first pollable node is
///   dropped and stops when the last one is deleted.
///
/// Polling is the honest v1: yse reports a display value on demand and offers no
/// change notification. It is deliberately confined to this one widget and one
/// controller method, so a per-object dirty flag from `dart-yse` would replace
/// it without touching the bodies.
class PatchGuiPoller extends StatefulWidget {
  const PatchGuiPoller({
    required this.controller,
    required this.active,
    required this.child,
    super.key,
  });

  /// The editor whose open patch is polled.
  final PatcherController controller;

  /// Whether the patcher is the visible tab of its pane. False parks the poll
  /// entirely — no timer, no gateway reads, no repaints.
  final bool active;

  final Widget child;

  /// Poll period — 30 Hz, fast enough that a cable-driven value looks immediate
  /// and slow enough to disappear beside the frame budget it rides on.
  static const Duration period = Duration(milliseconds: 33);

  @override
  State<PatchGuiPoller> createState() => _PatchGuiPollerState();
}

class _PatchGuiPollerState extends State<PatchGuiPoller> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.controller.graph.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(PatchGuiPoller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.graph.removeListener(_sync);
      widget.controller.graph.addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    widget.controller.graph.removeListener(_sync);
    _timer?.cancel();
    super.dispose();
  }

  /// Run the poll exactly while there is something to poll for someone to see,
  /// and idle it otherwise. Cheap enough to call from the graph listener on
  /// every node added or removed.
  void _sync() {
    final needed = widget.active && widget.controller.hasGuiValueNodes;
    if (needed && _timer == null) {
      _timer = Timer.periodic(PatchGuiPoller.period, _tick);
    } else if (!needed && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void _tick(Timer _) => widget.controller.refreshGuiValues();

  @override
  Widget build(BuildContext context) => widget.child;
}
