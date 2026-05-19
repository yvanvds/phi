import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/code/projection_strip.dart';
import 'code_eval_flash.dart';

/// Projected variant of the Code surface — read-only render of the
/// current source with full-line comments stripped and blank-line runs
/// collapsed. Recently-evaluated blocks fade through a fuchsia tint.
class CodeProjectedView extends StatelessWidget {
  const CodeProjectedView({
    required this.controller,
    required this.flash,
    super.key,
  });

  final CodeLineEditingController controller;
  final CodeEvalFlash flash;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, flash]),
      builder: (context, _) {
        final source = stripForProjection(controller.text);
        final lines = source.split('\n');
        final baseStyle = PhiType.mono().copyWith(
          color: PhiColors.fg0,
          fontSize: 16,
          height: 1.45,
        );
        return Container(
          color: PhiColors.bg0,
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s4,
            vertical: PhiSpacing.s3,
          ),
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            child: Text.rich(
              TextSpan(
                style: baseStyle,
                children: [
                  for (var i = 0; i < lines.length; i++) ...[
                    TextSpan(
                      text: lines[i],
                      style: flash.covers(i)
                          ? baseStyle.copyWith(
                              backgroundColor: PhiColors.voice1Soft.withAlpha(
                                (0x40 * flash.intensity).round(),
                              ),
                            )
                          : null,
                    ),
                    if (i < lines.length - 1) const TextSpan(text: '\n'),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
