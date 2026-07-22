import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/project/app_settings/app_settings_controller.dart';
import '../../engine/engine.dart';
import 'audio_settings_section.dart';
import 'diagnostics_settings_section.dart';
import 'midi_settings_section.dart';
import 'projects_settings_section.dart';
import 'settings_section.dart';

/// The settings dialog (design `docs/design/settings-and-devices.md` §6): a modal
/// overlay inside the main window — no rail button, no OS window. A left section
/// list (AUDIO · MIDI · PROJECTS · DIAGNOSTICS) picks the right-hand pane; it is
/// sized to never scroll a section, and has **no OK / Cancel** — every control
/// applies immediately (design §5), so closing is the only action.
///
/// All four sections carry fields: AUDIO (issue #154) plus MIDI, PROJECTS, and
/// DIAGNOSTICS (issue #151).
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    required this.engine,
    required this.settings,
    this.initialSection = SettingsSection.audio,
    this.diagnosticsReport,
    super.key,
  });

  /// The engine façade the AUDIO section drives (device list, live-switch,
  /// read-back, notices).
  final PhiEngine engine;

  /// The single settings owner (design §7) the AUDIO section persists through.
  final AppSettingsController settings;

  /// The section shown first — AUDIO by default, so the status-bar audio chip's
  /// click-through lands straight on the device pickers (issue #271).
  final SettingsSection initialSection;

  /// Builds the full paste-ready diagnostics bundle for the DIAGNOSTICS section's
  /// copy button (issue #272). `null` in a bare dialog, which then copies only
  /// the read-only rows.
  final String Function()? diagnosticsReport;

  /// Opens the dialog as a modal overlay over [context], starting on
  /// [initialSection] (AUDIO by default). Resolves when it is dismissed (there is
  /// nothing to return — every edit already applied).
  static Future<void> show(
    BuildContext context, {
    required PhiEngine engine,
    required AppSettingsController settings,
    SettingsSection initialSection = SettingsSection.audio,
    String Function()? diagnosticsReport,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (_) => SettingsDialog(
        engine: engine,
        settings: settings,
        initialSection: initialSection,
        diagnosticsReport: diagnosticsReport,
      ),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsSection _section = widget.initialSection;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: PhiColors.bg1,
      insetPadding: const EdgeInsets.all(PhiSpacing.s6),
      shape: const RoundedRectangleBorder(
        borderRadius: PhiRadii.all3,
        side: BorderSide(color: PhiColors.line2),
      ),
      child: SizedBox(
        width: 720,
        height: 460,
        child: Column(
          children: [
            _header(context),
            const Divider(height: 1, thickness: 1, color: PhiColors.line1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionList(),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: PhiColors.line1,
                  ),
                  Expanded(child: _content()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PhiSpacing.s5,
        PhiSpacing.s3,
        PhiSpacing.s2,
        PhiSpacing.s3,
      ),
      child: Row(
        children: [
          Text(
            'SETTINGS',
            style: PhiType.caption().copyWith(color: PhiColors.fg1),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: PhiColors.fg2),
            splashRadius: 16,
            tooltip: 'close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _sectionList() {
    return Container(
      width: 168,
      color: PhiColors.bg0,
      padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in SettingsSection.values)
            _SectionTile(
              label: section.label,
              selected: section == _section,
              onTap: () => setState(() => _section = section),
            ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (_section) {
      case SettingsSection.audio:
        return AudioSettingsSection(
          engine: widget.engine,
          settings: widget.settings,
        );
      case SettingsSection.midi:
        return MidiSettingsSection(
          engine: widget.engine,
          settings: widget.settings,
        );
      case SettingsSection.projects:
        return ProjectsSettingsSection(settings: widget.settings);
      case SettingsSection.diagnostics:
        return DiagnosticsSettingsSection(
          engine: widget.engine,
          report: widget.diagnosticsReport,
        );
    }
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s5),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected ? PhiColors.bg2 : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? PhiColors.voice1 : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: PhiType.caption().copyWith(
              color: selected ? PhiColors.fg0 : PhiColors.fg2,
            ),
          ),
        ),
      ),
    );
  }
}
