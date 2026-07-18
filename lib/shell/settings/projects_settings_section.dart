import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/project/app_settings/app_settings_controller.dart';

/// The PROJECTS section of the settings dialog (design
/// `docs/design/settings-and-devices.md` §6): the autosave cadence and recents
/// management.
///
/// The cadence is a seconds field (`0` disables autosave; the change applies on
/// the next timer arm, design §5). Recents management is per-entry remove,
/// clear-all, and pin/unpin (design §9.2): pinned entries float to the top of
/// the File menu and never age out. Every edit persists through the single
/// settings owner, which the File menu mirrors — so a pin or remove here shows
/// there at once.
class ProjectsSettingsSection extends StatelessWidget {
  const ProjectsSettingsSection({required this.settings, super.key});

  /// The single owner of the app settings (design §7) — the source of the
  /// cadence, recents, and pins, and the sink every edit persists through.
  final AppSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final value = settings.value;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(PhiSpacing.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('AUTOSAVE', style: PhiType.caption()),
              const SizedBox(height: PhiSpacing.s2),
              _AutosaveField(
                seconds: value.autosaveInterval.inSeconds,
                onCommit: (secs) => unawaited(
                  settings.update(
                    settings.value.withAutosaveInterval(
                      Duration(seconds: secs),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PhiSpacing.s2),
              Text(
                'seconds between saves · 0 disables autosave',
                style: PhiType.small().copyWith(color: PhiColors.fg3),
              ),
              const SizedBox(height: PhiSpacing.s6),
              _recentsHeader(
                context,
                hasRecents: value.recentProjects.isNotEmpty,
              ),
              const SizedBox(height: PhiSpacing.s2),
              _recentsList(context, value.pinnedProjects, value.recentProjects),
            ],
          ),
        );
      },
    );
  }

  Widget _recentsHeader(BuildContext context, {required bool hasRecents}) {
    return Row(
      children: [
        Text('RECENT PROJECTS', style: PhiType.caption()),
        const Spacer(),
        if (hasRecents)
          _TextAction(
            label: 'clear all',
            onPressed: () =>
                unawaited(settings.update(settings.value.withClearedRecents())),
          ),
      ],
    );
  }

  Widget _recentsList(
    BuildContext context,
    List<String> pinned,
    List<String> recents,
  ) {
    if (pinned.isEmpty && recents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s2),
        child: Text(
          'no recent projects',
          style: PhiType.small().copyWith(color: PhiColors.fg3),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final path in pinned)
          _ProjectRow(
            path: path,
            pinned: true,
            onTogglePin: () => unawaited(
              settings.update(settings.value.withoutPinnedProject(path)),
            ),
            onRemove: () => unawaited(
              settings.update(settings.value.withoutRecentProject(path)),
            ),
          ),
        for (final path in recents)
          _ProjectRow(
            path: path,
            pinned: false,
            onTogglePin: () => unawaited(
              settings.update(settings.value.withPinnedProject(path)),
            ),
            onRemove: () => unawaited(
              settings.update(settings.value.withoutRecentProject(path)),
            ),
          ),
      ],
    );
  }
}

/// The autosave cadence input — a seconds field that commits on Enter or blur.
/// Digits only; an empty commit is read as `0` (disabled).
class _AutosaveField extends StatefulWidget {
  const _AutosaveField({required this.seconds, required this.onCommit});

  final int seconds;
  final ValueChanged<int> onCommit;

  @override
  State<_AutosaveField> createState() => _AutosaveFieldState();
}

class _AutosaveFieldState extends State<_AutosaveField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.seconds}');
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_AutosaveField old) {
    super.didUpdateWidget(old);
    // Reflect an external change (e.g. a settings reload) when not being edited.
    if (!_focusNode.hasFocus && old.seconds != widget.seconds) {
      _controller.text = '${widget.seconds}';
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final secs = int.tryParse(_controller.text.trim()) ?? 0;
    if (secs != widget.seconds) widget.onCommit(secs);
    // Normalise the display (e.g. an empty field back to "0").
    _controller.text = '$secs';
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 34,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: PhiType.mono().copyWith(color: PhiColors.fg0),
        cursorColor: PhiColors.voice1,
        cursorWidth: 1,
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: PhiColors.bg2,
          contentPadding: EdgeInsets.symmetric(
            horizontal: PhiSpacing.s3,
            vertical: PhiSpacing.s2,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: PhiRadii.all2,
            borderSide: BorderSide(color: PhiColors.line1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: PhiRadii.all2,
            borderSide: BorderSide(color: PhiColors.lineHot),
          ),
        ),
      ),
    );
  }
}

/// One row in the recents list: the project name, a pin toggle, and a remove
/// button. Pinned rows show a lit pin and float above the ordinary recents.
class _ProjectRow extends StatefulWidget {
  const _ProjectRow({
    required this.path,
    required this.pinned,
    required this.onTogglePin,
    required this.onRemove,
  });

  final String path;
  final bool pinned;
  final VoidCallback onTogglePin;
  final VoidCallback onRemove;

  @override
  State<_ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<_ProjectRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
        color: _hovered ? PhiColors.bg2 : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                p.basename(widget.path),
                overflow: TextOverflow.ellipsis,
                style: PhiType.body().copyWith(
                  fontSize: 14,
                  color: PhiColors.fg1,
                ),
              ),
            ),
            _IconAction(
              icon: Icons.push_pin,
              tooltip: widget.pinned ? 'unpin' : 'pin',
              active: widget.pinned,
              onPressed: widget.onTogglePin,
            ),
            const SizedBox(width: PhiSpacing.s1),
            _IconAction(
              icon: Icons.close,
              tooltip: 'remove',
              active: false,
              onPressed: widget.onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact icon button used by the recents rows (pin / remove). Lit fuchsia
/// when [active], otherwise a muted foreground that brightens on hover.
class _IconAction extends StatefulWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (widget.active) {
      color = PhiColors.voice1;
    } else if (_hovered) {
      color = PhiColors.fg1;
    } else {
      color = PhiColors.fg3;
    }
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.all(PhiSpacing.s1),
            child: Icon(widget.icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

/// A small text button ("clear all") in the section's chrome.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Text(
          label,
          style: PhiType.caption().copyWith(color: PhiColors.fg2),
        ),
      ),
    );
  }
}
