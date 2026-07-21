import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/code/python_traceback.dart';

/// Inline traceback strip pinned under the editor (design
/// `docs/design/live-coding.md` §5, issue #232). Shows the newest Python
/// traceback the engine's error channel delivered, verbatim, with a dismiss.
///
/// A script-origin error carries a `<script>` line the surface has already
/// mapped onto the editor; the strip labels it `line N`. A callback-origin
/// error (a scheduled callback raising later) has no matching editor line — it
/// still renders in full, labelled as a callback traceback so the performer
/// knows it did not come from the block they just ran.
class CodeErrorStrip extends StatelessWidget {
  const CodeErrorStrip({
    required this.traceback,
    required this.onDismiss,
    super.key,
  });

  /// The traceback to render.
  final PythonTraceback traceback;

  /// Invoked when the dismiss control is tapped — clears the strip.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final label = traceback.hasScriptLine
        ? 'error · line ${traceback.scriptLine}'
        : 'error · callback';
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(top: BorderSide(color: PhiColors.hot)),
      ),
      padding: const EdgeInsets.fromLTRB(
        PhiSpacing.s3,
        PhiSpacing.s2,
        PhiSpacing.s2,
        PhiSpacing.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: PhiType.caption().copyWith(color: PhiColors.hot),
                ),
              ),
              _DismissButton(onTap: onDismiss),
            ],
          ),
          const SizedBox(height: PhiSpacing.s1),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                traceback.text,
                style: PhiType.monoS().copyWith(color: PhiColors.fg1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.all(PhiSpacing.s1),
          child: Icon(Icons.close, size: 14, color: PhiColors.fg2),
        ),
      ),
    );
  }
}
