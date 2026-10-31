import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the per-user folders Phi writes outside a project: app settings and
/// session logs (issue #454).
///
/// * **Windows** — both live under `%APPDATA%/phi/` (`settings.json` directly,
///   logs in `logs/`), falling back to `%HOME%`, `%USERPROFILE%` and finally
///   the current directory.
/// * **Linux** — the XDG Base Directory spec: settings in
///   `$XDG_CONFIG_HOME/phi` (default `~/.config/phi`), logs in
///   `$XDG_STATE_HOME/phi/logs` (default `~/.local/state/phi/logs`). A relative
///   or empty `XDG_*` value is ignored, as the spec requires.
/// * **Anything else** keeps the pre-#454 fallback (`$HOME/phi`) — no other
///   platform is supported yet.
///
/// Pure resolution over an injected [operatingSystem] and [environment], so
/// every branch is unit-testable on any host; [PerUserFolders.host] binds the
/// real process values.
class PerUserFolders {
  /// Binds the resolver to an [operatingSystem] (a `Platform.operatingSystem`
  /// value), an [environment] map and the [currentDirectory] used as the
  /// last-resort base.
  PerUserFolders({
    required this.operatingSystem,
    required this.environment,
    required this.currentDirectory,
  });

  /// The resolver for the running process.
  factory PerUserFolders.host() => PerUserFolders(
    operatingSystem: Platform.operatingSystem,
    environment: Platform.environment,
    currentDirectory: Directory.current.path,
  );

  /// The `Platform.operatingSystem` value the folders are resolved for.
  final String operatingSystem;

  /// The environment variables the folders are resolved from.
  final Map<String, String> environment;

  /// The base used when no environment variable names a home folder.
  final String currentDirectory;

  bool get _isWindows => operatingSystem == 'windows';

  bool get _isLinux => operatingSystem == 'linux';

  p.Context get _path =>
      p.Context(style: _isWindows ? p.Style.windows : p.Style.posix);

  /// The folder holding `settings.json`.
  String settingsDirectory() {
    if (_isLinux) {
      return _path.join(_xdg('XDG_CONFIG_HOME', ['.config']), 'phi');
    }
    return _path.join(_legacyBase(), 'phi');
  }

  /// The folder holding the session logs and the clean-shutdown marker.
  String logsDirectory() {
    if (_isLinux) {
      return _path.join(
        _xdg('XDG_STATE_HOME', ['.local', 'state']),
        'phi',
        'logs',
      );
    }
    return _path.join(_legacyBase(), 'phi', 'logs');
  }

  /// The Windows (and pre-#454) base: `%APPDATA%`, then home, then cwd —
  /// byte-for-byte the lookup the stores did before #454.
  String _legacyBase() =>
      environment['APPDATA'] ??
      environment['HOME'] ??
      environment['USERPROFILE'] ??
      currentDirectory;

  /// `$variable` when it is set to an absolute path, else
  /// `$HOME/<defaultUnderHome...>` (or the cwd when `HOME` is unset too).
  String _xdg(String variable, List<String> defaultUnderHome) {
    final value = _nonEmpty(variable);
    if (value != null && _path.isAbsolute(value)) return value;
    final home = _nonEmpty('HOME') ?? currentDirectory;
    return _path.joinAll([home, ...defaultUnderHome]);
  }

  String? _nonEmpty(String variable) {
    final value = environment[variable];
    return (value == null || value.isEmpty) ? null : value;
  }
}
