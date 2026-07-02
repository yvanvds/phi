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

/// End-to-end structural looping through the real workstation (issue #34).
///
/// The `loop · 4 bars` chip in the default chain is a real [LoopTransform]
/// now (shipped inactive, mirroring the old stub), so flipping it on must
/// double the exported note count through the real app's export path: real
/// navigation, real sidebar chip toggle, real SMF encoding. A fake
/// [FakeMidiFileIo] stands in for the native save dialog only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: the loop chip doubles the exported clip', (tester) async {
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

    // Open the MIDI surface; the seeded chain has the loop chip inactive.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.text('loop · 4 bars'), findsOneWidget);

    // Export with the loop off: the baseline, unlooped note count.
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 1);
    final unlooped = const SmfReader().read(fakeIo.savedBytes!).notes;
    expect(unlooped, isNotEmpty);

    // Toggle the loop chip on and export again: every pitch appears exactly
    // twice as often — the chip is live in the real app, not cosmetic.
    await tester.tap(find.text('loop · 4 bars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 2);
    final looped = const SmfReader().read(fakeIo.savedBytes!).notes;

    expect(looped.length, unlooped.length * 2);
    final unloopedCounts = <int, int>{};
    for (final n in unlooped) {
      unloopedCounts[n.pitch] = (unloopedCounts[n.pitch] ?? 0) + 1;
    }
    final loopedCounts = <int, int>{};
    for (final n in looped) {
      loopedCounts[n.pitch] = (loopedCounts[n.pitch] ?? 0) + 1;
    }
    for (final entry in unloopedCounts.entries) {
      expect(loopedCounts[entry.key], entry.value * 2);
    }

    session.dispose();
    await engine.dispose();
  });
}
