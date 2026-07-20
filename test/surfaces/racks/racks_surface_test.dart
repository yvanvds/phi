import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/synth/va_synth.dart';
import 'package:phi/domain/voice/voice_definition.dart';
import 'package:phi/engine/state/rack_definitions_controller.dart';
import 'package:phi/surfaces/racks/definition_editor_pane.dart';
import 'package:phi/surfaces/racks/definitions_panel.dart';
import 'package:phi/surfaces/racks/racks_surface.dart';
import 'package:phi/surfaces/racks/voices_pane.dart';

EntityAddress _addr(String dotted) => EntityAddress.parse(dotted);

void main() {
  late ProjectRegistry registry;
  late RackDefinitionsController controller;

  RackDefinitionsController build({void Function(ProjectRegistry)? seed}) {
    registry = ProjectRegistry();
    controller = RackDefinitionsController(registry: registry);
    seed?.call(registry);
    addTearDown(() {
      controller.dispose();
      registry.dispose();
    });
    return controller;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 640,
            child: RacksSurface(controller: controller),
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
    r.createEntity(_addr('synth.lead'), payload: const VaSynth().toJson());
    r.createEntity(
      _addr('synth.keys.piano'),
      payload: const SineSynth().toJson(),
    );
    r.createEntity(_addr('fx.reverb'), payload: {'kind': 'lowpass'});
    r.createEntity(
      _addr('voice.default'),
      payload: VoiceDefinition.internal(
        synth: _addr('synth.lead'),
        output: _addr('mix.master'),
      ).toJson(),
    );
  }

  testWidgets('renders synth + fx trees, kind chips, and the voices pane', (
    tester,
  ) async {
    build(seed: seedTree);
    await pump(tester);

    // Section labels.
    expect(find.text('SYNTHS'), findsOneWidget);
    expect(find.text('EFFECTS'), findsOneWidget);
    expect(find.text('VOICES'), findsOneWidget);

    // Synth leaf + group + nested leaf, and the fx leaf, each by its name.
    expect(
      find.byKey(DefinitionsPanel.rowKey(_addr('synth.lead'))),
      findsOneWidget,
    );
    expect(
      find.byKey(DefinitionsPanel.rowKey(_addr('synth.keys'))),
      findsOneWidget,
    );
    expect(
      find.byKey(DefinitionsPanel.rowKey(_addr('synth.keys.piano'))),
      findsOneWidget,
    );
    expect(
      find.byKey(DefinitionsPanel.rowKey(_addr('fx.reverb'))),
      findsOneWidget,
    );

    // Kind chips render on leaves.
    expect(find.text('va'), findsOneWidget);

    // The seeded voice renders in the right pane.
    expect(
      find.byKey(VoicesPane.rowKey(_addr('voice.default'))),
      findsOneWidget,
    );
  });

  testWidgets('selecting a definition routes the center editor pane', (
    tester,
  ) async {
    build(seed: seedTree);
    await pump(tester);

    // Nothing selected → empty hint, no title.
    expect(find.byKey(DefinitionEditorPane.emptyKey), findsOneWidget);
    expect(find.byKey(DefinitionEditorPane.titleKey), findsNothing);

    await tester.tap(find.byKey(DefinitionsPanel.rowKey(_addr('synth.lead'))));
    await tester.pumpAndSettle();

    expect(controller.selected, _addr('synth.lead'));
    expect(find.byKey(DefinitionEditorPane.titleKey), findsOneWidget);
    // The title names the selected definition; the subtitle names its kind; and
    // the VA panel renders its sections (issue #210).
    expect(find.widgetWithText(Column, 'lead'), findsWidgets);
    expect(find.text('synth · va'), findsOneWidget);
    expect(find.text('FILTER'), findsOneWidget);

    // Selecting the fx re-routes to the fx param rows.
    await tester.tap(find.byKey(DefinitionsPanel.rowKey(_addr('fx.reverb'))));
    await tester.pumpAndSettle();
    expect(controller.selected, _addr('fx.reverb'));
    expect(find.text('effect · lowpass'), findsOneWidget);
    expect(find.text('MIX'), findsOneWidget);
  });

  testWidgets('SYNTHS add menu creates a synth per kind and selects it', (
    tester,
  ) async {
    build();
    await pump(tester);

    await tester.tap(find.byKey(DefinitionsPanel.synthAddKey));
    await tester.pumpAndSettle();
    // The menu offers every synth kind + new group.
    expect(
      find.byKey(DefinitionsPanel.addItemKey('synth', 'sine')),
      findsOneWidget,
    );
    expect(
      find.byKey(DefinitionsPanel.addItemKey('synth', 'va')),
      findsOneWidget,
    );
    expect(
      find.byKey(DefinitionsPanel.addItemKey('synth', 'fm')),
      findsOneWidget,
    );
    expect(
      find.byKey(DefinitionsPanel.addItemKey('synth', 'sampler')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(DefinitionsPanel.addItemKey('synth', 'fm')));
    await tester.pumpAndSettle();

    expect(registry.contains(_addr('synth.fm')), isTrue);
    expect(controller.selected, _addr('synth.fm'));
    expect(find.text('synth · fm'), findsOneWidget);
  });

  testWidgets('EFFECTS add menu creates an fx instance', (tester) async {
    build();
    await pump(tester);

    await tester.tap(find.byKey(DefinitionsPanel.fxAddKey));
    await tester.pumpAndSettle();
    // The reserved patcherInsert is not offered.
    expect(
      find.byKey(DefinitionsPanel.addItemKey('fx', 'patcherInsert')),
      findsNothing,
    );

    await tester.tap(find.byKey(DefinitionsPanel.addItemKey('fx', 'phaser')));
    await tester.pumpAndSettle();

    expect(registry.contains(_addr('fx.phaser')), isTrue);
    expect(controller.selected, _addr('fx.phaser'));
  });

  testWidgets('add menu creates a group', (tester) async {
    build();
    await pump(tester);

    await tester.tap(find.byKey(DefinitionsPanel.synthAddKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DefinitionsPanel.addItemKey('synth', 'group')));
    await tester.pumpAndSettle();

    expect(registry.groupAt(_addr('synth.group')), isNotNull);
  });

  testWidgets('row menu duplicates a leaf', (tester) async {
    build(seed: seedTree);
    await pump(tester);

    await tester.tap(find.byKey(DefinitionsPanel.menuKey(_addr('fx.reverb'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('duplicate'));
    await tester.pumpAndSettle();

    expect(registry.contains(_addr('fx.reverb_copy')), isTrue);
  });

  testWidgets('row menu renames a definition (refactor)', (tester) async {
    build(seed: seedTree);
    await pump(tester);

    await tester.tap(find.byKey(DefinitionsPanel.menuKey(_addr('synth.lead'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('rename…'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Big Lead');
    await tester.tap(find.widgetWithText(TextButton, 'rename'));
    await tester.pumpAndSettle();

    expect(registry.contains(_addr('synth.big_lead')), isTrue);
    expect(registry.contains(_addr('synth.lead')), isFalse);
  });

  testWidgets('row menu deletes an unreferenced definition after confirm', (
    tester,
  ) async {
    build(seed: seedTree);
    await pump(tester);

    await tester.tap(find.byKey(DefinitionsPanel.menuKey(_addr('fx.reverb'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    // A plain confirm dialog (no referrers) → confirm.
    await tester.tap(find.widgetWithText(TextButton, 'delete'));
    await tester.pumpAndSettle();

    expect(registry.contains(_addr('fx.reverb')), isFalse);
  });

  testWidgets('deleting a referenced synth raises the delete-impact dialog', (
    tester,
  ) async {
    build(
      seed: (r) {
        r.createEntity(_addr('synth.lead'), payload: const VaSynth().toJson());
        // A voice referencing the synth — pass the object so its references derive.
        r.createEntity(
          _addr('voice.bells'),
          payload: VoiceDefinition.internal(
            synth: _addr('synth.lead'),
            output: _addr('mix.master'),
          ),
        );
      },
    );
    await pump(tester);

    await tester.tap(find.byKey(DefinitionsPanel.menuKey(_addr('synth.lead'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    // The impact dialog lists the stranded referrer.
    expect(find.textContaining('voice.bells'), findsOneWidget);
    // Cancel keeps it.
    await tester.tap(find.widgetWithText(TextButton, 'cancel'));
    await tester.pumpAndSettle();
    expect(registry.contains(_addr('synth.lead')), isTrue);
  });

  testWidgets('dragging a leaf onto a sibling reorders it', (tester) async {
    build(
      seed: (r) {
        r.createEntity(_addr('synth.a'), payload: const SineSynth().toJson());
        r.createEntity(_addr('synth.b'), payload: const SineSynth().toJson());
        r.createEntity(_addr('synth.c'), payload: const SineSynth().toJson());
      },
    );
    await pump(tester);
    expect(controller.synthTree.map((n) => n.name), ['a', 'b', 'c']);

    await dragOnto(
      tester,
      find.byKey(DefinitionsPanel.dragHandleKey(_addr('synth.c'))),
      find.byKey(DefinitionsPanel.rowKey(_addr('synth.a'))),
    );

    expect(controller.synthTree.map((n) => n.name), ['c', 'a', 'b']);
  });

  testWidgets('dragging a leaf onto a group re-parents it', (tester) async {
    build(
      seed: (r) {
        r.createEntity(_addr('synth.lead'), payload: const VaSynth().toJson());
        r.createGroup(_addr('synth.keys'));
      },
    );
    await pump(tester);

    await dragOnto(
      tester,
      find.byKey(DefinitionsPanel.dragHandleKey(_addr('synth.lead'))),
      find.byKey(DefinitionsPanel.rowKey(_addr('synth.keys'))),
    );

    expect(registry.contains(_addr('synth.keys.lead')), isTrue);
    expect(registry.contains(_addr('synth.lead')), isFalse);
  });

  testWidgets('a null controller renders a hint (bare shell)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RacksSurface(controller: null))),
    );
    await tester.pumpAndSettle();
    expect(find.text('no project loaded'), findsOneWidget);
  });
}
