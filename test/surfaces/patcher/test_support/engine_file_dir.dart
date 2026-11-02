import 'dart:io';

/// The folder where libYSE puts a patcher file named by a **relative** path:
/// `write cues.txt` on a `.coll`, `read lines.txt` on a `.textfile` (#541).
///
/// The engine's file requests prefix a relative name with
/// `YSE::GetCurrentWorkingDirectory()`. On Linux that is the process's working
/// directory (`/proc/self/cwd`), so a test that switches `Directory.current`
/// to a temp folder finds the file there. On Windows (libYSE 3.1.0) it is the
/// folder of the running executable instead, whatever the working directory
/// is (yse-soundengine#1249): `phi.exe`'s folder in an integration test,
/// `flutter_tester.exe`'s in a unit test.
Directory engineFileDir() => Platform.isWindows
    ? File(Platform.resolvedExecutable).parent
    : Directory.current;

/// Where a relative [name] lands, and whether a file is there now, in the
/// folders a reader might look: for a failure message that names what was
/// actually seen.
String whereIs(String name) {
  final places = {
    'engine folder': engineFileDir().path,
    'working directory': Directory.current.path,
    'executable folder': File(Platform.resolvedExecutable).parent.path,
  };
  return [
    for (final MapEntry(:key, :value) in places.entries)
      '$key $value: ${File('$value${Platform.pathSeparator}$name').existsSync() ? 'present' : 'absent'}',
  ].join('; ');
}
