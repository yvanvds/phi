import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/smf/smf_reader.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/midi/fake_midi_file_io.dart';

/// End-to-end typed parameter editing through the real workstation (issue #95).
///
/// The seeded `route · voice.default` chip is a real [VoiceRoutingTransform].
/// Opening its typed editor from the chip context menu and changing the rule's
/// target **voice** must survive the real app's export path — real navigation,
/// real context menu, real dialog, real SMF encoding (the voice ↔ channel
/// mapping, issue #205) — proving the editor mutates the live chain, not a copy.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: editing the route chip re-voices the exported clip', (
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

    // Open the MIDI surface; the seeded route rule sends every note to
    // voice.default.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    final routeChip = find.ancestor(
      of: find.text('route · voice.default'),
      matching: find.byType(TransformChip),
    );
    expect(routeChip, findsOneWidget);

    // Right-click the chip and open its typed routing editor.
    await tester.tap(routeChip, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('edit parameters…'));
    await tester.pumpAndSettle();

    // The rule's fields are min, max, voice — retarget the voice. `voice.channel_5`
    // exports to SMF channel 4 and re-imports back to the same voice.
    final voiceField = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .at(2);
    await tester.enterText(voiceField, 'voice.channel_5');
    await tester.pump();
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();

    // Export: every decoded note now carries the edited voice (round-tripped
    // through its SMF channel), proving the typed editor mutated the live chain
    // end-to-end.
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 1);
    final exported = _decodeVoices(fakeIo);
    expect(exported, isNotEmpty);
    for (final voice in exported) {
      expect(voice, 'voice.channel_5');
    }

    session.dispose();
    await engine.dispose();
  });
}

/// The routed voice of every note in the last saved SMF blob (the reader maps
/// each file channel back onto its voice, issue #205).
List<String?> _decodeVoices(FakeMidiFileIo io) {
  final notes = const SmfReader().read(io.savedBytes!).notes;
  return [for (final n in notes) n.voice];
}
