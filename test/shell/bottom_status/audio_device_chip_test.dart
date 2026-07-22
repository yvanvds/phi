import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/shell/bottom_status/audio_device_chip.dart';
import 'package:phi/shell/diagnostics/audio_device_health.dart';

/// Widget coverage for [AudioDeviceChip] (design `docs/design/diagnostics.md`
/// §5): the ok → reconnecting → lost → ok look walk and the click-through.
void main() {
  Future<void> pump(
    WidgetTester tester,
    ValueNotifier<AudioDeviceHealth> health, {
    VoidCallback? onTap,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AudioDeviceChip(health: health, onTap: onTap),
          ),
        ),
      ),
    );
  }

  Color chipAccent(WidgetTester tester) {
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(AudioDeviceChip.chipKey),
        matching: find.byType(Icon),
      ),
    );
    return icon.color!;
  }

  testWidgets('renders the ok look — calm and muted', (tester) async {
    final health = ValueNotifier(AudioDeviceHealth.ok);
    addTearDown(health.dispose);
    await pump(tester, health);

    expect(find.text('AUDIO'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(chipAccent(tester), PhiColors.fg2);
  });

  testWidgets('walks ok → reconnecting → lost → ok with the right look', (
    tester,
  ) async {
    final health = ValueNotifier(AudioDeviceHealth.ok);
    addTearDown(health.dispose);
    await pump(tester, health);

    expect(
      find.text(AudioDeviceChip.labelFor(AudioDeviceHealth.ok)),
      findsOneWidget,
    );
    expect(chipAccent(tester), PhiColors.fg2);

    health.value = AudioDeviceHealth.reconnecting;
    await tester.pump();
    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(chipAccent(tester), PhiColors.warm);

    health.value = AudioDeviceHealth.lost;
    await tester.pump();
    expect(find.text('NO AUDIO'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(chipAccent(tester), PhiColors.hot);

    health.value = AudioDeviceHealth.ok;
    await tester.pump();
    expect(find.text('AUDIO'), findsOneWidget);
    expect(chipAccent(tester), PhiColors.fg2);
  });

  testWidgets('a tap fires the click-through (opens settings AUDIO)', (
    tester,
  ) async {
    final health = ValueNotifier(AudioDeviceHealth.lost);
    addTearDown(health.dispose);
    var taps = 0;
    await pump(tester, health, onTap: () => taps++);

    await tester.tap(find.byKey(AudioDeviceChip.chipKey));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('is inert when no click-through is wired', (tester) async {
    final health = ValueNotifier(AudioDeviceHealth.ok);
    addTearDown(health.dispose);
    await pump(tester, health);

    // No onTap: tapping is a harmless no-op (no crash).
    await tester.tap(find.byKey(AudioDeviceChip.chipKey));
    await tester.pump();
    expect(find.byKey(AudioDeviceChip.chipKey), findsOneWidget);
  });
}
