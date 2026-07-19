import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/engine/state/clip_library_controller.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';
import 'package:phi/surfaces/midi/library/library_panel.dart';

import '../../../engine/test_doubles/fake_midi_gateway.dart';

EntityAddress _addr(String dotted) => EntityAddress.parse(dotted);

Map<String, Object?> _clipPayload({double pitch = 60}) => ClipDocument(
  source: MidiClip(
    bars: 1,
    notes: [MidiNote(pitch: pitch, start: 0, duration: 1, velocity: 1)],
  ),
).toJson();

MidiTransformChain _seedChain() => MidiTransformChain(
  source: MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
);

void main() {
  late ProjectRegistry registry;
  late FakeMidiGateway gateway;
  late EngineMidiController sessions;
  late ClipLibraryController controller;

  ClipLibraryController build({void Function(ProjectRegistry)? seed}) {
    registry = ProjectRegistry();
    gateway = FakeMidiGateway();
    sessions = EngineMidiController(chain: _seedChain(), gateway: gateway);
    controller = ClipLibraryController(registry: registry, sessions: sessions);
    seed?.call(registry);
    addTearDown(() async {
      controller.dispose();
      sessions.dispose();
      registry.dispose();
      await gateway.dispose();
    });
    return controller;
  }

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 500,
              child: LibraryPanel(
                controller: controller,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dragOnto(
    WidgetTester tester,
    Finder source,
    Finder target,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(source));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  void seedTree(ProjectRegistry r) {
    r.createEntity(_addr('clip.a'), payload: _clipPayload(pitch: 60));
    r.createEntity(_addr('clip.drums.kick'), payload: _clipPayload(pitch: 36));
    r.createEntity(_addr('clip.drums.snare'), payload: _clipPayload(pitch: 38));
    r.createEntity(_addr('clip.b'), payload: _clipPayload(pitch: 62));
  }

  testWidgets('renders the clip tree with groups and order', (tester) async {
    build(seed: seedTree);
    await pumpPanel(tester);

    // Every clip + group leaf renders by its address name.
    expect(find.text('a'), findsOneWidget);
    expect(find.text('drums'), findsOneWidget);
    expect(find.text('kick'), findsOneWidget);
    expect(find.text('snare'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);

    // The rows appear top-to-bottom in registry order: a, drums, kick, snare, b.
    double topOf(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(topOf('a'), lessThan(topOf('drums')));
    expect(topOf('drums'), lessThan(topOf('kick')));
    expect(topOf('kick'), lessThan(topOf('snare')));
    expect(topOf('snare'), lessThan(topOf('b')));
  });

  testWidgets('tapping a clip opens it as the edited session', (tester) async {
    build(seed: seedTree);
    await pumpPanel(tester);
    expect(controller.editedAddress, isNull);

    await tester.tap(find.byKey(LibraryPanel.rowKey(_addr('clip.b'))));
    await tester.pumpAndSettle();

    expect(controller.editedAddress, _addr('clip.b'));
    expect(sessions.editedSession.address, _addr('clip.b'));
  });

  testWidgets('the collapse toggle hides then shows the tree', (tester) async {
    build(seed: seedTree);
    await pumpPanel(tester);
    expect(find.text('a'), findsOneWidget);

    await tester.tap(find.byKey(LibraryPanel.expandToggleKey).first);
    await tester.pumpAndSettle();
    // Collapsed: the tree is gone, only the strip's expand toggle remains.
    expect(find.text('a'), findsNothing);

    await tester.tap(find.byKey(LibraryPanel.expandToggleKey));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
  });

  group('context menu', () {
    testWidgets('new clip adds a sibling clip', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(LibraryPanel.menuKey(_addr('clip.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('new clip'));
      await tester.pumpAndSettle();

      // A fresh top-level clip.clip appeared (a's parent is the top level).
      expect(registry.contains(_addr('clip.clip')), isTrue);
    });

    testWidgets('new group adds a group folder', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(LibraryPanel.menuKey(_addr('clip.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('new group'));
      await tester.pumpAndSettle();

      expect(registry.groupAt(_addr('clip.group')), isNotNull);
    });

    testWidgets('duplicate copies the clip to <name>_copy', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(LibraryPanel.menuKey(_addr('clip.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('duplicate'));
      await tester.pumpAndSettle();

      expect(registry.contains(_addr('clip.a_copy')), isTrue);
    });

    testWidgets('rename moves the entity to the new slug', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(LibraryPanel.menuKey(_addr('clip.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('rename…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'lead line');
      await tester.tap(find.widgetWithText(TextButton, 'rename'));
      await tester.pumpAndSettle();

      expect(registry.contains(_addr('clip.a')), isFalse);
      expect(registry.contains(_addr('clip.lead_line')), isTrue);
    });

    testWidgets('delete confirms then removes the clip', (tester) async {
      build(seed: seedTree);
      await pumpPanel(tester);

      await tester.tap(find.byKey(LibraryPanel.menuKey(_addr('clip.a'))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();

      // The confirm dialog is up; confirming removes the clip.
      await tester.tap(find.widgetWithText(TextButton, 'delete'));
      await tester.pumpAndSettle();

      expect(registry.contains(_addr('clip.a')), isFalse);
    });
  });

  testWidgets('dragging a clip onto a group re-parents it in the registry', (
    tester,
  ) async {
    build(seed: seedTree);
    await pumpPanel(tester);

    await dragOnto(
      tester,
      find.byKey(LibraryPanel.dragHandleKey(_addr('clip.a'))),
      find.byKey(LibraryPanel.rowKey(_addr('clip.drums'))),
    );

    expect(registry.contains(_addr('clip.a')), isFalse);
    expect(registry.contains(_addr('clip.drums.a')), isTrue);
  });

  testWidgets('per-row play toggles play state and shows the playing dot', (
    tester,
  ) async {
    build(seed: seedTree);
    await pumpPanel(tester);
    final a = _addr('clip.a');
    expect(find.byKey(LibraryPanel.playingDotKey(a)), findsNothing);

    await tester.tap(find.byKey(LibraryPanel.playKey(a)));
    await tester.pump();

    expect(controller.isPlaying(a), isTrue);
    expect(find.byKey(LibraryPanel.playingDotKey(a)), findsOneWidget);

    // Tapping again stops it (and cancels the ticker before teardown).
    await tester.tap(find.byKey(LibraryPanel.playKey(a)));
    await tester.pump();
    expect(controller.isPlaying(a), isFalse);
  });

  testWidgets('group play/stop drives the whole subtree', (tester) async {
    build(seed: seedTree);
    await pumpPanel(tester);
    final drums = _addr('clip.drums');

    await tester.tap(find.byKey(LibraryPanel.groupPlayKey(drums)));
    await tester.pump();
    expect(controller.isPlaying(_addr('clip.drums.kick')), isTrue);
    expect(controller.isPlaying(_addr('clip.drums.snare')), isTrue);

    await tester.tap(find.byKey(LibraryPanel.groupPlayKey(drums)));
    await tester.pump();
    expect(controller.isGroupPlaying(drums), isFalse);
  });

  testWidgets('stop-all in the header halts every playing clip', (
    tester,
  ) async {
    build(seed: seedTree);
    await pumpPanel(tester);

    await tester.tap(find.byKey(LibraryPanel.playKey(_addr('clip.a'))));
    await tester.pump();
    await tester.tap(find.byKey(LibraryPanel.playKey(_addr('clip.b'))));
    await tester.pump();
    expect(controller.isPlaying(_addr('clip.a')), isTrue);

    await tester.tap(find.byKey(LibraryPanel.stopAllKey));
    await tester.pump();

    expect(controller.isPlaying(_addr('clip.a')), isFalse);
    expect(controller.isPlaying(_addr('clip.b')), isFalse);
  });
}
