import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/session/transport_state.dart';

void main() {
  group('SessionState', () {
    late SessionState session;

    setUp(() => session = SessionState());
    tearDown(() => session.dispose());

    test('defaults to idle transport, projection off, untitled scene', () {
      expect(session.transport.value, TransportState.idle);
      expect(session.isPlaying, isFalse);
      expect(session.projection.value, isFalse);
      expect(session.sceneName.value, 'untitled');
    });

    test('play / stop flip the transport state and isPlaying', () {
      session.play();
      expect(session.transport.value, TransportState.playing);
      expect(session.isPlaying, isTrue);

      session.stop();
      expect(session.transport.value, TransportState.idle);
      expect(session.isPlaying, isFalse);
    });

    test('toggleProjection flips the projection flag', () {
      session.toggleProjection();
      expect(session.projection.value, isTrue);
      session.toggleProjection();
      expect(session.projection.value, isFalse);
    });

    test('renameScene trims and accepts non-empty names', () {
      session.renameScene('  drone study  ');
      expect(session.sceneName.value, 'drone study');
    });

    test('renameScene ignores empty / whitespace-only input', () {
      session.renameScene('first name');
      session.renameScene('   ');
      expect(session.sceneName.value, 'first name');
    });

    test('initial scene name can be overridden', () {
      final custom = SessionState(initialSceneName: 'hello');
      expect(custom.sceneName.value, 'hello');
      custom.dispose();
    });

    test('listeners fire on every notifier change', () {
      var transportTicks = 0;
      var projectionTicks = 0;
      var nameTicks = 0;
      session.transport.addListener(() => transportTicks++);
      session.projection.addListener(() => projectionTicks++);
      session.sceneName.addListener(() => nameTicks++);

      session.play();
      session.toggleProjection();
      session.renameScene('new');

      expect(transportTicks, 1);
      expect(projectionTicks, 1);
      expect(nameTicks, 1);
    });
  });
}
