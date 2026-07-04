import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';

/// The shared form vocabulary the typed parameter editors (issue #95) are
/// built from: a labelled row, a mono text input, and a tap-to-pick choice.
///
/// These three tiny presentational widgets share one file the same way the
/// sealed [TransformParam] variants do — they are one concept ("an editor
/// field"), always used together, and splitting them buys nothing but imports.
/// None carries state; the hosting editor owns the controllers and the live
/// apply.

/// One labelled field: [label] on the left, [child] (an input or a choice) on
/// the right at a fixed [childWidth].
class EditorRow extends StatelessWidget {
  const EditorRow({
    required this.label,
    required this.child,
    this.childWidth = 110,
    super.key,
  });

  final String label;
  final Widget child;
  final double childWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PhiType.monoS().copyWith(
                fontSize: 11,
                color: PhiColors.fg1,
              ),
            ),
          ),
          SizedBox(width: childWidth, child: child),
        ],
      ),
    );
  }
}

/// A right-aligned mono text input matching the generic scalar editor's field.
class EditorTextInput extends StatelessWidget {
  const EditorTextInput({
    required this.controller,
    required this.onChanged,
    this.hintText,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: PhiType.monoS().copyWith(fontSize: 11, color: PhiColors.fg0),
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: PhiType.monoS().copyWith(fontSize: 11, color: PhiColors.fg3),
      ),
    );
  }
}

/// A compact `×` that removes the row it sits on — the affordance the
/// list-shaped editors (table, rules, voices) hang off each entry.
class EditorRemoveButton extends StatelessWidget {
  const EditorRemoveButton({required this.onRemove, super.key});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRemove,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(
          '×',
          style: PhiType.monoS().copyWith(fontSize: 13, color: PhiColors.fg3),
        ),
      ),
    );
  }
}

/// A tap-to-pick choice: shows the current [value]'s label and opens a
/// Phi-styled popup of [options] (value, label) on tap. Mirrors the chip
/// context menu's `showMenu` styling so the editors feel of a piece.
class EditorChoice<T> extends StatelessWidget {
  const EditorChoice({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final T value;

  /// Selectable `(value, label)` pairs, in display order.
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  String get _currentLabel => options
      .firstWhere((o) => o.$1 == value, orElse: () => (value, '$value'))
      .$2;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      color: PhiColors.bg2,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final (v, label) in options)
          PopupMenuItem<T>(
            value: v,
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: const BoxDecoration(
          color: PhiColors.bg2,
          borderRadius: PhiRadii.all1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                _currentLabel,
                style: PhiType.monoS().copyWith(
                  fontSize: 11,
                  color: PhiColors.fg0,
                ),
              ),
            ),
            Text(
              '▾',
              style: PhiType.monoS().copyWith(
                fontSize: 9,
                color: PhiColors.fg3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
