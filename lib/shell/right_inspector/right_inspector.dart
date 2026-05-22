import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_motion.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/fader/phi_fader.dart';
import '../../design/widgets/inline_editable_text/inline_editable_text.dart';
import '../../domain/session/session_state.dart';
import '../../domain/state_machine/performance_state.dart';
import '../../domain/state_machine/state_snapshot.dart';
import '../../engine/engine.dart';

/// Right inspector — collapsed by default to a 28px strip with a rotated
/// label. Tap to expand to 320px and reveal property editors for the active
/// selection. The master-volume fader is permanent at the top; below it,
/// a context panel watches [SessionState.selection] and renders editors
/// for whichever object is currently selected on any surface.
class RightInspector extends StatefulWidget {
  const RightInspector({
    required this.engine,
    required this.session,
    super.key,
  });

  final PhiEngine engine;
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
              ? _ExpandedBody(
                  engine: widget.engine,
                  session: widget.session,
                  onCollapse: _toggle,
                )
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
  const _ExpandedBody({
    required this.engine,
    required this.session,
    required this.onCollapse,
  });

  final PhiEngine engine;
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
                _MasterSection(engine: engine),
                const SizedBox(height: PhiSpacing.s5),
                ValueListenableBuilder<Object?>(
                  valueListenable: session.selection,
                  builder: (context, value, _) {
                    if (value is PerformanceState) {
                      return _PerformanceStateSection(state: value);
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

/// Inspector panel for a selected [PerformanceState]. Inline-editable
/// name + read-only [StateSnapshot] view (three labelled lists). The
/// snapshot stays read-only until the time-domain / scripting /
/// scene-pose layers ship — see [StateSnapshot] for the contract.
class _PerformanceStateSection extends StatelessWidget {
  const _PerformanceStateSection({required this.state});

  final PerformanceState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final snapshot = state.snapshot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STATE', style: PhiType.caption()),
            const SizedBox(height: PhiSpacing.s2),
            InlineEditableText(
              value: state.name,
              onChanged: state.rename,
              style: PhiType.monoL(),
            ),
            const SizedBox(height: PhiSpacing.s5),
            _SnapshotList(label: 'DOMAINS', values: snapshot.domainIds),
            const SizedBox(height: PhiSpacing.s4),
            _SnapshotList(label: 'CODE BLOCKS', values: snapshot.codeBlockIds),
            const SizedBox(height: PhiSpacing.s4),
            _SnapshotScalar(label: 'SCENE REF', value: snapshot.sceneRef),
          ],
        );
      },
    );
  }
}

class _SnapshotList extends StatelessWidget {
  const _SnapshotList({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s1),
        if (values.isEmpty)
          Text('—', style: PhiType.mono().copyWith(color: PhiColors.fg3))
        else
          for (final v in values)
            Padding(
              padding: const EdgeInsets.only(top: PhiSpacing.s0),
              child: Text(v, style: PhiType.mono()),
            ),
      ],
    );
  }
}

class _SnapshotScalar extends StatelessWidget {
  const _SnapshotScalar({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s1),
        Text(
          value ?? '—',
          style: PhiType.mono().copyWith(
            color: value == null ? PhiColors.fg3 : PhiColors.fg1,
          ),
        ),
      ],
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
  const _MasterSection({required this.engine});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MASTER', style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s3),
        Center(
          child: ValueListenableBuilder<double>(
            valueListenable: engine.masterVolume,
            builder: (context, value, _) => PhiFader(
              value: value,
              onChanged: engine.setMasterVolume,
              readout: value.toStringAsFixed(2),
              label: 'volume',
            ),
          ),
        ),
      ],
    );
  }
}
