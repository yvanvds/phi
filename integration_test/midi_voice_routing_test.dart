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

/// End-to-end voice routing through the real workstation (issue #33).
///
/// The `route · osc.saw` chip in the default chain is a real
/// [VoiceRoutingTransform] now, so its effect — every note re-channelled to
/// channel 1 — must survive the real app's export path: real navigation,
/// real sidebar chip toggle, real SMF encoding. A fake [FakeMidiFileIo]
/// stands in for the native save dialog only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: the route chip re-channels the exported clip', (
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
    expect(find.text('route · osc.saw'), findsOneWidget);

    // Export the seeded phrase with routing active: every decoded note
    // carries the routed channel, proving the chip is live in the real
    // app and the channel survives the SMF bytes.
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 1);
    final routed = const SmfReader().read(fakeIo.savedBytes!);
    expect(routed.notes, isNotEmpty);
    for (final note in routed.notes) {
      expect(note.channel, 1);
    }

    // Toggle the chip off in the sidebar and export again: notes fall back
    // to the source channel 0 — the toggle is wired, not cosmetic.
    await tester.tap(find.text('route · osc.saw'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 2);
    final unrouted = const SmfReader().read(fakeIo.savedBytes!);
    for (final note in unrouted.notes) {
      expect(note.channel, 0);
    }

    session.dispose();
    await engine.dispose();
  });
}
