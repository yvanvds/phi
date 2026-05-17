import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/inline_editable_text/inline_editable_text.dart';
import '../../design/widgets/toggle/phi_toggle.dart';
import '../../design/widgets/transport_button/transport_button.dart';
import '../../domain/session/session_state.dart';
import '../../domain/session/transport_state.dart';

/// Top toolbar — 36px strip.
///
/// Layout:
/// `[ phi · scene-name ]    [ transport ]    [ domains ]    [ projection ]`
///
/// Time-domain summary is a placeholder area until the time-domain layer
/// exists (see phi#5+). The projection toggle's only Phase-1 wiring is the
/// `LIVE` dot in the bottom status — see `BottomStatus`.
class TopToolbar extends StatelessWidget {
  const TopToolbar({required this.session, super.key});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PhiSpacing.topToolbarHeight,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s4),
      child: Row(
        children: [
          _Wordmark(),
          const SizedBox(width: PhiSpacing.s3),
          Text('/', style: PhiType.caption().copyWith(color: PhiColors.fg3)),
          const SizedBox(width: PhiSpacing.s3),
          ValueListenableBuilder<String>(
            valueListenable: session.sceneName,
            builder: (context, name, _) => InlineEditableText(
              value: name,
              onChanged: session.renameScene,
              style: PhiType.body().copyWith(color: PhiColors.fg0),
            ),
          ),
          const SizedBox(width: PhiSpacing.s5),
          _TransportControls(session: session),
          const SizedBox(width: PhiSpacing.s5),
          const Expanded(child: _DomainSummary()),
          const SizedBox(width: PhiSpacing.s4),
          _ProjectionToggle(session: session),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'phi',
      style: PhiType.h2().copyWith(
        color: PhiColors.voice1,
        shadows: const [Shadow(color: PhiColors.voice1Soft, blurRadius: 12)],
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransportState>(
      valueListenable: session.transport,
      builder: (context, state, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TransportButton(
            icon: Icons.play_arrow,
            tooltip: 'play',
            isActive: state == TransportState.playing,
            onPressed: session.play,
          ),
          const SizedBox(width: PhiSpacing.s2),
          TransportButton(
            icon: Icons.stop,
            tooltip: 'stop',
            isActive: false,
            onPressed: session.stop,
          ),
        ],
      ),
    );
  }
}

/// Placeholder for the time-domain summary row. Time domains land in a
/// later phase — see phi-vision §3 and the relevant issue.
class _DomainSummary extends StatelessWidget {
  const _DomainSummary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'no time domains yet',
        style: PhiType.caption().copyWith(color: PhiColors.fg3),
      ),
    );
  }
}

class _ProjectionToggle extends StatelessWidget {
  const _ProjectionToggle({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('projection', style: PhiType.caption()),
        const SizedBox(width: PhiSpacing.s2),
        ValueListenableBuilder<bool>(
          valueListenable: session.projection,
          builder: (context, on, _) => PhiToggle(
            value: on,
            onChanged: (_) => session.toggleProjection(),
          ),
        ),
      ],
    );
  }
}
