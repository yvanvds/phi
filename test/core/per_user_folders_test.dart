import 'package:flutter_test/flutter_test.dart';
import 'package:phi/core/per_user_folders.dart';

PerUserFolders _folders(String os, Map<String, String> env) => PerUserFolders(
  operatingSystem: os,
  environment: env,
  currentDirectory: os == 'windows' ? r'C:\work' : '/work',
);

void main() {
  group('PerUserFolders on Windows (unchanged by #454)', () {
    const appData = r'C:\Users\yvan\AppData\Roaming';

    test('settings live in %APPDATA%\\phi', () {
      final folders = _folders('windows', {
        'APPDATA': appData,
        'HOME': r'C:\Users\yvan',
        'XDG_CONFIG_HOME': r'C:\xdg',
      });
      expect(folders.settingsDirectory(), '$appData\\phi');
    });

    test('logs live in %APPDATA%\\phi\\logs', () {
      final folders = _folders('windows', {
        'APPDATA': appData,
        'XDG_STATE_HOME': r'C:\xdg',
      });
      expect(folders.logsDirectory(), '$appData\\phi\\logs');
    });

    test('falls back to HOME, then USERPROFILE, then the cwd', () {
      expect(
        _folders('windows', {
          'HOME': r'C:\home',
          'USERPROFILE': r'C:\profile',
        }).settingsDirectory(),
        r'C:\home\phi',
      );
      expect(
        _folders('windows', {'USERPROFILE': r'C:\profile'}).logsDirectory(),
        r'C:\profile\phi\logs',
      );
      expect(_folders('windows', {}).settingsDirectory(), r'C:\work\phi');
    });
  });

  group('PerUserFolders on Linux (XDG)', () {
    test('defaults to ~/.config/phi and ~/.local/state/phi/logs', () {
      final folders = _folders('linux', {'HOME': '/home/yvan'});
      expect(folders.settingsDirectory(), '/home/yvan/.config/phi');
      expect(folders.logsDirectory(), '/home/yvan/.local/state/phi/logs');
    });

    test('honours absolute XDG_CONFIG_HOME and XDG_STATE_HOME', () {
      final folders = _folders('linux', {
        'HOME': '/home/yvan',
        'XDG_CONFIG_HOME': '/cfg',
        'XDG_STATE_HOME': '/state',
      });
      expect(folders.settingsDirectory(), '/cfg/phi');
      expect(folders.logsDirectory(), '/state/phi/logs');
    });

    test('ignores relative or empty XDG values, as the spec requires', () {
      final folders = _folders('linux', {
        'HOME': '/home/yvan',
        'XDG_CONFIG_HOME': 'relative/cfg',
        'XDG_STATE_HOME': '',
      });
      expect(folders.settingsDirectory(), '/home/yvan/.config/phi');
      expect(folders.logsDirectory(), '/home/yvan/.local/state/phi/logs');
    });

    test('never uses APPDATA or the visible ~/phi folder', () {
      final folders = _folders('linux', {
        'HOME': '/home/yvan',
        'APPDATA': '/appdata',
      });
      expect(folders.settingsDirectory(), isNot(startsWith('/appdata')));
      expect(folders.settingsDirectory(), isNot('/home/yvan/phi'));
    });

    test('falls back to the cwd when HOME is unset', () {
      final folders = _folders('linux', {});
      expect(folders.settingsDirectory(), '/work/.config/phi');
      expect(folders.logsDirectory(), '/work/.local/state/phi/logs');
    });
  });

  test('host() resolves against the running process', () {
    final folders = PerUserFolders.host();
    expect(folders.settingsDirectory(), endsWith('phi'));
    expect(folders.logsDirectory(), endsWith('logs'));
  });
}
