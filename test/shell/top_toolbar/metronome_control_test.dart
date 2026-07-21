import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/time_domains/time_domain.dart';
import 'package:phi/domain/time_domains/time_domain_registry.dart';
import 'package:phi/engine/state/metronome_controller.dart';
import 'package:phi/shell/top_toolbar/metronome_control.dart';
import 'package:phi/shell/top_toolbar/metronome_popover.dart';

import '../../engine/test_doubles/fake_midi_gateway.dart';

void main() {
  late FakeMidiGateway gateway;
  late MetronomeController controller;

  final registry = TimeDomainRegistry(const [
    TimeDomain(name: 'drum', tempo: 120),
    TimeDomain(name: 'pad', tempo: 60),
  ]);

  setUp(() {
    gateway = FakeMidiGateway();
    controller = MetronomeController(
      gateway: gateway,
      domains: () => registry,
      sessionTempo: () => 100,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MetronomeControl(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPopover(WidgetTester tester) async {
    await tester.tap(find.byKey(MetronomeControl.popoverButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(MetronomePopover), findsOneWidget);
  }

  testWidgets('the toggle enables and disables the click', (tester) async {
    await pump(tester);
    expect(controller.enabled, isFalse);

    await tester.tap(find.byKey(MetronomeControl.toggleKey));
    await tester.pumpAndSettle();
    expect(controller.enabled, isTrue);
    expect(gateway.transport, isNotNull);
    expect(gateway.transport!.isPlaying, isTrue);

    await tester.tap(find.byKey(MetronomeControl.toggleKey));
    await tester.pumpAndSettle();
    expect(controller.enabled, isFalse);
    expect(gateway.transport!.isPlaying, isFalse);
  });

  testWidgets('the popover opens and closes', (tester) async {
    await pump(tester);
    expect(find.byType(MetronomePopover), findsNothing);

    await openPopover(tester);

    // An outside tap dismisses it.
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.byType(MetronomePopover), findsNothing);
  });

  testWidgets('the domain picker binds the click to a domain', (tester) async {
    await pump(tester);
    await openPopover(tester);
    expect(controller.domainName, isNull);

    // Open the domain PhiSelect and pick `drum`.
    await tester.tap(find.byKey(MetronomePopover.domainPickerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('drum · 120 bpm'));
    await tester.pumpAndSettle();

    expect(controller.domainName, 'drum');
  });

  testWidgets('the meter picker changes beats-per-bar', (tester) async {
    await pump(tester);
    await openPopover(tester);
    expect(controller.beatsPerBar, 4);

    await tester.tap(find.byKey(MetronomePopover.beatsPickerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 / beat'));
    await tester.pumpAndSettle();

    expect(controller.beatsPerBar, 3);
  });

  testWidgets('the accent toggle flips the downbeat accent', (tester) async {
    await pump(tester);
    await openPopover(tester);
    expect(controller.accentDownbeat, isTrue);

    await tester.tap(find.byKey(MetronomePopover.accentToggleKey));
    await tester.pumpAndSettle();

    expect(controller.accentDownbeat, isFalse);
  });

  testWidgets('the volume slider lowers the click level', (tester) async {
    await pump(tester);
    await openPopover(tester);
    final before = controller.volume;

    await tester.drag(
      find.byKey(MetronomePopover.volumeSliderKey),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(controller.volume, lessThan(before));
  });
}
