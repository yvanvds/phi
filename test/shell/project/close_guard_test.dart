import 'dart:ui' show AppExitResponse;

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/shell/project/close_decision.dart';
import 'package:phi/shell/project/close_guard.dart';

void main() {
  group('CloseGuard', () {
    test('a clean project exits without asking', () async {
      var confirmed = false;
      final guard = CloseGuard(
        isDirty: () => false,
        confirm: () async {
          confirmed = true;
          return CloseDecision.cancel;
        },
        save: () async {},
      );
      expect(await guard.onExitRequested(), AppExitResponse.exit);
      expect(confirmed, isFalse);
    });

    test('save then exit when the save succeeds', () async {
      var dirty = true;
      var saved = false;
      final guard = CloseGuard(
        isDirty: () => dirty,
        confirm: () async => CloseDecision.save,
        save: () async {
          saved = true;
          dirty = false; // the save cleared the pending changes
        },
      );
      expect(await guard.onExitRequested(), AppExitResponse.exit);
      expect(saved, isTrue);
    });

    test('a cancelled save (still dirty) vetoes the exit', () async {
      final guard = CloseGuard(
        isDirty: () => true, // never becomes clean → the save was cancelled
        confirm: () async => CloseDecision.save,
        save: () async {},
      );
      expect(await guard.onExitRequested(), AppExitResponse.cancel);
    });

    test('discard exits without saving', () async {
      var saved = false;
      final guard = CloseGuard(
        isDirty: () => true,
        confirm: () async => CloseDecision.discard,
        save: () async => saved = true,
      );
      expect(await guard.onExitRequested(), AppExitResponse.exit);
      expect(saved, isFalse);
    });

    test('keep-working vetoes the exit', () async {
      final guard = CloseGuard(
        isDirty: () => true,
        confirm: () async => CloseDecision.cancel,
        save: () async {},
      );
      expect(await guard.onExitRequested(), AppExitResponse.cancel);
    });
  });
}
