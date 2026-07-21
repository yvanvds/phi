import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/clip_library_controller.dart';
import 'package:phi/surfaces/midi/clip_transport_row.dart';
import 'package:phi/surfaces/midi/midi_surface.dart';

import '../../engine/test_doubles/fake_midi_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

/// The MIDI surface's **record-arm button** wired to a live session (issue #261):
/// the button arms record, arm + play starts a take, a played note is captured
/// into the edited clip, stop ends the take, and a second click disarms.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  Map<String, Object?> emptyClip() =>
      ClipDocument(source: MidiClip(bars: 2, notes: const [])).toJson();

  late FakeYseGateway yse;
  late FakeMidiGateway midiGateway;
  late PhiEngine engine;
  late ProjectRegistry registry;
  late ClipLibraryController controller;

  setUp(() {
    yse = FakeYseGateway();
    midiGateway = FakeMidiGateway();
    engine = PhiEngine(
      yse,
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 50),
    );
    engine.start(); // builds engine.midi (the record-bearing session manager)
    registry = ProjectRegistry();
    controller = ClipLibraryController(
      registry: registry,
      sessions: engine.midi,
    );
    registry.createEntity(addr('clip.take'), payload: emptyClip());
    controller.select(addr('clip.take'));
  });

  tearDown(() async {
    controller.dispose();
    registry.dispose();
    await midiGateway.dispose();
    await engine.dispose();
    await yse.dispose();
  });

  Future<void> pumpSurface(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            height: 620,
            child: MidiSurface(engine: engine, libraryController: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  MidiClip editedClip() => engine.midi.editedSession.chain.source;

  testWidgets('the record button arms, captures a played note, and disarms', (
    tester,
  ) async {
    await pumpSurface(tester);

    // The record button is present (a live session wires the record flow).
    expect(find.byKey(ClipTransportRow.recordArmKey), findsOneWidget);
    expect(engine.midi.record.armed, isFalse);

    // Arm record.
    await tester.tap(find.byKey(ClipTransportRow.recordArmKey));
    await tester.pump();
    expect(engine.midi.record.armed, isTrue);

    // Arm + play starts a take.
    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump(const Duration(milliseconds: 20));
    expect(engine.midi.record.isRecording, isTrue);

    // A played note (MIDI-in on/off) is captured.
    final before = editedClip().notes.length;
    midiGateway.emitNoteOn('Fake MIDI In', 60, 100);
    await tester.pump(const Duration(milliseconds: 60));
    midiGateway.emitNoteOff('Fake MIDI In', 60);
    await tester.pump(const Duration(milliseconds: 20));

    // Stop ends the take and commits the pass.
    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump();
    expect(engine.midi.record.isRecording, isFalse);
    expect(editedClip().notes.length, before + 1);
    final note = editedClip().notes.last;
    expect(note.pitch, 60.0);
    expect(note.start, greaterThanOrEqualTo(0.0));
    expect(note.duration, greaterThanOrEqualTo(0.0));

    // Arm stays on across stop; a second click disarms.
    expect(engine.midi.record.armed, isTrue);
    await tester.tap(find.byKey(ClipTransportRow.recordArmKey));
    await tester.pump();
    expect(engine.midi.record.armed, isFalse);
  });

  testWidgets('without arming, playing captures nothing', (tester) async {
    await pumpSurface(tester);

    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump(const Duration(milliseconds: 20));
    expect(engine.midi.record.isRecording, isFalse);

    midiGateway.emitNoteOn('Fake MIDI In', 62, 100);
    await tester.pump(const Duration(milliseconds: 40));
    midiGateway.emitNoteOff('Fake MIDI In', 62);
    await tester.pump();

    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump();
    expect(editedClip().notes, isEmpty);
  });
}
