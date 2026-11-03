import 'dart:io';

import 'proc_task_reader.dart';

/// The production [ProcTaskReader]: reads the real `/proc/self/task` tree with
/// synchronous `dart:io` calls (issue #24). A sample is a few dozen tiny
/// procfs reads, cheap enough for a once-a-second poll on the UI isolate.
class IoProcTaskReader implements ProcTaskReader {
  /// Reads under [root] — `/proc/self/task` unless a test points elsewhere.
  const IoProcTaskReader({this.root = '/proc/self/task'});

  /// The directory holding one sub-directory per thread.
  final String root;

  @override
  List<String> taskIds() => [
    for (final entry in Directory(root).listSync(followLinks: false))
      entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ];

  @override
  String? readStat(String taskId) => _read('$root/$taskId/stat');

  @override
  String? readComm(String taskId) => _read('$root/$taskId/comm');

  static String? _read(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }
}
