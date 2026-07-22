import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../engine/engine.dart';
import '../../engine/state/engine_telemetry.dart';

/// The DIAGNOSTICS section of the settings dialog (design
/// `docs/design/settings-and-devices.md` §6): read-only rows the performer can
/// copy into a bug report.
///
/// The rows read live engine facts, **not** stored settings — the libYSE
/// version, the resolved `YSE_DLL_PATH`, the device actually open, and the
/// dropped-callback counter (which ticks with telemetry). The copy button yields
/// a paste-ready plain-text block.
///
/// When the shell supplies [report] (production, via `DiagnosticsReport`), the
/// button copies the **full** diagnostics bundle — the same block the "Copy
/// Diagnostics" palette command produces, adding the app version, the live audio
/// state, the open project path, and the last 200 log lines (design §6, issue
/// #272). Without it (a bare section, e.g. a focused widget test) the button
/// falls back to the read-only facts shown here.
class DiagnosticsSettingsSection extends StatelessWidget {
  const DiagnosticsSettingsSection({
    required this.engine,
    this.report,
    super.key,
  });

  /// The engine façade — the only path above the bridge to the library version,
  /// resolved path, active device, and drop counter.
  final PhiEngine engine;

  /// Builds the full paste-ready diagnostics bundle at the moment of the tap.
  /// `null` in a bare section, which then copies just the rows below.
  final String Function()? report;

  static const String _pathUnset = '(not set — bundled library)';

  String get _libraryPath => engine.engineLibraryPath ?? _pathUnset;

  String get _activeDevice {
    final audio = engine.activeAudioSettings;
    final device = audio.outputDevice;
    if (device == null) return 'System default';
    final host = audio.outputHost;
    return host == null ? device : '$device · $host';
  }

  /// The paste-ready block the copy button writes to the clipboard.
  String _report(int drops) =>
      'Phi diagnostics\n'
      'libYSE version: ${engine.engineVersion}\n'
      'YSE_DLL_PATH: $_libraryPath\n'
      'Active device: $_activeDevice\n'
      'Dropped callbacks: $drops';

  @override
  Widget build(BuildContext context) {
    // The drop counter ticks with telemetry; the rest is static per open. Rebuild
    // on every tick and re-read the live value, exactly as the AUDIO read-back.
    return StreamBuilder<EngineTelemetry>(
      stream: engine.telemetry,
      builder: (context, _) {
        final drops = engine.missedCallbacks;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(PhiSpacing.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row('libYSE version', engine.engineVersion),
              _row('YSE_DLL_PATH', _libraryPath),
              _row('active device', _activeDevice),
              _row('dropped callbacks', '$drops'),
              const SizedBox(height: PhiSpacing.s5),
              Align(
                alignment: Alignment.centerLeft,
                child: _CopyButton(report: report ?? () => _report(drops)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PhiSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label.toUpperCase(), style: PhiType.caption()),
          const SizedBox(height: PhiSpacing.s1),
          SelectableText(
            value,
            style: PhiType.mono().copyWith(color: PhiColors.fg0),
          ),
        ],
      ),
    );
  }
}

/// The "copy for bug report" button — writes the diagnostics block to the
/// clipboard and briefly confirms.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.report});

  /// Builds the paste-ready block at the moment of the tap (so a fresh drop
  /// count is captured).
  final String Function() report;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _hovered = false;
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.report()));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_copy()),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
          decoration: BoxDecoration(
            color: _hovered ? PhiColors.bg3 : PhiColors.bg2,
            borderRadius: PhiRadii.all2,
            border: Border.all(color: PhiColors.line1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check : Icons.copy,
                size: 14,
                color: _copied ? PhiColors.voice1 : PhiColors.fg2,
              ),
              const SizedBox(width: PhiSpacing.s2),
              Text(
                _copied ? 'copied' : 'copy for bug report',
                style: PhiType.caption().copyWith(
                  color: _copied ? PhiColors.voice1 : PhiColors.fg1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
