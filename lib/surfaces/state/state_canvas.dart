import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/dialog/delete_impact_dialog.dart';
import '../../design/widgets/patcher/patch_grid_painter.dart';
import '../../design/widgets/state_machine/state_canvas_constants.dart';
import '../../design/widgets/state_machine/state_transition_geometry.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/registry_entity.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/session/session_state.dart';
import '../../domain/state_machine/state_transition.dart';
import '../../domain/state_machine/store/state_trigger.dart';
import '../../domain/time_domains/time_domain.dart';
import '../../engine/state/state_entity_selection.dart';
import '../../engine/state/state_machine_controller.dart';
import 'state_ghost_transition.dart';
import 'state_node_view.dart';
import 'state_transition_badge.dart';
import 'state_transition_layer.dart';
import 'state_trigger_editor.dart';

/// The state-graph pan/zoom canvas, rendered from the registry through the
/// [StateMachineController] (issue #241). Hosts the grid backdrop (reused
/// from the patcher — same scope-backdrop intent), the transition layer,
/// every state node, and the in-flight ghost transition. Tracks the
/// cursor's canvas-local position so the ghost can follow it.
///
/// Standard affordances ride context menus: a secondary tap on empty
/// canvas offers *new state* at that spot; a secondary tap on a node
/// offers *duplicate* and *delete* (the latter behind the delete-impact
/// dialog when other entities still point at the state).
///
/// Each transition is badged with its trigger kind at the curve midpoint
/// (issue #244). The badge is the tap target: on a **manual** transition it
/// toggles the arm (tap-to-arm moved to the badge, design §5); on any other
/// kind it opens the trigger editor. Tapping the curve itself opens the
/// editor for every kind.
class StateCanvas extends StatefulWidget {
  const StateCanvas({
    required this.controller,
    required this.session,
    this.variables,
    super.key,
  });

  final StateMachineController controller;
  final SessionState session;

  /// The runtime-variable registry the trigger editor's variable picker
  /// offers definitions from (issue #244). `null` — a bare setup — leaves the
  /// picker empty.
  final RuntimeVariableRegistry? variables;

  @override
  State<StateCanvas> createState() => _StateCanvasState();
}

class _StateCanvasState extends State<StateCanvas> {
  Offset _cursor = Offset.zero;

  StateMachineController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Listener(
      onPointerMove: (e) => _updateCursor(e.localPosition),
      onPointerHover: (e) => _updateCursor(e.localPosition),
      onPointerUp: (e) => _onPointerUp(e.localPosition),
      child: InteractiveViewer(
        transformationController: controller.transform,
        constrained: false,
        minScale: 0.25,
        maxScale: 4.0,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: SizedBox(
          width: StateCanvasConstants.canvasSize,
          height: StateCanvasConstants.canvasSize,
          child: ListenableBuilder(
            // Rebuild on controller changes (the registry view, arms, the
            // live state, drags) *and* on selection changes — selection
            // drives the outer ring on whichever node carries it.
            listenable: Listenable.merge([
              controller,
              widget.session.selection,
            ]),
            builder: (context, _) {
              final nodes = controller.states;
              final selection = widget.session.selection.value;
              final selectedAddress =
                  selection is StateEntitySelection &&
                      identical(selection.controller, controller)
                  ? selection.address
                  : null;
              final rects = <EntityAddress, Rect>{
                for (final n in nodes) n.address: rectFor(n),
              };
              final transitions = controller.transitions;
              // Index armed transitions by target node so each node can
              // look up its capsule label in O(1). At most one armed
              // capsule per node — duplicates are unlikely in practice
              // and the first wins.
              final armedByTarget = <EntityAddress, StateTransition>{};
              for (final t in transitions) {
                if (t.armed) {
                  armedByTarget.putIfAbsent(t.target, () => t);
                }
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: PatchGridPainter()),
                    ),
                  ),
                  Positioned.fill(
                    child: StateTransitionLayer(
                      transitions: transitions,
                      nodeRects: rects,
                      version: controller.version,
                      onTransitionTap: _openTriggerEditor,
                    ),
                  ),
                  // Above the transition layer (whose paint hit-tests the
                  // whole canvas) but below the nodes: translucent, and it
                  // claims only secondary taps — primary pointers still
                  // reach the transition layer and the pan/zoom.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onSecondaryTapDown: (d) => _onCanvasContextMenu(
                        d.globalPosition,
                        d.localPosition,
                      ),
                    ),
                  ),
                  // Trigger-kind badges at the curve midpoints (issue #244):
                  // tap-to-arm for manual, the trigger editor otherwise.
                  for (final t in transitions) ?_badgeFor(t, rects),
                  for (final n in nodes)
                    Positioned(
                      left: n.position.dx,
                      top: n.position.dy,
                      width: StateCanvasConstants.nodeWidth,
                      height: StateCanvasConstants.nodeHeight,
                      child: StateNodeView(
                        node: n,
                        controller: controller,
                        onPinDown: _onPinDown,
                        onSelect: () => _select(n.address),
                        onContextMenu: (global) =>
                            _onNodeContextMenu(n.address, global),
                        isLive: controller.activeStateAddress == n.address,
                        armedTransition: armedByTarget[n.address],
                        selected: selectedAddress == n.address,
                      ),
                    ),
                  if (controller.dragSourceState != null)
                    Positioned.fill(
                      child: StateGhostTransition(
                        source:
                            rects[controller.dragSourceState!]?.center ??
                            Offset.zero,
                        cursor: _cursor,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _select(EntityAddress address) {
    widget.session.select(
      StateEntitySelection(controller: _controller, address: address),
    );
  }

  void _updateCursor(Offset local) {
    if (_controller.dragSourceState == null) return;
    setState(() => _cursor = local);
  }

  void _onPinDown(EntityAddress from, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ?? global;
    setState(() => _cursor = local);
    _controller.beginTransitionDrag(from);
  }

  void _onPointerUp(Offset local) {
    final source = _controller.dragSourceState;
    if (source == null) return;
    final hit = _findStateAt(local);
    if (hit != null && hit != source) {
      _controller.connect(source, hit);
    }
    _controller.endTransitionDrag();
  }

  EntityAddress? _findStateAt(Offset local) {
    const pad = StateCanvasConstants.nodeHitPadding;
    for (final n in _controller.states) {
      final r = rectFor(n).inflate(pad);
      if (r.contains(local)) return n.address;
    }
    return null;
  }

  // ─── trigger badges + editor (issue #244) ───────────────────────────────

  /// The trigger-kind badge for [transition], centred on its curve midpoint —
  /// or `null` when either endpoint is missing from [rects].
  Widget? _badgeFor(
    StateTransition transition,
    Map<EntityAddress, Rect> rects,
  ) {
    final src = rects[transition.source];
    final dst = rects[transition.target];
    if (src == null || dst == null) return null;
    final mid = StateTransitionGeometry.pointAt(
      StateTransitionGeometry.curveBetween(src, dst),
      0.5,
    );
    return Positioned(
      key: ValueKey(
        'badge:${transition.source.format()}>${transition.target.format()}',
      ),
      left: mid.dx,
      top: mid.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: StateTransitionBadge(
          kind: transition.triggerKind,
          armed: transition.armed,
          onTap: () => _onBadgeTap(transition),
        ),
      ),
    );
  }

  /// A badge tap: the arm toggle for a manual transition (tap-to-arm moved to
  /// the badge, design §5); the trigger editor for every other kind.
  void _onBadgeTap(StateTransition transition) {
    final trigger = _controller.triggerOf(transition.source, transition.target);
    if (trigger is ManualTrigger) {
      _controller.toggleArmed(transition);
    } else {
      _openTriggerEditor(transition);
    }
  }

  /// Open the trigger editor for [transition] and write the edited trigger
  /// back as one journaled payload update.
  Future<void> _openTriggerEditor(StateTransition transition) async {
    final trigger = _controller.triggerOf(transition.source, transition.target);
    if (trigger == null) return;
    final edited = await StateTriggerEditor.show(
      context,
      initial: trigger,
      domains: _domainOptions(),
      variables: widget.variables?.variables.toList() ?? const [],
    );
    if (edited == null || edited == trigger || !mounted) return;
    _controller.setTrigger(transition.source, transition.target, edited);
  }

  /// The project's `domain.` clocks a timed trigger can count on — top-level
  /// entities with a decoded [TimeDomain] payload, in registry order (the
  /// capture seam's shape).
  List<TriggerDomainOption> _domainOptions() {
    final result = <TriggerDomainOption>[];
    for (final node in _controller.registry.childrenOfKind(
      RegistryKinds.domain,
    )) {
      if (node is! RegistryEntity) continue;
      final payload = node.payload;
      if (payload is! TimeDomain) continue;
      result.add((
        address: EntityAddress(
          kind: RegistryKinds.domain,
          segments: [node.name],
        ),
        tempo: payload.tempo,
      ));
    }
    return result;
  }

  // ─── context menus (standard affordances, issue #241) ───────────────────

  Future<void> _onCanvasContextMenu(Offset global, Offset canvasLocal) async {
    final choice = await _showMenu(global, const [('new state', 'new')]);
    if (choice != 'new' || !mounted) return;
    final address = _controller.addState(position: canvasLocal);
    _select(address);
  }

  Future<void> _onNodeContextMenu(EntityAddress address, Offset global) async {
    final choice = await _showMenu(global, const [
      ('duplicate', 'duplicate'),
      ('delete', 'delete'),
    ]);
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'duplicate':
        final copy = _controller.duplicateState(address);
        if (copy != null) _select(copy);
      case 'delete':
        await _deleteWithImpact(address);
    }
  }

  /// Delete the state at [address], raising the delete-impact dialog first
  /// when other entities (inbound transitions, MIDI-graph guards) still
  /// point at it.
  Future<void> _deleteWithImpact(EntityAddress address) async {
    final impact = _controller.impactOf(address);
    if (impact.hasReferrers) {
      final confirmed = await DeleteImpactDialog.show(
        context,
        title: 'delete ${address.name}?',
        message:
            'These still point at ${address.format()}. '
            'Deleting it strands them:',
        referrers: [for (final r in impact.referrers) r.format()],
      );
      if (!confirmed || !mounted) return;
    }
    final selection = widget.session.selection.value;
    if (selection is StateEntitySelection && selection.address == address) {
      widget.session.clearSelection();
    }
    _controller.removeState(address);
  }

  Future<String?> _showMenu(Offset global, List<(String, String)> items) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(global, global),
      Offset.zero & overlay.size,
    );
    return showMenu<String>(
      context: context,
      position: position,
      color: PhiColors.bg2,
      items: [
        for (final (label, value) in items)
          PopupMenuItem<String>(
            value: value,
            height: 32,
            child: Text(
              label,
              style: PhiType.monoS().copyWith(
                fontSize: 11,
                color: PhiColors.fg0,
              ),
            ),
          ),
      ],
    );
  }
}
