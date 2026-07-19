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

/// End-to-end voice routing through the real workstation (issue #33, #205).
///
/// The `route · voice.default` chip in the default chain is a real
/// [VoiceRoutingTransform] that now assigns each note a `voice.` address rather
/// than a bare channel (issue #205). Its effect — every note carrying
/// `voice.default` when active, and falling back to the unrouted `null` voice
/// when toggled off — must show up on the live interpreted output through the
/// real app: real navigation, real sidebar chip toggle. The routed clip also
/// still exports to SMF (the default voice maps to channel 0). A fake
/// [FakeMidiFileIo] stands in for the native save dialog only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: the route chip re-voices the interpreted clip', (
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

    // Open the MIDI surface; the seeded chain has the route chip active.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.text('route · voice.default'), findsOneWidget);

    // With routing active every interpreted note carries voice.default — the
    // chip is live in the real app.
    final routedOutput = engine.midi.chain.output;
    expect(routedOutput, isNotEmpty);
    for (final note in routedOutput) {
      expect(note.voice, 'voice.default');
    }

    // The routed clip still exports (voice.default → SMF channel 0), and
    // re-imports as voice.default.
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 1);
    final exported = const SmfReader().read(fakeIo.savedBytes!);
    expect(exported.notes, isNotEmpty);
    for (final note in exported.notes) {
      expect(note.voice, 'voice.default');
    }

    // Toggle the chip off in the sidebar: notes fall back to the unrouted
    // `null` voice — the toggle is wired, not cosmetic.
    await tester.tap(find.text('route · voice.default'));
    await tester.pumpAndSettle();
    final unroutedOutput = engine.midi.chain.output;
    expect(unroutedOutput, isNotEmpty);
    for (final note in unroutedOutput) {
      expect(note.voice, isNull);
    }

    session.dispose();
    await engine.dispose();
  });
}
