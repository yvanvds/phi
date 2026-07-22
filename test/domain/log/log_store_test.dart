import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_store.dart';

void main() {
  LogEntry entryAt(int i) => LogEntry(
    source: LogSource.app,
    level: LogLevel.info,
    time: DateTime(2026, 1, 1).add(Duration(seconds: i)),
    text: 'entry $i',
  );

  group('LogStore', () {
    test('starts empty', () {
      final store = LogStore();
      expect(store.isEmpty, isTrue);
      expect(store.length, 0);
      expect(store.entries, isEmpty);
    });

    test('add appends in order, oldest first', () {
      final store = LogStore();
      store
        ..add(entryAt(0))
        ..add(entryAt(1))
        ..add(entryAt(2));
      expect(store.entries.map((e) => e.text), [
        'entry 0',
        'entry 1',
        'entry 2',
      ]);
    });

    test('drops the oldest entry once capacity is exceeded', () {
      final store = LogStore(capacity: 3);
      for (var i = 0; i < 5; i++) {
        store.add(entryAt(i));
      }
      expect(store.length, 3);
      expect(store.entries.map((e) => e.text), [
        'entry 2',
        'entry 3',
        'entry 4',
      ]);
    });

    test('defaults to the design ~2000 ring size', () {
      expect(LogStore().capacity, LogStore.defaultCapacity);
      expect(LogStore.defaultCapacity, 2000);
    });

    test('notifies on every add', () {
      final store = LogStore();
      var notifications = 0;
      store.addListener(() => notifications++);
      store
        ..add(entryAt(0))
        ..add(entryAt(1));
      expect(notifications, 2);
    });

    test('clear empties and notifies once, but not when already empty', () {
      final store = LogStore()..add(entryAt(0));
      var notifications = 0;
      store.addListener(() => notifications++);

      store.clear();
      expect(store.isEmpty, isTrue);
      expect(notifications, 1);

      store.clear();
      expect(
        notifications,
        1,
        reason: 'clearing an empty store does not notify',
      );
    });

    test('the entries view is unmodifiable', () {
      final store = LogStore()..add(entryAt(0));
      expect(() => store.entries.add(entryAt(1)), throwsUnsupportedError);
    });

    test('rejects a non-positive capacity', () {
      expect(() => LogStore(capacity: 0), throwsA(isA<AssertionError>()));
    });
  });
}
