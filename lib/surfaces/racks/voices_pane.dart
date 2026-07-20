import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/voice/voice_kind.dart';
import '../../engine/state/rack_definitions_controller.dart';
import '../../engine/state/rack_voice_row.dart';

/// The racks surface's right **voices pane** (issue #209, design
/// `docs/design/racks-and-voices.md` §8) — one row per `voice.` entity.
///
/// A **scaffold** in this issue: rows *render* (name, kind, the synth definition
/// and mix bus a voice binds, its colour swatch), but create / bind / colour /
/// kind editing, the arm-for-input toggle, and the on-screen audition test strip
/// land in the voices-pane issue (#211). It binds to the
/// [RackDefinitionsController], which flattens the `voice.` namespace into the
/// read-only [RackVoiceRow]s this shows.
class VoicesPane extends StatelessWidget {
  const VoicesPane({required this.controller, super.key});

  final RackDefinitionsController controller;

  /// Fixed pane width — the right column of the three-pane racks layout.
  static const double width = 264;

  /// Key on a voice row, by address — so tests can find a specific voice.
  static Key rowKey(EntityAddress address) =>
      Key('VoicesPane.row.${address.format()}');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(left: BorderSide(color: PhiColors.line1)),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final voices = controller.voices;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(left: PhiSpacing.s3),
                height: 28,
                alignment: Alignment.centerLeft,
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: PhiColors.line1)),
                ),
                child: Text(
                  'voices'.toUpperCase(),
                  style: PhiType.caption().copyWith(color: PhiColors.fg1),
                ),
              ),
              Expanded(
                child: voices.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(PhiSpacing.s3),
                        child: Text(
                          'no voices yet',
                          style: PhiType.monoS().copyWith(color: PhiColors.fg3),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                          vertical: PhiSpacing.s1,
                        ),
                        children: [
                          for (final voice in voices) _VoiceRow(voice: voice),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One read-only voice row: a colour swatch, the voice name, and a compact
/// binding line (the synth / channel it plays and the bus it routes to).
class _VoiceRow extends StatelessWidget {
  const _VoiceRow({required this.voice});

  final RackVoiceRow voice;

  @override
  Widget build(BuildContext context) {
    final source = voice.kind == VoiceKind.external
        ? 'ch ${voice.channel}'
        : (voice.synth?.name ?? '—');
    return Container(
      key: VoicesPane.rowKey(voice.address),
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s2,
        vertical: PhiSpacing.s1,
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _swatch(voice.colorToken),
              borderRadius: PhiRadii.all1,
            ),
          ),
          const SizedBox(width: PhiSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voice.name,
                  overflow: TextOverflow.ellipsis,
                  style: PhiType.monoS().copyWith(color: PhiColors.fg0),
                ),
                Text(
                  '$source → ${voice.output.name}',
                  overflow: TextOverflow.ellipsis,
                  style: PhiType.caption().copyWith(color: PhiColors.fg2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves a voice colour token (`voice1..voice6`) to its swatch, defaulting
  /// to the first swatch for any other/opaque token (full-palette tokens land
  /// with the voices-pane editor, #211).
  static Color _swatch(String token) {
    const prefix = 'voice';
    if (token.startsWith(prefix)) {
      final index = int.tryParse(token.substring(prefix.length));
      if (index != null) return PhiVoices.color(index);
    }
    return PhiVoices.color(1);
  }
}
