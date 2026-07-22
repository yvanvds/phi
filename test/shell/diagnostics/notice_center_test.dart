import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_store.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';

void main() {
  group('NoticeCenter', () {
    test('notice writes an app log entry AND shows a toast (the pairing)', () {
      final center = NoticeCenter.build();

      center.notice('device unavailable', level: LogLevel.warning);

      // The log half.
      expect(center.log.entries, hasLength(1));
      expect(center.log.entries.single.source, LogSource.app);
      expect(center.log.entries.single.level, LogLevel.warning);
      expect(center.log.entries.single.text, 'device unavailable');
      // The toast half — one call, both surfaces.
      expect(center.toasts.visible, hasLength(1));
      expect(center.toasts.visible.single.text, 'device unavailable');
      expect(center.toasts.visible.single.level, LogLevel.warning);

      center.dispose();
    });

    test('defaults to info level', () {
      final center = NoticeCenter.build();
      center.notice('project opened');
      expect(center.log.entries.single.level, LogLevel.info);
      expect(center.toasts.visible.single.level, LogLevel.info);
      center.dispose();
    });

    test('errors are logged at error level', () {
      final center = NoticeCenter.build();
      center.notice('no audio device', level: LogLevel.error);
      expect(center.log.entries.single.level, LogLevel.error);
      center.dispose();
    });

    test('shares an injected store instead of owning one', () {
      final store = LogStore();
      final center = NoticeCenter.build(store: store);
      expect(center.ownsStore, isFalse);
      expect(center.log, same(store));

      center.notice('shared');
      expect(store.entries.single.text, 'shared');

      // Disposing must NOT dispose a store it does not own — still usable.
      center.dispose();
      expect(() => store.add(store.entries.single), returnsNormally);
      store.dispose();
    });
  });
}
