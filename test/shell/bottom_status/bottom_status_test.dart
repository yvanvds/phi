import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/state/engine_telemetry.dart';
import 'package:phi/shell/bottom_status/bottom_status.dart';
import 'package:phi/shell/bottom_status/midi_activity_dot.dart';

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

    Future<void> pump(WidgetTester tester) async {
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
          missedCallbacks: 2,
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
      expect(find.text('2'), findsOneWidget);
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
