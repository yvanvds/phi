import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';

/// One titled group in a synth / fx editor panel (design
/// `docs/design/racks-and-voices.md` §8 — "VA: sectioned sliders/selects from
/// the design system").
///
/// A bordered card with an uppercase caption header and a column of parameter
/// rows. Purely presentational — the rows it wraps own their own state and
/// commit path.
class EditorSection extends StatelessWidget {
  const EditorSection({
    required this.title,
    required this.children,
    this.trailing,
    super.key,
  });

  /// The section caption (e.g. `oscillators`, `filter`).
  final String title;

  /// The parameter rows the section stacks.
  final List<Widget> children;

  /// An optional control shown at the right of the header (e.g. an add button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: PhiSpacing.s3),
      padding: const EdgeInsets.all(PhiSpacing.s3),
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        borderRadius: PhiRadii.all2,
        border: Border.all(color: PhiColors.line1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: PhiType.caption().copyWith(color: PhiColors.fg1),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: PhiSpacing.s2),
          ...children,
        ],
      ),
    );
  }
}
