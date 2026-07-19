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
      ValueChanged<String>? onRename,
      VoidCallback? onRemove,
      List<double> outputPeaks = const <double>[],
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
              outputPeaks: outputPeaks,
              onVolumeChanged: onVolumeChanged ?? (_) {},
              onVolumeChangeStart: onVolumeChangeStart,
              onVolumeChangeEnd: onVolumeChangeEnd,
              onMuteToggle: onMuteToggle,
              onSoloToggle: onSoloToggle,
              onRename: onRename,
              onRemove: onRemove,
            ),
          ),
        ),
      );
    }

    testWidgets('renders one meter bar per output when given output peaks', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          name: 'master',
          isMaster: true,
          outputPeaks: const [0.2, 0.5, 0.9],
        ),
      );

      expect(find.byKey(ChannelStrip.outputMeterKey(0)), findsOneWidget);
      expect(find.byKey(ChannelStrip.outputMeterKey(1)), findsOneWidget);
      expect(find.byKey(ChannelStrip.outputMeterKey(2)), findsOneWidget);
      expect(find.byKey(ChannelStrip.outputMeterKey(3)), findsNothing);
    });

    testWidgets('renders no per-output bars when output peaks are empty', (
      tester,
    ) async {
      await tester.pumpWidget(host(name: 'pad'));

      expect(find.byKey(ChannelStrip.outputMeterKey(0)), findsNothing);
    });

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

    testWidgets('no remove control when onRemove is null', (tester) async {
      await tester.pumpWidget(host(name: 'pad'));

      expect(find.byKey(ChannelStrip.removeButtonKey), findsNothing);
    });

    testWidgets('the remove control calls onRemove', (tester) async {
      var removes = 0;
      await tester.pumpWidget(host(name: 'pad', onRemove: () => removes++));

      expect(find.byKey(ChannelStrip.removeButtonKey), findsOneWidget);
      await tester.tap(find.byKey(ChannelStrip.removeButtonKey));
      await tester.pump();

      expect(removes, 1);
    });

    testWidgets('a plain header name is not editable without onRename', (
      tester,
    ) async {
      await tester.pumpWidget(host(name: 'pad'));

      // Tapping the label does nothing — no text field appears.
      await tester.tap(find.text('pad'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('inline-editing the header name commits through onRename', (
      tester,
    ) async {
      String? renamedTo;
      await tester.pumpWidget(
        host(name: 'pad', onRename: (n) => renamedTo = n),
      );

      // Tap the name to enter edit mode, type a new name, commit with Enter.
      await tester.tap(find.text('pad'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'lead synth');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(renamedTo, 'lead synth');
    });
  });
}
