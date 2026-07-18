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

    testWidgets('the master strip has no remove control', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixSurface(engine: engine)),
        ),
      );

      // Only the master is present and it is never removable.
      expect(find.byType(ChannelStrip), findsOneWidget);
      expect(find.byKey(ChannelStrip.removeButtonKey), findsNothing);
    });

    testWidgets('removing a user strip drops it from the rack', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixSurface(engine: engine)),
        ),
      );

      await tester.tap(find.text('+'));
      await tester.pump();
      expect(engine.channels.value, hasLength(1));
      expect(find.byType(ChannelStrip), findsNWidgets(2));

      await tester.tap(find.byKey(ChannelStrip.removeButtonKey));
      await tester.pump();

      expect(engine.channels.value, isEmpty);
      expect(find.byType(ChannelStrip), findsOneWidget); // master only
    });

    testWidgets('inline-renaming a user strip renames the channel', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MixSurface(engine: engine)),
        ),
      );

      await tester.tap(find.text('+'));
      await tester.pump();
      // A strip is named by its address leaf (issue #166), so the default
      // 'ch 1' shows as its slug 'ch_1'.
      expect(engine.channels.value.single.name, 'ch_1');

      // Tap the strip's name to edit, type a new one, commit with Enter.
      await tester.tap(find.text('ch_1'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'lead');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(engine.channels.value.single.name, 'lead');
      expect(find.text('lead'), findsOneWidget);
    });
  });
}
