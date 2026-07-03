import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/smf/smf_reader.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/midi/fake_midi_file_io.dart';

/// End-to-end tempo-locking through the real workstation (issue #61).
///
/// The `domain · drum @ 124` chip in the default chain is a real
/// [DomainSubscriptionTransform] now: it tempo-locks the 120 BPM demo phrase
/// to the `drum` domain @ 124, compressing every beat by `120 / 124`. Driving
/// the real app — real navigation, real sidebar chip toggles, real SMF
/// encoding — the exported note timings must scale by exactly that ratio when
/// the chip is on versus off. The downstream `quantize` chip is toggled off
/// first so it can't re-snap the compressed (now off-grid) notes and muddy the
/// ratio; a fake [FakeMidiFileIo] stands in for the native save dialog only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: the domain chip tempo-locks the exported clip', (
    tester,
  ) async {
    final fakeIo = FakeMidiFileIo();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(
      PhiApp(engine: engine, session: session, midiFileIo: fakeIo),
    );
    await tester.pumpAndSettle();

    // Open the MIDI surface; the seed chain has the domain chip active.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.text('domain · drum @ 124'), findsOneWidget);

    // Turn quantize off so the (now off-grid) compressed notes aren't snapped
    // back — isolating the domain subscription's clean tempo scale.
    await tester.tap(find.text('quantize · gravity 0.6'));
    await tester.pumpAndSettle();

    // Export with the domain chip on: the tempo-locked (compressed) timing.
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 1);
    final locked = const SmfReader().read(fakeIo.savedBytes!).notes;
    expect(locked, hasLength(10));

    // Toggle the domain chip off and export again: the unlocked reference
    // timing (the phrase as authored at 120 BPM).
    await tester.tap(find.text('domain · drum @ 124'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 2);
    final unlocked = const SmfReader().read(fakeIo.savedBytes!).notes;
    expect(unlocked, hasLength(10));

    // Same notes, just rescaled in time — compare them start-sorted. Every
    // locked start/duration is the unlocked one times 120/124: the chip is
    // live, not cosmetic. Tolerance covers SMF integer-tick rounding.
    const ratio = 120 / 124;
    final lockedStarts = locked.map((n) => n.start).toList()..sort();
    final unlockedStarts = unlocked.map((n) => n.start).toList()..sort();
    final lockedDurations = locked.map((n) => n.duration).toList()..sort();
    final unlockedDurations = unlocked.map((n) => n.duration).toList()..sort();

    for (var i = 0; i < unlockedStarts.length; i++) {
      expect(lockedStarts[i], closeTo(unlockedStarts[i] * ratio, 0.01));
      expect(lockedDurations[i], closeTo(unlockedDurations[i] * ratio, 0.01));
    }
    // And the compression is real — the phrase genuinely ends sooner.
    expect(lockedStarts.last, lessThan(unlockedStarts.last));

    session.dispose();
    await engine.dispose();
  });
}
