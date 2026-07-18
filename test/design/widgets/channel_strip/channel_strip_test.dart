import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';

void main() {
  group('ChannelStrip', () {
    Widget host({
      String name = 'drum',
      double volume = 0.5,
      double peak = 0.0,
      bool muted = false,
      bool soloed = false,
      bool isMaster = false,
      ValueChanged<double>? onVolumeChanged,
      VoidCallback? onVolumeChangeStart,
      VoidCallback? onVolumeChangeEnd,
      VoidCallback? onMuteToggle,
      VoidCallback? onSoloToggle,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChannelStrip(
              name: name,
              volume: volume,
              peak: peak,
              muted: muted,
              soloed: soloed,
              voiceColor: PhiColors.voice1,
              voiceGlow: PhiColors.voice1Soft,
              isMaster: isMaster,
              onVolumeChanged: onVolumeChanged ?? (_) {},
              onVolumeChangeStart: onVolumeChangeStart,
              onVolumeChangeEnd: onVolumeChangeEnd,
              onMuteToggle: onMuteToggle,
              onSoloToggle: onSoloToggle,
            ),
          ),
        ),
      );
    }

    testWidgets('renders name and mute/solo buttons for a user strip', (
      tester,
    ) async {
      await tester.pumpWidget(host(name: 'pad'));

      expect(find.text('pad'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
    });

    testWidgets('hides mute/solo buttons on the master strip', (tester) async {
      await tester.pumpWidget(host(name: 'master', isMaster: true));

      expect(find.text('master'), findsOneWidget);
      expect(find.text('M'), findsNothing);
      expect(find.text('S'), findsNothing);
    });

    testWidgets('reads "muted" instead of a dB value when muted', (
      tester,
    ) async {
      await tester.pumpWidget(host(peak: 0.5, muted: true));

      expect(find.text('muted'), findsOneWidget);
    });

    testWidgets('tap near the bottom of the fader emits a small volume', (
      tester,
    ) async {
      double? captured;
      await tester.pumpWidget(
        host(volume: 1.0, onVolumeChanged: (v) => captured = v),
      );

      final faderRect = tester.getRect(
        find.byKey(ChannelStrip.faderHitAreaKey),
      );
      await tester.tapAt(Offset(faderRect.center.dx, faderRect.bottom - 5));
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!, lessThan(0.1));
    });

    testWidgets('drag upward emits an increasing volume', (tester) async {
      final emitted = <double>[];
      await tester.pumpWidget(host(volume: 0.0, onVolumeChanged: emitted.add));

      final faderRect = tester.getRect(
        find.byKey(ChannelStrip.faderHitAreaKey),
      );
      final start = Offset(faderRect.center.dx, faderRect.bottom - 5);
      final end = Offset(faderRect.center.dx, faderRect.top + 5);

      final g = await tester.startGesture(start);
      await g.moveTo(end);
      await g.up();
      await tester.pump();

      expect(emitted, isNotEmpty);
      expect(emitted.last, greaterThan(0.8));
    });

    testWidgets('a fader drag brackets the volume changes with start/end', (
      tester,
    ) async {
      final events = <String>[];
      await tester.pumpWidget(
        host(
          volume: 0.0,
          onVolumeChanged: (v) => events.add('change'),
          onVolumeChangeStart: () => events.add('start'),
          onVolumeChangeEnd: () => events.add('end'),
        ),
      );

      final faderRect = tester.getRect(
        find.byKey(ChannelStrip.faderHitAreaKey),
      );
      final g = await tester.startGesture(
        Offset(faderRect.center.dx, faderRect.bottom - 5),
      );
      await g.moveTo(Offset(faderRect.center.dx, faderRect.center.dy));
      await g.moveTo(Offset(faderRect.center.dx, faderRect.top + 5));
      await g.up();
      await tester.pump();

      // Exactly one start and one end bracket the (many) change events.
      expect(events.first, 'start');
      expect(events.last, 'end');
      expect(events.where((e) => e == 'start'), hasLength(1));
      expect(events.where((e) => e == 'end'), hasLength(1));
      expect(events.where((e) => e == 'change'), isNotEmpty);
    });

    testWidgets('a click-to-set brackets its single change with start/end', (
      tester,
    ) async {
      final events = <String>[];
      await tester.pumpWidget(
        host(
          volume: 1.0,
          onVolumeChanged: (v) => events.add('change'),
          onVolumeChangeStart: () => events.add('start'),
          onVolumeChangeEnd: () => events.add('end'),
        ),
      );

      final faderRect = tester.getRect(
        find.byKey(ChannelStrip.faderHitAreaKey),
      );
      await tester.tapAt(Offset(faderRect.center.dx, faderRect.bottom - 5));
      await tester.pump();

      expect(events, ['start', 'change', 'end']);
    });

    testWidgets('mute button calls onMuteToggle', (tester) async {
      var muteTaps = 0;
      await tester.pumpWidget(host(onMuteToggle: () => muteTaps++));

      await tester.tap(find.text('M'));
      await tester.pump();

      expect(muteTaps, 1);
    });

    testWidgets('solo button calls onSoloToggle', (tester) async {
      var soloTaps = 0;
      await tester.pumpWidget(host(onSoloToggle: () => soloTaps++));

      await tester.tap(find.text('S'));
      await tester.pump();

      expect(soloTaps, 1);
    });
  });
}
