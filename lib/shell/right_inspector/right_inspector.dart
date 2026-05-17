import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_motion.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/fader/phi_fader.dart';
import '../../engine/engine.dart';

/// Right inspector — collapsed by default to a 28px strip with a rotated
/// label. Tap to expand to 320px and reveal property editors for the active
/// selection. The first concrete editor is the master-volume fader.
class RightInspector extends StatefulWidget {
  const RightInspector({required this.engine, super.key});

  final PhiEngine engine;

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
              ? _ExpandedBody(engine: widget.engine, onCollapse: _toggle)
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
  const _ExpandedBody({required this.engine, required this.onCollapse});

  final PhiEngine engine;
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
                Text('NO SELECTION', style: PhiType.caption()),
                const SizedBox(height: PhiSpacing.s2),
                Text(
                  'Select an object on a surface to edit its properties here.',
                  style: PhiType.small(),
                ),
              ],
            ),
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
