import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/shortcuts/shortcut_hint.dart';
import '../../domain/shortcuts/shortcut_hint_section.dart';
import 'shortcut_chip.dart';
import 'shortcut_filter.dart';

/// The keyboard shortcuts overlay (issue #487): a modal sheet like the command
/// palette, opened on Ctrl+/ (or the "Keyboard Shortcuts" command / File menu
/// item), listing [sections] — the focused surface's table first, then the
/// global chords, then the other surfaces (see `ShortcutCatalog.sections`).
///
/// A filter field narrows it with the palette's fuzzy matching
/// ([ShortcutFilter]); Esc closes it. Purely a reference — nothing here runs a
/// command.
class KeyboardShortcutsOverlay extends StatefulWidget {
  const KeyboardShortcutsOverlay({required this.sections, super.key});

  final List<ShortcutHintSection> sections;

  /// Key on the filter field, for tests.
  static const Key fieldKey = Key('KeyboardShortcutsOverlay.field');

  /// Opens the overlay over [context]; resolves when it is dismissed.
  static Future<void> show(
    BuildContext context, {
    required List<ShortcutHintSection> sections,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => KeyboardShortcutsOverlay(sections: sections),
    );
  }

  @override
  State<KeyboardShortcutsOverlay> createState() =>
      _KeyboardShortcutsOverlayState();
}

class _KeyboardShortcutsOverlayState extends State<KeyboardShortcutsOverlay> {
  final TextEditingController _query = TextEditingController();
  late List<ShortcutHintSection> _visible = widget.sections;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _visible = ShortcutFilter.run(value, widget.sections));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s5),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 640,
            constraints: const BoxConstraints(maxHeight: 560),
            decoration: BoxDecoration(
              color: PhiColors.bg1,
              borderRadius: PhiRadii.all3,
              border: Border.all(color: PhiColors.line2),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 32),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(),
                const Divider(height: 1, thickness: 1, color: PhiColors.line1),
                Flexible(child: _list()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s4,
        vertical: PhiSpacing.s2,
      ),
      child: Row(
        children: [
          const Icon(Icons.keyboard_outlined, size: 18, color: PhiColors.fg2),
          const SizedBox(width: PhiSpacing.s2),
          Expanded(
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                key: KeyboardShortcutsOverlay.fieldKey,
                controller: _query,
                autofocus: true,
                onChanged: _onQueryChanged,
                style: PhiType.body().copyWith(color: PhiColors.fg0),
                cursorColor: PhiColors.voice1,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Filter shortcuts…',
                  hintStyle: PhiType.body().copyWith(color: PhiColors.fg3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(PhiSpacing.s5),
        child: Text(
          'No matching shortcuts',
          style: PhiType.monoS().copyWith(color: PhiColors.fg3),
        ),
      );
    }
    // Flattened so the lazy list builds headers and rows alike.
    final items = <Object>[
      for (final section in _visible) ...[section, ...section.hints],
    ];
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: PhiSpacing.s2),
      itemCount: items.length,
      itemBuilder: (context, index) => switch (items[index]) {
        final ShortcutHintSection section => _SectionHeader(
          title: section.title,
        ),
        final ShortcutHint hint => _HintRow(hint: hint),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PhiSpacing.s4,
        PhiSpacing.s4,
        PhiSpacing.s4,
        PhiSpacing.s1,
      ),
      child: Text(
        title.toUpperCase(),
        style: PhiType.caption().copyWith(color: PhiColors.voice1),
      ),
    );
  }
}

/// One hint: the action (and its mode note beneath) left, its chords right.
class _HintRow extends StatelessWidget {
  const _HintRow({required this.hint});

  final ShortcutHint hint;

  @override
  Widget build(BuildContext context) {
    final note = hint.note;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s4,
        vertical: PhiSpacing.s1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hint.action,
                  style: PhiType.body().copyWith(color: PhiColors.fg1),
                ),
                if (note != null)
                  Text(
                    note,
                    style: PhiType.monoS().copyWith(color: PhiColors.fg3),
                  ),
              ],
            ),
          ),
          const SizedBox(width: PhiSpacing.s3),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: PhiSpacing.s1,
              runSpacing: PhiSpacing.s1,
              children: [for (final key in hint.keys) ShortcutChip(label: key)],
            ),
          ),
        ],
      ),
    );
  }
}
