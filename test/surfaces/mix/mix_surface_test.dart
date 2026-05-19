import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  group('MixSurface', () {
    late FakeYseGateway gateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      engine = PhiEngine(
        gateway,
        telemetryInterval: const Duration(milliseconds: 50),
      );
      engine.start();
    });

    tearDown(() async {
      await engine.dispose();
      await gateway.dispose();
    });

    testWidgets('renders the master strip on first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixSurface(engine: engine)),
        ),
      );

      expect(find.byType(ChannelStrip), findsOneWidget);
      expect(find.text('master'), findsOneWidget);
    });

    testWidgets('tapping + adds a user strip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixSurface(engine: engine)),
        ),
      );

      await tester.tap(find.text('+'));
      await tester.pump();

      expect(find.byType(ChannelStrip), findsNWidgets(2));
      expect(engine.channels.value, hasLength(1));
    });

    testWidgets('channel count in the header reflects user channels', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixSurface(engine: engine)),
        ),
      );

      expect(find.text('MIX · 1 CHANNELS'), findsOneWidget);

      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.tap(find.text('+'));
      await tester.pump();

      expect(find.text('MIX · 3 CHANNELS'), findsOneWidget);
    });
  });
}
