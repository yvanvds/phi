import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../design/widgets/button/primary_button.dart';
import '../../design/widgets/channel_strip/channel_strip.dart';
import '../../engine/engine.dart';
import '../../engine/state/mixer_channel.dart';
import '../surface.dart';

/// Mix surface — horizontal rack of channel strips. User channels on the
/// left, the master strip pinned on the right behind a separator. The
/// header carries the channel count, a `+` to add a user channel, and the
/// engine's built-in test-signal toggle (kept here from the Phase-1 stub
/// so we can audibly verify additions without firing up an external
/// source).
class MixSurface extends Surface {
  const MixSurface({required this.engine, super.key});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      padding: const EdgeInsets.all(PhiSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(engine: engine),
          const SizedBox(height: PhiSpacing.s2),
          Expanded(
            child: ValueListenableBuilder<List<MixerChannel>>(
              valueListenable: engine.channels,
              builder: (context, channels, _) =>
                  _StripRack(engine: engine, userChannels: channels),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.engine});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ValueListenableBuilder<List<MixerChannel>>(
          valueListenable: engine.channels,
          builder: (context, channels, _) => Text(
            'MIX · ${channels.length + 1} CHANNELS',
            style: PhiType.caption(),
          ),
        ),
        const SizedBox(width: PhiSpacing.s3),
        _AddChannelButton(engine: engine),
        const Spacer(),
        SizedBox(
          width: 140,
          child: ValueListenableBuilder<bool>(
            valueListenable: engine.testSignal,
            builder: (context, armed, _) => PrimaryButton(
              label: armed ? 'stop sine' : 'play sine',
              isArmed: armed,
              onPressed: () => engine.setTestSignal(on: !armed),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddChannelButton extends StatelessWidget {
  const _AddChannelButton({required this.engine});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: engine.isStarted ? () => engine.addChannel() : null,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(color: PhiColors.line2),
            borderRadius: PhiRadii.all1,
          ),
          child: Text(
            '+',
            style: PhiType.monoL().copyWith(color: PhiColors.fg1),
          ),
        ),
      ),
    );
  }
}

class _StripRack extends StatelessWidget {
  const _StripRack({required this.engine, required this.userChannels});

  final PhiEngine engine;
  final List<MixerChannel> userChannels;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all1,
      ),
      padding: const EdgeInsets.all(PhiSpacing.s2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final ch in userChannels) ...[
              _BoundStrip(engine: engine, channel: ch),
              const SizedBox(width: PhiSpacing.s1),
            ],
            const SizedBox(width: PhiSpacing.s2),
            Container(width: 1, color: PhiColors.line1),
            const SizedBox(width: PhiSpacing.s2),
            _BoundStrip(engine: engine, channel: engine.masterChannel),
          ],
        ),
      ),
    );
  }
}

class _BoundStrip extends StatelessWidget {
  const _BoundStrip({required this.engine, required this.channel});

  final PhiEngine engine;
  final MixerChannel channel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: channel,
      builder: (context, _) => ChannelStrip(
        name: channel.name,
        volume: channel.volume,
        peak: channel.peak,
        muted: channel.muted,
        soloed: channel.soloed,
        voiceColor: PhiVoices.color(channel.voice),
        voiceGlow: PhiVoices.glow(channel.voice),
        isMaster: channel.isMaster,
        onVolumeChanged: (v) => engine.setChannelVolume(channel, v),
        onMuteToggle: channel.isMaster
            ? null
            : () => engine.setChannelMuted(channel, muted: !channel.muted),
        onSoloToggle: channel.isMaster
            ? null
            : () => engine.setChannelSoloed(channel, soloed: !channel.soloed),
      ),
    );
  }
}
