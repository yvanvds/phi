import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/select/phi_select.dart';
import '../../design/widgets/select/phi_select_option.dart';
import '../../design/widgets/toggle/phi_toggle.dart';
import '../../engine/state/metronome_controller.dart';

/// The metronome settings panel (issue #262, design §4): the domain picker
/// (a [PhiSelect] over the project's `domain.` entities), beats-per-bar, the
/// downbeat accent, and the click volume. Rendered inside [MetronomeControl]'s
/// popover; it reads and writes the live [MetronomeController].
class MetronomePopover extends StatelessWidget {
  const MetronomePopover({required this.controller, super.key});

  final MetronomeController controller;

  /// The beats-per-bar options the meter picker offers.
  static const List<int> beatsPerBarOptions = [2, 3, 4, 5, 6, 7];

  static const Key domainPickerKey = Key('MetronomePopover.domain');
  static const Key beatsPickerKey = Key('MetronomePopover.beats');
  static const Key accentToggleKey = Key('MetronomePopover.accent');
  static const Key volumeSliderKey = Key('MetronomePopover.volume');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(PhiSpacing.s3),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.all2,
        border: Border.all(color: PhiColors.line2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('METRONOME', style: PhiType.caption()),
          const SizedBox(height: PhiSpacing.s3),
          _Field(label: 'domain', child: _domainPicker()),
          const SizedBox(height: PhiSpacing.s2),
          _Field(label: 'beats', child: _beatsPicker()),
          const SizedBox(height: PhiSpacing.s2),
          _Field(
            label: 'accent',
            child: Align(
              alignment: Alignment.centerLeft,
              child: PhiToggle(
                key: accentToggleKey,
                value: controller.accentDownbeat,
                onChanged: (v) => controller.accentDownbeat = v,
              ),
            ),
          ),
          const SizedBox(height: PhiSpacing.s2),
          _Field(label: 'volume', child: _volumeSlider()),
        ],
      ),
    );
  }

  Widget _domainPicker() {
    return PhiSelect<String?>.flat(
      key: domainPickerKey,
      value: controller.domainName,
      placeholder: 'session tempo',
      options: [
        const PhiSelectOption<String?>(value: null, label: 'session tempo'),
        for (final domain in controller.availableDomains)
          PhiSelectOption<String?>(
            value: domain.name,
            label: '${domain.name} · ${_bpm(domain.tempo)} bpm',
          ),
      ],
      onChanged: (v) => controller.domainName = v,
    );
  }

  Widget _beatsPicker() {
    final value = controller.beatsPerBar;
    return PhiSelect<int>.flat(
      key: beatsPickerKey,
      value: value,
      options: [
        // Keep an unusual meter selectable so the closed control never blanks.
        for (final n in {value, ...beatsPerBarOptions}.toList()..sort())
          PhiSelectOption<int>(value: n, label: '$n / beat'),
      ],
      onChanged: (v) => controller.beatsPerBar = v,
    );
  }

  Widget _volumeSlider() {
    return SizedBox(
      height: 28,
      child: Slider(
        key: volumeSliderKey,
        value: controller.volume,
        activeColor: PhiColors.voice1,
        inactiveColor: PhiColors.line2,
        onChanged: (v) => controller.volume = v,
      ),
    );
  }

  static String _bpm(double tempo) =>
      tempo == tempo.roundToDouble() ? '${tempo.round()}' : tempo.toString();
}

/// One labelled row in the popover: a dim caption on the left, the control on
/// the right.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            label.toUpperCase(),
            style: PhiType.monoS().copyWith(
              color: PhiColors.fg3,
              fontSize: 9,
              letterSpacing: 0.08 * 9,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
