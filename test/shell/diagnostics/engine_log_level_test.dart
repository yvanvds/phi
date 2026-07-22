import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/shell/diagnostics/engine_log_level.dart';

void main() {
  group('engineLogLevel', () {
    test('plain progress is info', () {
      expect(engineLogLevel('Audio device opened at 48000 Hz'), LogLevel.info);
      expect(engineLogLevel('Engine started'), LogLevel.info);
    });

    test('error / failure wording is error', () {
      expect(engineLogLevel('ERROR: could not load DSP'), LogLevel.error);
      expect(engineLogLevel('device open failed'), LogLevel.error);
      expect(engineLogLevel('Fatal: out of memory'), LogLevel.error);
    });

    test('warning wording is warning', () {
      expect(engineLogLevel('Warning: buffer underrun'), LogLevel.warning);
      expect(engineLogLevel('warn: high cpu load'), LogLevel.warning);
    });

    test('classification is case-insensitive', () {
      expect(engineLogLevel('Error opening file'), LogLevel.error);
      expect(engineLogLevel('WARNING queue full'), LogLevel.warning);
    });
  });
}
