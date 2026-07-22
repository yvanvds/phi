import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/shell/diagnostics/toast_controller.dart';

void main() {
  group('ToastController', () {
    test('show adds a toast and notifies', () {
      final controller = ToastController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.show('hello', LogLevel.info);

      expect(controller.visible, hasLength(1));
      expect(controller.visible.single.text, 'hello');
      expect(controller.visible.single.level, LogLevel.info);
      expect(notifications, 1);
      controller.dispose();
    });

    test('assigns each toast a distinct id', () {
      final controller = ToastController();
      controller.show('a', LogLevel.info);
      controller.show('b', LogLevel.warning);

      final ids = controller.visible.map((t) => t.id).toSet();
      expect(ids, hasLength(2));
      controller.dispose();
    });

    test('dismiss removes the matching toast and notifies', () {
      final controller = ToastController();
      controller.show('a', LogLevel.info);
      final id = controller.visible.single.id;
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.dismiss(id);
      expect(controller.visible, isEmpty);
      expect(notifications, 1);

      controller.dismiss(id);
      expect(
        notifications,
        1,
        reason: 'dismissing a gone toast does not notify',
      );
      controller.dispose();
    });

    test('the visible view is unmodifiable', () {
      final controller = ToastController()..show('a', LogLevel.info);
      expect(() => controller.visible.clear(), throwsUnsupportedError);
      controller.dispose();
    });
  });
}
