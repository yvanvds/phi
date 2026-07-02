import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/piano_roll_geometry.dart';
import 'package:phi/surfaces/midi/piano_roll_painter.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end microtonal pitch through the real workstation (issue #36).
///
/// A fractional MIDI pitch authored into the shared clip must survive the real
/// navigation + layout + paint path all the way to the piano-roll painter, and
/// render *between* two semitone lanes rather than snapping to one. That is the
/// visible half of microtonal support (the audible half — pitch-bend on live
/// output — is covered by the EngineMidiController unit tests).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  PianoRollPainter rollPainter(WidgetTester tester) {
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PianoRollPainter,
    );
    return tester.widget<CustomPaint>(finder.first).painter as PianoRollPainter;
  }

  testWidgets('midi: a fractional pitch paints between two lanes', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Open the MIDI surface.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    // Author a quarter-tone-sharp C4 (60.25) through the *same* editor the
    // surface paints. Gestures snap to whole semitones, so a microtonal note
    // can only arrive from a transform or a programmatic edit like this one.
    engine.midi.editor.addNote(
      const MidiNote(pitch: 60.25, start: 0.0, duration: 0.5, velocity: 0.8),
    );
    await tester.pumpAndSettle();

    // The fractional pitch reaches the painter unrounded.
    final painter = rollPainter(tester);
    final micro = painter.sourceNotes.where((n) => n.pitch == 60.25);
    expect(
      micro,
      hasLength(1),
      reason: 'the microtonal note survived to paint',
    );

    // …and it lays out strictly between the C4 (60) and C#4 (61) lane lines.
    final geo = PianoRollGeometry(
      size: const Size(400, 200),
      bars: 4,
      beatsPerBar: 4,
      minPitch: painter.minPitch,
      maxPitch: painter.maxPitch,
    );
    final y60 = geo.yForPitch(60);
    final y61 = geo.yForPitch(61);
    final yMicro = geo.yForPitch(60.25);
    expect(yMicro, lessThan(y60));
    expect(yMicro, greaterThan(y61));

    session.dispose();
    await engine.dispose();
  });
}
