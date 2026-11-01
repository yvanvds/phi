import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_pitch.dart';
import '../../../domain/patcher/keyboard_layout.dart';

/// The reference panel's **keyboard** rows for a selected `.kslider` (issue
/// #515): the range it shows, shifted or stretched an octave at a time, and
/// whether a press plays by its depth down the key or at one fixed velocity.
///
/// Like the note's colour row, it edits nothing itself — every pick goes out
/// through [onRange] / [onVelocity], which the surface journals. A step that
/// would run off MIDI or leave less than an octave is shown but inert.
class PatchKeyboardSettings extends StatelessWidget {
  const PatchKeyboardSettings({
    required this.range,
    required this.velocity,
    required this.onRange,
    required this.onVelocity,
    super.key,
  });

  /// The keys the keyboard shows now.
  final KeyboardLayout range;

  /// The fixed press velocity, or null while a press plays by its depth.
  final int? velocity;

  /// Called with the range a step picked.
  final ValueChanged<KeyboardLayout> onRange;

  /// Called with the fixed velocity a step picked, or null for depth.
  final ValueChanged<int?> onVelocity;

  /// The velocity switching to fixed starts at.
  static const int initialVelocity = 100;

  /// Key on the range readout.
  static const Key rangeKey = Key('PatchKeyboardSettings.range');

  /// Key on the fixed-velocity readout.
  static const Key velocityKey = Key('PatchKeyboardSettings.velocity');

  /// Key on one step button: `shift.down`, `shift.up`, `low.down`, `low.up`,
  /// `high.down`, `high.up`, `velocity.depth`, `velocity.fixed`, and
  /// `velocity.-10` / `.-1` / `.+1` / `.+10`.
  static Key stepKey(String step) => Key('PatchKeyboardSettings.$step');

  @override
  Widget build(BuildContext context) {
    final fixed = velocity;
    void moveVelocity(int by) =>
        onVelocity((fixed! + by).clamp(1, MidiPitch.maxVelocity));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PhiSpacing.s3,
        PhiSpacing.s2,
        PhiSpacing.s3,
        PhiSpacing.s1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'range',
            trailing: [
              Text(
                '${MidiPitch.name(range.low)} – ${MidiPitch.name(range.high)}',
                key: rangeKey,
                style: PhiType.monoS().copyWith(color: PhiColors.voice1),
              ),
            ],
          ),
          _Row(
            label: 'shift',
            trailing: [
              _step('shift.down', '− oct', range.shifted(-1)),
              _step('shift.up', '+ oct', range.shifted(1)),
            ],
          ),
          _Row(
            label: 'low',
            trailing: [
              _step('low.down', '− oct', range.movedLow(-1)),
              _step('low.up', '+ oct', range.movedLow(1)),
            ],
          ),
          _Row(
            label: 'high',
            trailing: [
              _step('high.down', '− oct', range.movedHigh(-1)),
              _step('high.up', '+ oct', range.movedHigh(1)),
            ],
          ),
          _Row(
            label: 'velocity',
            trailing: [
              _StepButton(
                key: stepKey('velocity.depth'),
                label: 'depth',
                selected: fixed == null,
                onTap: fixed == null ? null : () => onVelocity(null),
              ),
              _StepButton(
                key: stepKey('velocity.fixed'),
                label: 'fixed',
                selected: fixed != null,
                onTap: fixed != null ? null : () => onVelocity(initialVelocity),
              ),
            ],
          ),
          if (fixed != null)
            _Row(
              label: '',
              trailing: [
                for (final by in const [-10, -1])
                  _velocityStep(by, fixed, moveVelocity),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$fixed',
                    key: velocityKey,
                    textAlign: TextAlign.center,
                    style: PhiType.monoS().copyWith(color: PhiColors.voice1),
                  ),
                ),
                for (final by in const [1, 10])
                  _velocityStep(by, fixed, moveVelocity),
              ],
            ),
        ],
      ),
    );
  }

  Widget _step(String step, String label, KeyboardLayout? to) => _StepButton(
    key: stepKey(step),
    label: label,
    onTap: to == null ? null : () => onRange(to),
  );

  Widget _velocityStep(int by, int fixed, void Function(int) move) {
    final open = by < 0 ? fixed > 1 : fixed < MidiPitch.maxVelocity;
    return _StepButton(
      key: stepKey('velocity.${by > 0 ? '+' : ''}$by'),
      label: by > 0 ? '+$by' : '$by',
      onTap: open ? () => move(by) : null,
    );
  }
}

/// One labelled settings row: the label left, its controls right.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.trailing});

  final String label;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s1 / 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            ),
          ),
          for (var i = 0; i < trailing.length; i++) ...[
            if (i > 0) const SizedBox(width: PhiSpacing.s1),
            trailing[i],
          ],
        ],
      ),
    );
  }
}

/// A small bordered text button — dim and inert without [onTap], ringed in
/// the foreground while [selected].
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || selected;
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s1,
            vertical: PhiSpacing.s1 / 2,
          ),
          decoration: BoxDecoration(
            color: PhiColors.bg2,
            borderRadius: PhiRadii.all1,
            border: Border.all(
              color: selected ? PhiColors.fg0 : PhiColors.line2,
            ),
          ),
          child: Text(
            label,
            style: PhiType.monoS().copyWith(
              color: enabled ? PhiColors.fg0 : PhiColors.fg3,
            ),
          ),
        ),
      ),
    );
  }
}
