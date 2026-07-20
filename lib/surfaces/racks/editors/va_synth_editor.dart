import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/synth/adsr_envelope.dart';
import '../../../domain/synth/lfo_type.dart';
import '../../../domain/synth/va_oscillator.dart';
import '../../../domain/synth/va_synth.dart';
import '../../../domain/synth/va_waveform.dart';
import '../../../engine/state/rack_definitions_controller.dart';
import 'editor_choice_row.dart';
import 'editor_number_row.dart';
import 'editor_section.dart';
import 'editor_slider_row.dart';

/// The full VA editor panel — the virtual-analog + wavetable voice's whole
/// recipe as sectioned sliders and selects (design
/// `docs/design/racks-and-voices.md` §4, §8): the oscillator stack, wavetable
/// position, the filter, the amp + filter envelopes, the LFO, gain and voice
/// count.
///
/// Every field mutates the [VaSynth] payload through
/// [RackDefinitionsController.updateSynth] — one journaled command per discrete
/// edit, one per slider gesture (the slider coalesces its own drag).
class VaSynthEditor extends StatelessWidget {
  const VaSynthEditor({
    required this.controller,
    required this.address,
    required this.definition,
    super.key,
  });

  final RackDefinitionsController controller;
  final EntityAddress address;
  final VaSynth definition;

  void _commit(VaSynth next) => controller.updateSynth(address, next);

  void _setOsc(int index, VaOscillator osc) {
    final next = [...definition.oscillators];
    next[index] = osc;
    _commit(definition.copyWith(oscillators: next));
  }

  void _addOsc() => _commit(
    definition.copyWith(
      oscillators: [...definition.oscillators, const VaOscillator()],
    ),
  );

  void _removeOsc(int index) {
    if (definition.oscillators.length <= 1) return;
    final next = [...definition.oscillators]..removeAt(index);
    _commit(definition.copyWith(oscillators: next));
  }

  @override
  Widget build(BuildContext context) {
    final filter = definition.filter;
    final amp = definition.ampEnvelope;
    final filterEnv = definition.filterEnvelope;
    final lfo = definition.lfo;
    return ListView(
      children: [
        for (var i = 0; i < definition.oscillators.length; i++)
          _oscSection(i, definition.oscillators[i]),
        EditorSection(
          title: 'wavetable',
          children: [
            EditorSliderRow(
              label: 'position',
              value: definition.wavetablePosition,
              min: 0,
              max: 1,
              onCommit: (v) =>
                  _commit(definition.copyWith(wavetablePosition: v)),
            ),
          ],
        ),
        EditorSection(
          title: 'filter',
          children: [
            EditorSliderRow(
              label: 'cutoff',
              value: filter.cutoff,
              min: 20,
              max: 20000,
              asInt: true,
              onCommit: (v) => _commit(
                definition.copyWith(filter: filter.copyWith(cutoff: v)),
              ),
            ),
            EditorSliderRow(
              label: 'resonance',
              value: filter.resonance,
              min: 0,
              max: 1,
              onCommit: (v) => _commit(
                definition.copyWith(filter: filter.copyWith(resonance: v)),
              ),
            ),
            EditorSliderRow(
              label: 'key track',
              value: filter.keyTracking,
              min: 0,
              max: 1,
              onCommit: (v) => _commit(
                definition.copyWith(filter: filter.copyWith(keyTracking: v)),
              ),
            ),
            EditorSliderRow(
              label: 'env amount',
              value: filter.envAmount,
              min: -4,
              max: 4,
              onCommit: (v) => _commit(
                definition.copyWith(filter: filter.copyWith(envAmount: v)),
              ),
            ),
            EditorSliderRow(
              label: 'vel amount',
              value: filter.velAmount,
              min: -4,
              max: 4,
              onCommit: (v) => _commit(
                definition.copyWith(filter: filter.copyWith(velAmount: v)),
              ),
            ),
          ],
        ),
        _envSection(
          'amp envelope',
          amp,
          (e) => _commit(definition.copyWith(ampEnvelope: e)),
          extra: EditorSliderRow(
            label: 'vel amount',
            value: definition.ampVelAmount,
            min: 0,
            max: 1,
            onCommit: (v) => _commit(definition.copyWith(ampVelAmount: v)),
          ),
        ),
        _envSection(
          'filter envelope',
          filterEnv,
          (e) => _commit(definition.copyWith(filterEnvelope: e)),
        ),
        EditorSection(
          title: 'lfo',
          children: [
            EditorChoiceRow<LfoType>(
              label: 'type',
              value: lfo.type,
              options: [for (final t in LfoType.values) (t, t.name)],
              onChanged: (t) =>
                  _commit(definition.copyWith(lfo: lfo.copyWith(type: t))),
            ),
            EditorSliderRow(
              label: 'rate',
              value: lfo.rate,
              min: 0,
              max: 20,
              onCommit: (v) =>
                  _commit(definition.copyWith(lfo: lfo.copyWith(rate: v))),
            ),
            EditorSliderRow(
              label: 'to pitch',
              value: lfo.toPitch,
              min: -24,
              max: 24,
              onCommit: (v) =>
                  _commit(definition.copyWith(lfo: lfo.copyWith(toPitch: v))),
            ),
            EditorSliderRow(
              label: 'to cutoff',
              value: lfo.toCutoff,
              min: -4,
              max: 4,
              onCommit: (v) =>
                  _commit(definition.copyWith(lfo: lfo.copyWith(toCutoff: v))),
            ),
            EditorSliderRow(
              label: 'to wavetable',
              value: lfo.toWavetable,
              min: 0,
              max: 1,
              onCommit: (v) => _commit(
                definition.copyWith(lfo: lfo.copyWith(toWavetable: v)),
              ),
            ),
          ],
        ),
        EditorSection(
          title: 'output',
          children: [
            EditorSliderRow(
              label: 'gain',
              value: definition.gain,
              min: 0,
              max: 1,
              onCommit: (v) => _commit(definition.copyWith(gain: v)),
            ),
            EditorNumberRow(
              label: 'voice count',
              value: definition.voiceCount,
              min: 1,
              max: 64,
              onCommit: (v) => _commit(definition.copyWith(voiceCount: v)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _oscSection(int index, VaOscillator osc) {
    return EditorSection(
      title: 'osc ${index + 1}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (index == definition.oscillators.length - 1)
            _MiniButton(
              icon: Icons.add,
              tooltip: 'add oscillator',
              onTap: _addOsc,
            ),
          if (definition.oscillators.length > 1)
            _MiniButton(
              icon: Icons.close,
              tooltip: 'remove oscillator',
              onTap: () => _removeOsc(index),
            ),
        ],
      ),
      children: [
        EditorChoiceRow<VaWaveform>(
          label: 'wave',
          value: osc.wave,
          options: [for (final w in VaWaveform.values) (w, w.name)],
          onChanged: (w) => _setOsc(index, osc.copyWith(wave: w)),
        ),
        EditorSliderRow(
          label: 'detune',
          value: osc.detune,
          min: -24,
          max: 24,
          onCommit: (v) => _setOsc(index, osc.copyWith(detune: v)),
        ),
        EditorSliderRow(
          label: 'level',
          value: osc.level,
          min: 0,
          max: 1,
          onCommit: (v) => _setOsc(index, osc.copyWith(level: v)),
        ),
        EditorSliderRow(
          label: 'pulse width',
          value: osc.pulseWidth,
          min: 0,
          max: 1,
          onCommit: (v) => _setOsc(index, osc.copyWith(pulseWidth: v)),
        ),
      ],
    );
  }

  Widget _envSection(
    String title,
    AdsrEnvelope env,
    void Function(AdsrEnvelope) onChanged, {
    Widget? extra,
  }) {
    return EditorSection(
      title: title,
      children: [
        EditorSliderRow(
          label: 'attack',
          value: env.attack,
          min: 0,
          max: 4,
          onCommit: (v) => onChanged(env.copyWith(attack: v)),
        ),
        EditorSliderRow(
          label: 'decay',
          value: env.decay,
          min: 0,
          max: 4,
          onCommit: (v) => onChanged(env.copyWith(decay: v)),
        ),
        EditorSliderRow(
          label: 'sustain',
          value: env.sustain,
          min: 0,
          max: 1,
          onCommit: (v) => onChanged(env.copyWith(sustain: v)),
        ),
        EditorSliderRow(
          label: 'release',
          value: env.release,
          min: 0,
          max: 4,
          onCommit: (v) => onChanged(env.copyWith(release: v)),
        ),
        ?extra,
      ],
    );
  }
}

/// A compact square icon button for a section header action.
class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(icon, size: 15, color: PhiColors.fg2),
        ),
      ),
    );
  }
}
