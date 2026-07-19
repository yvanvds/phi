import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/clip_library_controller.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';
import 'package:phi/surfaces/midi/clip_transport_row.dart';
import 'package:phi/surfaces/midi/midi_surface.dart';

import '../../engine/test_doubles/fake_midi_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

/// The MIDI surface's header transport + length row wired to a live session
/// (issue #190): length editing applies, shrinking notes-out-of-window warns
/// first, and the transport buttons drive the session's fake transport.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  Map<String, Object?> clipPayload({int bars = 4}) => ClipDocument(
    source: MidiClip(
      bars: bars,
      notes: const [
        // A note living out at beat 8 (start of bar 3), so a shrink below it
        // strands notes and must warn.
        MidiNote(pitch: 60, start: 8, duration: 1, velocity: 0.8),
      ],
    ),
  ).toJson();

  MidiTransformChain seedChain() => MidiTransformChain(
    source: MidiClip(
      bars: 4,
      notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
    ),
  );

  late FakeYseGateway yse;
  late PhiEngine engine;
  late ProjectRegistry registry;
  late FakeMidiGateway midiGateway;
  late EngineMidiController sessions;
  late ClipLibraryController controller;

  setUp(() {
    yse = FakeYseGateway();
    engine = PhiEngine(
      yse,
      telemetryInterval: const Duration(milliseconds: 50),
    );
    registry = ProjectRegistry();
    midiGateway = FakeMidiGateway();
    sessions = EngineMidiController(chain: seedChain(), gateway: midiGateway);
    controller = ClipLibraryController(registry: registry, sessions: sessions);
    registry.createEntity(addr('clip.a'), payload: clipPayload());
    controller.select(addr('clip.a'));
  });

  tearDown(() async {
    controller.dispose();
    sessions.dispose();
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

  MidiClip editedClip() => sessions.editedSession.chain.source;

  Future<void> enterBars(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(ClipTransportRow.barsFieldKey), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('growing the length applies without a warning', (tester) async {
    await pumpSurface(tester);
    expect(editedClip().bars, 4);

    await enterBars(tester, '8');

    expect(find.text('shrink clip'), findsNothing);
    expect(editedClip().bars, 8);
  });

  testWidgets('shrinking past a note warns, and confirming applies it', (
    tester,
  ) async {
    await pumpSurface(tester);

    await enterBars(tester, '2'); // total 8 < the note ending at beat 9
    expect(find.text('shrink clip'), findsOneWidget);

    await tester.tap(find.text('shrink'));
    await tester.pumpAndSettle();

    expect(editedClip().bars, 2);
  });

  testWidgets('cancelling the shrink warning leaves the length unchanged', (
    tester,
  ) async {
    await pumpSurface(tester);

    await enterBars(tester, '2');
    expect(find.text('shrink clip'), findsOneWidget);

    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();

    expect(editedClip().bars, 4);
    // The field snapped back to the authoritative value.
    final barsField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ClipTransportRow.barsFieldKey),
        matching: find.byType(EditableText),
      ),
    );
    expect(barsField.controller.text, '4');
  });

  testWidgets('shrinking that strands no note applies without warning', (
    tester,
  ) async {
    // clip.a's note ends at beat 9; bars 4→3 (total 12) still contains it.
    await pumpSurface(tester);

    await enterBars(tester, '3');

    expect(find.text('shrink clip'), findsNothing);
    expect(editedClip().bars, 3);
  });

  testWidgets('play / pause / stop drive the session transport', (
    tester,
  ) async {
    await pumpSurface(tester);
    final session = sessions.editedSession;

    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump();
    expect(session.isPlaying, isTrue);
    expect(midiGateway.transport, isNotNull);
    expect(midiGateway.transport!.calls, contains('play'));

    await tester.tap(find.byKey(ClipTransportRow.pauseKey));
    await tester.pump();
    expect(session.isPlaying, isFalse);
    expect(session.isPaused, isTrue);

    // Play again resumes from the pause (does not restart from the top).
    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump();
    expect(session.isPlaying, isTrue);
    expect(session.isPaused, isFalse);

    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump();
    expect(session.isPlaying, isFalse);
    expect(session.isPaused, isFalse);
    expect(midiGateway.transport!.calls, contains('stop'));
  });

  testWidgets('the loop button toggles the edited session loop flag', (
    tester,
  ) async {
    await pumpSurface(tester);
    expect(sessions.loop, isTrue); // default on

    await tester.tap(find.byKey(ClipTransportRow.loopKey));
    await tester.pump();

    expect(sessions.loop, isFalse);
  });
}
