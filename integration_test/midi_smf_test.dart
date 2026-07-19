import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/smf/smf_reader.dart';
import 'package:phi/domain/midi/smf/smf_writer.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/midi/fake_midi_file_io.dart';

/// End-to-end SMF import/export through the real workstation (issue #30).
///
/// Drives the real [PhiApp] — real navigation, fonts, layout — with a fake
/// [FakeMidiFileIo] standing in for the native open/save dialogs (an
/// un-fakeable OS surface). The byte↔clip codec and the surface wiring are
/// exercised for real: importing rewrites the live clip and repaints the roll,
/// and exporting encodes the chain's *transformed* output back to bytes that
/// round-trip. The OS drag-and-drop event itself isn't simulated here — it
/// shares the very same `_importBytes` path the IMPORT button drives.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  List<MidiNote> sortNotes(List<MidiNote> notes) =>
      List<MidiNote>.of(notes)..sort((a, b) {
        if (a.start != b.start) return a.start.compareTo(b.start);
        return a.pitch.compareTo(b.pitch);
      });

  testWidgets('midi: import a clip then export its transformed output', (
    tester,
  ) async {
    // A 3-note clip, distinct from the seeded 10-note "phrase A". Velocities
    // are multiples of 1/127 and timings sit on a 1/16 grid so the round trip
    // is byte-exact.
    final importClip = MidiClip(
      bars: 2,
      notes: const [
        MidiNote(pitch: 62, start: 0.0, duration: 0.5, velocity: 100 / 127),
        MidiNote(pitch: 65, start: 1.0, duration: 0.25, velocity: 64 / 127),
        MidiNote(pitch: 69, start: 2.0, duration: 1.0, velocity: 120 / 127),
      ],
    );
    final fakeIo = FakeMidiFileIo(
      openBytes: const SmfWriter().write(importClip),
    );

    // A wired MIDI gateway means the engine builds its player, so the shell
    // sources the chain/editor from engine.midi — giving the test a handle on
    // the live transformed output to compare the export against.
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

    // Open the MIDI surface; it starts on the seeded 10-note clip. The header
    // shows the clip's registry address leaf — `clip.phrase_a` (issue #184) —
    // not a free-form display name.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.text('MIDI · PHRASE_A'), findsOneWidget);
    expect(find.textContaining('10 notes'), findsOneWidget);

    // Turn the domain subscription off (issue #61): it tempo-locks the clip by
    // 120/124, pushing timings off the 1/16 grid so they can't round-trip
    // byte-exact through integer SMF ticks. This test is about the import/export
    // codec, not tempo-locking — the domain chip has its own e2e test.
    await tester.tap(find.text('domain · drum @ 124'));
    await tester.pumpAndSettle();

    // Import: the header IMPORT button pulls bytes from the fake dialog and
    // swaps them into the live clip in place. The roll repaints with the new
    // content; the header keeps the clip's address-leaf name — import mutates
    // the same entity now that the clip carries no display name (issue #184;
    // import-as-new-entity lands with the library in #185).
    await tester.tap(find.text('IMPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.openCalls, 1);
    expect(find.text('MIDI · PHRASE_A'), findsOneWidget);
    expect(find.textContaining('3 notes'), findsOneWidget);
    expect(engine.midi.chain.source.notes.length, 3);

    // Export: the header EXPORT button encodes the chain's transformed output
    // (source transforms still active) and hands the bytes to the fake dialog.
    // The file is named from the clip's address leaf (issue #184).
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 1);
    expect(fakeIo.savedName, 'phrase_a.mid');
    expect(fakeIo.savedBytes, isNotNull);

    // The exported bytes are valid SMF and decode back to exactly the chain's
    // transformed output — proving the whole export path, not just the codec.
    final decoded = const SmfReader().read(fakeIo.savedBytes!);
    expect(sortNotes(decoded.notes), sortNotes(engine.midi.chain.output));

    session.dispose();
    await engine.dispose();
  });
}
