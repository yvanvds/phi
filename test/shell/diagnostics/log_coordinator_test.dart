import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_recorder.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_store.dart';
import 'package:phi/engine/bridge/code_evaluator.dart';
import 'package:phi/shell/diagnostics/log_coordinator.dart';

void main() {
  late LogStore store;
  late StreamController<String> engine;
  late StreamController<EvalEvent> python;
  late LogCoordinator coordinator;

  setUp(() {
    store = LogStore();
    engine = StreamController<String>.broadcast();
    python = StreamController<EvalEvent>.broadcast();
    coordinator = LogCoordinator(
      recorder: LogRecorder(store: store),
      engineMessages: engine.stream,
      pythonEvents: python.stream,
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await engine.close();
    await python.close();
  });

  test('engine lines land tagged engine, level from the text', () async {
    engine.add('device opened');
    engine.add('ERROR: callback overran');
    await Future<void>.delayed(Duration.zero);

    expect(store.entries.map((e) => e.source), everyElement(LogSource.engine));
    expect(store.entries[0].level, LogLevel.info);
    expect(store.entries[0].text, 'device opened');
    expect(store.entries[1].level, LogLevel.error);
  });

  test('Python tracebacks land tagged python at error level', () async {
    python.add(const EvalStderr('Traceback: NameError'));
    await Future<void>.delayed(Duration.zero);

    expect(store.entries.single.source, LogSource.python);
    expect(store.entries.single.level, LogLevel.error);
    expect(store.entries.single.text, 'Traceback: NameError');
  });

  test('non-stderr evaluator frames are not logged', () async {
    python.add(const EvalStdout('print output'));
    python.add(const EvalDiagnostic('info'));
    await Future<void>.delayed(Duration.zero);

    expect(store.isEmpty, isTrue);
  });

  test('dispose stops recording further source events', () async {
    await coordinator.dispose();
    engine.add('after dispose');
    python.add(const EvalStderr('after dispose'));
    await Future<void>.delayed(Duration.zero);

    expect(store.isEmpty, isTrue);
  });
}
