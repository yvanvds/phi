import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_motion.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/fader/phi_fader.dart';
import '../../design/widgets/inline_editable_text/inline_editable_text.dart';
import '../../domain/session/session_state.dart';
import '../../engine/state/state_entity_selection.dart';

/// Right inspector — collapsed by default to a 28px strip with a rotated
/// label. Tap to expand to 320px and reveal property editors for the active
/// selection. The master-volume fader is permanent at the top; below it,
/// a context panel watches [SessionState.selection] and renders editors
/// for whichever object is currently selected on any surface.
class RightInspector extends StatefulWidget {
  const RightInspector({required this.session, super.key});

  final SessionState session;

  @override
  State<RightInspector> createState() => _RightInspectorState();
}

class _RightInspectorState extends State<RightInspector> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: PhiMotion.dur3,
      curve: PhiMotion.easeOut,
      width: _expanded
          ? PhiSpacing.rightInspectorExpandedWidth
          : PhiSpacing.rightInspectorCollapsedWidth,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(left: BorderSide(color: PhiColors.line1)),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: _expanded
              ? PhiSpacing.rightInspectorExpandedWidth
              : PhiSpacing.rightInspectorCollapsedWidth,
          maxWidth: _expanded
              ? PhiSpacing.rightInspectorExpandedWidth
              : PhiSpacing.rightInspectorCollapsedWidth,
          child: _expanded
              ? _ExpandedBody(session: widget.session, onCollapse: _toggle)
              : _CollapsedStrip(onExpand: _toggle),
        ),
      ),
    );
  }
}

class _CollapsedStrip extends StatelessWidget {
  const _CollapsedStrip({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text('INSPECTOR', style: PhiType.caption()),
        ),
      ),
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({required this.session, required this.onCollapse});

  final SessionState session;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(onCollapse: onCollapse),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: PhiSpacing.s3,
              vertical: PhiSpacing.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MasterSection(session: session),
                const SizedBox(height: PhiSpacing.s5),
                ValueListenableBuilder<Object?>(
                  valueListenable: session.selection,
                  builder: (context, value, _) {
                    if (value is StateEntitySelection) {
                      return _StateEntitySection(
                        selection: value,
                        session: session,
                      );
                    }
                    return const _NoSelection();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NO SELECTION', style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s2),
        Text(
          'Select an object on a surface to edit its properties here.',
          style: PhiType.small(),
        ),
      ],
    );
  }
}

/// Inspector panel for a selected `state.` entity (issue #241). Inline-
/// editable name — an edit renames the entity through the controller's
/// journaled rename-refactor and re-publishes the selection at its new
/// address — plus the entity address and a read-only outbound-transitions
/// list. The full SLICES / ON ENTER / TRANSITIONS editors arrive with the
/// state-graph epic's inspector issue (design state-graph §6).
class _StateEntitySection extends StatelessWidget {
  const _StateEntitySection({required this.selection, required this.session});

  final StateEntitySelection selection;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final controller = selection.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final node = controller.nodeAt(selection.address);
        final document = controller.documentOf(selection.address);
        // The selected entity is gone (deleted, or renamed from elsewhere) —
        // the selection is stale, so fall back to the empty panel.
        if (node == null || document == null) return const _NoSelection();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STATE', style: PhiType.caption()),
            const SizedBox(height: PhiSpacing.s2),
            InlineEditableText(
              value: node.name,
              onChanged: (name) {
                final to = controller.rename(selection.address, name);
                if (to != null && to != selection.address) {
                  session.select(selection.withAddress(to));
                }
              },
              style: PhiType.monoL(),
            ),
            const SizedBox(height: PhiSpacing.s1),
            Text(
              node.address.format(),
              style: PhiType.small().copyWith(color: PhiColors.fg3),
            ),
            const SizedBox(height: PhiSpacing.s5),
            Text('TRANSITIONS', style: PhiType.caption()),
            const SizedBox(height: PhiSpacing.s1),
            if (document.transitions.isEmpty)
              Text('—', style: PhiType.mono().copyWith(color: PhiColors.fg3))
            else
              for (final spec in document.transitions)
                Padding(
                  padding: const EdgeInsets.only(top: PhiSpacing.s0),
                  child: Text(
                    '→ ${spec.to.name} · ${spec.label ?? spec.trigger.kind}',
                    style: PhiType.mono(),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCollapse,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
        decoration: const BoxDecoration(
          color: PhiColors.bg2,
          border: Border(bottom: BorderSide(color: PhiColors.line1)),
        ),
        child: Row(
          children: [
            Text('INSPECTOR', style: PhiType.caption()),
            const Spacer(),
            Text('×', style: PhiType.caption().copyWith(color: PhiColors.fg2)),
          ],
        ),
      ),
    );
  }
}

class _MasterSection extends StatelessWidget {
  const _MasterSection({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MASTER', style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s3),
        Center(
          // Bound to the session (not the engine directly): master volume is
          // manifest state (design `docs/design/mix.md` §3), so the fader writes
          // it there — the shell mirrors it onto the engine, and a save persists
          // it. Mirrors how the session owns tempo.
          child: ValueListenableBuilder<double>(
            valueListenable: session.masterVolume,
            builder: (context, value, _) => PhiFader(
              value: value,
              onChanged: session.setMasterVolume,
              readout: value.toStringAsFixed(2),
              label: 'volume',
            ),
          ),
        ),
      ],
    );
  }
}
