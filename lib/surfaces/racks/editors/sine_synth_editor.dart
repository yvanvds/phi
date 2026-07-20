import 'package:flutter/material.dart';

import '../../../domain/project/entity_address.dart';
import '../../../domain/synth/sine_synth.dart';
import '../../../engine/state/rack_definitions_controller.dart';
import 'editor_number_row.dart';
import 'editor_section.dart';

/// The editor panel for a [SineSynth] definition (design
/// `docs/design/racks-and-voices.md` §4 — "sine — voice count only; the
/// zero-config starter").
///
/// The sine recipe carries nothing but its polyphony, so the panel is a single
/// voice-count field. Every edit commits through
/// [RackDefinitionsController.updateSynth] as one journaled payload command.
class SineSynthEditor extends StatelessWidget {
  const SineSynthEditor({
    required this.controller,
    required this.address,
    required this.definition,
    super.key,
  });

  final RackDefinitionsController controller;
  final EntityAddress address;
  final SineSynth definition;

  @override
  Widget build(BuildContext context) {
    return EditorSection(
      title: 'voices',
      children: [
        EditorNumberRow(
          label: 'voice count',
          value: definition.voiceCount,
          min: 1,
          max: 64,
          onCommit: (v) => controller.updateSynth(
            address,
            definition.copyWith(voiceCount: v),
          ),
        ),
      ],
    );
  }
}
