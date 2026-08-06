import '../../core/app_version.dart';
import '../../domain/log/diagnostics_bundle.dart';
import '../../domain/log/log_store.dart';
import '../../domain/project/app_settings/audio_settings.dart';
import '../../engine/engine.dart';

/// Gathers the live diagnostics facts into a paste-ready [DiagnosticsBundle]
/// (design `docs/design/diagnostics.md` §6, issue #272).
///
/// The single source of truth behind both the "Copy Diagnostics" palette command
/// and the settings DIAGNOSTICS copy button — each just calls [compose] and
/// writes the result to the clipboard, so the two never drift. This is the one
/// place above the engine façade that reads the version, resolved DLL path,
/// active device + audio state, and the shared log; the pure bundle it builds is
/// what the assembly tests exercise.
class DiagnosticsReport {
  /// Binds the report to its live sources: the [engine] façade, the shared
  /// unified [log], and a [projectPath] resolver (the open `.phi` folder, or
  /// `null`). [appVersion] defaults to Phi's own constant.
  const DiagnosticsReport({
    required this.engine,
    required this.log,
    this.projectPath,
    this.appVersion = phiAppVersion,
  });

  /// The engine façade — the only path above the bridge to version, resolved
  /// path, active device, live audio state, and the audio-stall counters.
  final PhiEngine engine;

  /// The shared unified log the report tails.
  final LogStore log;

  /// Resolves the open project's folder at compose time, or `null` when there is
  /// no project (or none was saved yet).
  final String? Function()? projectPath;

  /// Phi's application version string.
  final String appVersion;

  /// The "(not set)" note the diagnostics rows and bundle share for an unset
  /// `YSE_DLL_PATH`.
  static const String pathUnset = '(not set — bundled library)';

  /// What the device row and the bundle both say when the engine has **no**
  /// device open (issue #408) — a total loss, where naming the last device the
  /// engine was on is precisely the lie a performer pastes into a bug report.
  /// Deliberately distinct from `System default`, which means a device *is* open
  /// and it is the platform's own.
  static const String noDevice = 'none — no audio device open';

  /// Composes the bundle from a fresh read of every live source and renders it.
  /// Called at the moment of the copy so the drop counter and log tail are
  /// current.
  String compose() {
    final audio = engine.activeAudioState();
    final settings = engine.activeAudioSettings;
    return DiagnosticsBundle(
      appVersion: appVersion,
      engineVersion: engine.engineVersion,
      libraryPath: engine.engineLibraryPath ?? pathUnset,
      device: describeDevice(settings),
      sampleRate: audio.sampleRate,
      bufferSize: audio.bufferSize,
      outputLatencyMs: audio.outputLatencyMs,
      // No open device means no layout in effect either. The bundle only prints
      // the layout beside a live rate, so this reads as the same "no device
      // open" line rather than a leftover from the device that went away.
      layout: settings?.layout.wireName ?? noDevice,
      audioStalls: engine.audioStalls,
      peakStallTicks: engine.peakStallTicks,
      projectPath: projectPath?.call(),
      log: log.entries,
    ).render();
  }

  /// Formats the active device for both the bundle and the DIAGNOSTICS section's
  /// read-back row — the two share this one function so they can never drift:
  /// `device · host`, the bare device when the host is unknown, `System default`
  /// when a device is open but none was chosen, and [noDevice] when [audio] is
  /// `null`, i.e. nothing is open at all (issue #408).
  static String describeDevice(AudioSettings? audio) {
    if (audio == null) return noDevice;
    final device = audio.outputDevice;
    if (device == null) return 'System default';
    final host = audio.outputHost;
    return host == null ? device : '$device · $host';
  }
}
