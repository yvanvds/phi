import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/inline_editable_text/inline_editable_text.dart';
import '../../design/widgets/toggle/phi_toggle.dart';
import '../../design/widgets/transport_button/transport_button.dart';
import '../../domain/project/lifecycle/project_controller.dart';
import '../../domain/project/lifecycle/project_directory_picker.dart';
import '../../domain/session/session_state.dart';
import '../../domain/session/transport_state.dart';
import '../project/dirty_indicator.dart';
import '../project/project_menu.dart';

/// Top toolbar — 36px strip.
///
/// Layout:
/// `[ phi · scene-name ]    [ transport ]    [ domains ]    [ projection ]`
///
/// Time-domain summary is a placeholder area until the time-domain layer
/// exists (see phi#5+). The projection toggle's only Phase-1 wiring is the
/// `LIVE` dot in the bottom status — see `BottomStatus`.
class TopToolbar extends StatelessWidget {
  const TopToolbar({
    required this.session,
    this.projectController,
    this.directoryPicker,
    this.onOpenSettings,
    super.key,
  });

  final SessionState session;

  /// The project lifecycle controller. When present (and [directoryPicker] is
  /// too), the toolbar shows the project menu and the dirty indicator ahead of
  /// the scene name; when `null` the toolbar keeps its bare Phase-1 layout so a
  /// standalone widget test can pump it without the project stack.
  final ProjectController? projectController;

  /// The folder picker the project menu opens native dialogs through. Required
  /// alongside [projectController] to show the menu.
  final ProjectDirectoryPicker? directoryPicker;

  /// Opens the settings dialog from the project menu (design
  /// `settings-and-devices.md` §6). `null` omits the "Settings…" item.
  final VoidCallback? onOpenSettings;

  /// Keys so tests can target the toolbar transport unambiguously. Since the
  /// MIDI surface renders its own `play`/`stop` tooltips (per-clip transport in
  /// `ClipTransportRow`, per-row previews in the library panel), a bare
  /// `find.byTooltip('play')` is ambiguous once MIDI is onstage (issues
  /// #288/#290/#292). Match the same key convention those controls already use.
  static const Key playKey = Key('TopToolbar.play');
  static const Key stopKey = Key('TopToolbar.stop');

  @override
  Widget build(BuildContext context) {
    final controller = projectController;
    final picker = directoryPicker;
    final showProject = controller != null && picker != null;
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
          if (showProject) ...[
            const SizedBox(width: PhiSpacing.s3),
            ProjectMenu(
              controller: controller,
              picker: picker,
              onOpenSettings: onOpenSettings,
            ),
            const SizedBox(width: PhiSpacing.s2),
            DirtyIndicator(isDirty: controller.isDirty),
          ],
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
            key: TopToolbar.playKey,
            icon: Icons.play_arrow,
            tooltip: 'play',
            isActive: state == TransportState.playing,
            onPressed: session.play,
          ),
          const SizedBox(width: PhiSpacing.s2),
          TransportButton(
            key: TopToolbar.stopKey,
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
