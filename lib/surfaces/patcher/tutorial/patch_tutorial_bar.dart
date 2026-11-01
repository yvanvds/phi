import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import 'patch_word_button.dart';

/// The banner over the canvas while a **tutorial** is open (issue #489) — in
/// place of the placement bar, since a tutorial is not a project patch and has
/// no placement of its own.
///
/// It says what the canvas is ("Tutorial — read-only" and the tutorial's
/// title), and offers the two ways out: **copy to project** (mint an editable
/// `patch.tutorials.<slug>` copy) and **close** (back to the project patch).
class PatchTutorialBar extends StatelessWidget {
  const PatchTutorialBar({
    required this.title,
    required this.onCopyToProject,
    required this.onClose,
    super.key,
  });

  /// The open tutorial's title.
  final String title;

  /// Copy the tutorial into the project.
  final VoidCallback onCopyToProject;

  /// Close the tutorial.
  final VoidCallback onClose;

  /// Same height as the placement bar it stands in for.
  static const double height = 32;

  /// Key on the read-only banner caption.
  static const Key bannerKey = Key('PatchTutorialBar.banner');

  /// Key on the copy-to-project button.
  static const Key copyKey = Key('PatchTutorialBar.copy');

  /// Key on the close button.
  static const Key closeKey = Key('PatchTutorialBar.close');

  /// The banner's text.
  static const String bannerText = 'Tutorial — read-only';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
      decoration: const BoxDecoration(
        color: PhiColors.bg2,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: Row(
        children: [
          Text(
            bannerText.toUpperCase(),
            key: bannerKey,
            style: PhiType.caption().copyWith(color: PhiColors.live),
          ),
          const SizedBox(width: PhiSpacing.s2),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            ),
          ),
          const SizedBox(width: PhiSpacing.s2),
          PatchWordButton(
            key: copyKey,
            label: 'copy to project',
            tooltip: 'add an editable copy under patch.tutorials',
            onTap: onCopyToProject,
          ),
          const SizedBox(width: PhiSpacing.s2),
          PatchWordButton(key: closeKey, label: 'close', onTap: onClose),
        ],
      ),
    );
  }
}
