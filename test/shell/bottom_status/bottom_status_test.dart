import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/state/engine_telemetry.dart';
import 'package:phi/shell/bottom_status/bottom_status.dart';
import 'package:phi/shell/bottom_status/midi_activity_dot.dart';
import 'package:phi/shell/bottom_status/panic_button.dart';
import 'package:phi/shell/bottom_status/status_chip.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  group('BottomStatus formatters', () {
    test('formatCpu shows percentage with one decimal', () {
      expect(BottomStatus.formatCpu(0), '0.0 %');
      expect(BottomStatus.formatCpu(0.14), '14.0 %');
      expect(BottomStatus.formatCpu(1), '100.0 %');
    });

    test('formatBuffer shows "frames / kHz" and dash for unopened device', () {
      expect(BottomStatus.formatBuffer(128, 48000), '128 / 48k');
      expect(BottomStatus.formatBuffer(256, 44100), '256 / 44k');
      expect(BottomStatus.formatBuffer(0, 0), '—');
      expect(BottomStatus.formatBuffer(128, 0), '—');
    });

    test('formatLatency shows ms with one decimal and dash for zero', () {
      expect(BottomStatus.formatLatency(5.333), '5.3 ms');
      expect(BottomStatus.formatLatency(0), '—');
    });
  });

  group('BottomStatus widget', () {
    late SessionState session;
    late StreamController<EngineTelemetry> telemetry;
    late StreamController<void> midi;

    setUp(() {
      session = SessionState();
      telemetry = StreamController<EngineTelemetry>.broadcast();
      midi = StreamController<void>.broadcast();
    });

    tearDown(() async {
      session.dispose();
      await telemetry.close();
      await midi.close();
    });

    // The status strip is a full-width bar: the LIVE dot + panic button + four
    // telemetry chips + the MIDI dot need more than the 800px test default, so
    // size the surface to a performance width (as the real-app tests do).
    Future<void> widenSurface(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    Future<void> pump(WidgetTester tester) async {
      await widenSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BottomStatus.fromStreams(
              telemetry: telemetry.stream,
              midiActivity: midi.stream,
              session: session,
            ),
          ),
        ),
      );
    }

    testWidgets('renders CPU, BUF, LAT, DROPS chips with live telemetry', (
      tester,
    ) async {
      await pump(tester);
      telemetry.add(
        const EngineTelemetry(
          cpuLoad: 0.14,
          audioStalls: 2,
          // The raw device-stall gauge is *not* what DROPS shows (issue #350):
          // a healthy device sits at 1 here, and the chip must ignore it.
          deviceStallTicks: 1,
          peakStallTicks: 9,
          masterPeak: 0,
          sampleRate: 48000,
          bufferSize: 128,
          latencyMs: 5.333,
        ),
      );
      await tester.pump();

      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('14.0 %'), findsOneWidget);
      expect(find.text('BUF'), findsOneWidget);
      expect(find.text('128 / 48k'), findsOneWidget);
      expect(find.text('LAT'), findsOneWidget);
      expect(find.text('5.3 ms'), findsOneWidget);
      expect(find.text('DROPS'), findsOneWidget);
      // The latched stall-event count, not the raw gauge (1) or its peak (9).
      expect(find.text('2'), findsOneWidget);
      expect(find.text('9'), findsNothing);
    });

    testWidgets('DROPS stays at 0 while the raw stall gauge flickers', (
      tester,
    ) async {
      // The issue-#350 regression: at a 16 ms control tick a healthy device
      // reads `1` on the engine's gauge roughly once a second. The chip is fed
      // the interpreted count, so it must never move for those.
      await pump(tester);
      for (final gauge in [0, 1, 0, 1, 1, 0]) {
        telemetry.add(
          EngineTelemetry(
            cpuLoad: 0.1,
            audioStalls: 0,
            deviceStallTicks: gauge,
            peakStallTicks: 1,
            masterPeak: 0,
            sampleRate: 48000,
            bufferSize: 1024,
            latencyMs: 21.3,
          ),
        );
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(StatusChip),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('shows em-dash placeholders before a device is open', (
      tester,
    ) async {
      await pump(tester);
      // Default initialData is EngineTelemetry.zero — no need to emit.

      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('mounts a MIDI activity dot wired to the activity stream', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byType(MidiActivityDot), findsOneWidget);
      expect(find.text('MIDI'), findsOneWidget);
    });

    // Issue #400: with a device open the BUF / LAT chips carry real values
    // instead of the `—` placeholder, and the strip no longer fits a narrow
    // window. It must degrade to a horizontal scroll, not assert.
    testWidgets('scrolls instead of overflowing in a narrow window', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(560, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BottomStatus.fromStreams(
              telemetry: telemetry.stream,
              midiActivity: midi.stream,
              session: session,
            ),
          ),
        ),
      );
      telemetry.add(
        const EngineTelemetry(
          cpuLoad: 0.14,
          audioStalls: 0,
          deviceStallTicks: 0,
          peakStallTicks: 0,
          masterPeak: 0,
          sampleRate: 44100,
          bufferSize: 256,
          latencyMs: 5.8,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Everything is still mounted — scrolled out of view, not dropped.
      expect(find.text('256 / 44k'), findsOneWidget);
      expect(find.text('5.8 ms'), findsOneWidget);
      // The readouts are genuinely wider than the room they were given, i.e.
      // this window really does exercise the scrolling path.
      expect(
        tester.getSize(find.byType(SingleChildScrollView)).width,
        lessThan(tester.getSize(find.byKey(BottomStatus.readoutsKey)).width),
      );
    });

    testWidgets('pins the readouts to the right when the window has room', (
      tester,
    ) async {
      await pump(tester);
      telemetry.add(
        const EngineTelemetry(
          cpuLoad: 0.14,
          audioStalls: 0,
          deviceStallTicks: 0,
          peakStallTicks: 0,
          masterPeak: 0,
          sampleRate: 44100,
          bufferSize: 256,
          latencyMs: 5.8,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The strip still fills the bar and the readouts sit flush against its
      // right edge — the common layout is unchanged by the scroll wrapper.
      expect(tester.getSize(find.byType(Row).first).width, 1200);
      expect(
        tester.getBottomRight(find.byKey(BottomStatus.readoutsKey)).dx,
        closeTo(1200, 0.5),
      );
    });

    testWidgets('the panic button runs onPanic (issue #264)', (tester) async {
      await widenSurface(tester);
      var panicked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BottomStatus.fromStreams(
              telemetry: telemetry.stream,
              midiActivity: midi.stream,
              session: session,
              onPanic: () => panicked++,
            ),
          ),
        ),
      );

      // Unmissable in the strip, right of the LIVE dot.
      expect(find.byKey(PanicButton.buttonKey), findsOneWidget);
      expect(find.text('PANIC'), findsOneWidget);

      await tester.tap(find.byKey(PanicButton.buttonKey));
      await tester.pump();
      expect(panicked, 1);
    });
  });

  group('MidiActivityDot', () {
    testWidgets('lights up on tick, then fades after flashDuration', (
      tester,
    ) async {
      final gateway = FakeYseGateway();
      addTearDown(() async {
        await gateway.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MidiActivityDot(
              activity: gateway.midiActivity,
              flashDuration: const Duration(milliseconds: 50),
            ),
          ),
        ),
      );

      Color dotColor() {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(MidiActivityDot),
                matching: find.byType(Container),
              )
              .first,
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      expect(dotColor(), PhiColors.fg4);

      gateway.emitMidiActivity();
      await tester.pump();
      expect(dotColor(), PhiColors.voice3);

      await tester.pump(const Duration(milliseconds: 60));
      expect(dotColor(), PhiColors.fg4);
    });
  });
}
