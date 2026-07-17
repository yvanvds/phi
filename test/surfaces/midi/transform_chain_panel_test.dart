import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/custom_transform_registry.dart';
import 'package:phi/domain/midi/dsl_note.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/transforms/loop_transform.dart';
import 'package:phi/domain/midi/transforms/quantization_transform.dart';
import 'package:phi/domain/midi/transforms/stub_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/midi/midi_surface.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

List<DslNote> _octaveUp(List<DslNote> notes) =>
    notes.map((n) => n.copyWith(pitch: n.pitch + 12)).toList();

void main() {
  late FakeYseGateway gateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    engine = PhiEngine(
      gateway,
      patcherGateway: FakePatcherGateway(),
      telemetryInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  MidiClip oneNoteClip() => MidiClip(
    name: 't',
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
    bars: 1,
  );

  MidiTransformChain oneNoteChain({
    List<MidiTransform> transforms = const [],
  }) => MidiTransformChain(source: oneNoteClip(), transforms: transforms);

  Future<void> pump(
    WidgetTester tester,
    MidiTransformChain chain, {
    CustomTransformRegistry? registry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 480,
            child: MidiSurface(
              engine: engine,
              chain: chain,
              registry: registry,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('add menu', () {
    testWidgets('+ opens a menu grouping the built-in catalogue by family', (
      tester,
    ) async {
      final chain = oneNoteChain();
      await pump(tester, chain);

      await tester.tap(find.text('+'));
      await tester.pump();

      // The four family sections and a representative built-in from each.
      expect(find.text('PITCH'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('VOICE'), findsOneWidget);
      expect(find.text('STRUCT'), findsOneWidget);
      expect(find.text('transpose · +12 st'), findsOneWidget);
      expect(find.text('quantize · 1/16'), findsOneWidget);

      chain.dispose();
    });

    testWidgets('picking a built-in appends it to the chain with defaults', (
      tester,
    ) async {
      final chain = oneNoteChain();
      await pump(tester, chain);

      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.tap(find.text('transpose · +12 st'));
      await tester.pump();

      expect(chain.transforms, hasLength(1));
      expect(chain.transforms.single.label, 'transpose · +12 st');
      expect(chain.transforms.single.kind, MidiTransformKind.pitch);
      // Default is +12 semitones, so the single note lands an octave up.
      expect(chain.output.single.pitch, 72);
      expect(find.byType(TransformChip), findsOneWidget);

      chain.dispose();
    });

    testWidgets('works without a registry (built-ins need no live-coding)', (
      tester,
    ) async {
      final chain = oneNoteChain();
      await pump(tester, chain); // registry: null

      await tester.tap(find.text('+'));
      await tester.pump();
      expect(find.text('transpose · +12 st'), findsOneWidget);

      chain.dispose();
    });

    testWidgets('a registered custom transform appears under its family', (
      tester,
    ) async {
      final chain = oneNoteChain();
      final registry = CustomTransformRegistry();
      await pump(tester, chain, registry: registry);

      registry.register(
        name: 'octave up',
        kind: MidiTransformKind.pitch,
        transform: _octaveUp,
      );
      await tester.pump();

      await tester.tap(find.text('+'));
      await tester.pump();
      expect(find.text('octave up'), findsOneWidget);
      expect(chain.transforms, isEmpty);

      await tester.tap(find.text('octave up'));
      await tester.pump();

      expect(chain.transforms, hasLength(1));
      expect(chain.output.single.pitch, 72);

      chain.dispose();
      registry.dispose();
    });

    testWidgets('hot-reload re-registration updates an in-chain chip live', (
      tester,
    ) async {
      final chain = oneNoteChain();
      final registry = CustomTransformRegistry();
      await pump(tester, chain, registry: registry);

      registry.register(
        name: 'shift',
        kind: MidiTransformKind.pitch,
        transform: _octaveUp,
      );
      await tester.pump();
      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.tap(find.text('shift'));
      await tester.pump();
      expect(chain.output.single.pitch, 72);

      registry.register(
        name: 'shift',
        transform: (notes) => notes.map((n) => n.copyWith(pitch: 48)).toList(),
      );
      await tester.pump();

      expect(chain.transforms, hasLength(1));
      expect(chain.output.single.pitch, 48);

      chain.dispose();
      registry.dispose();
    });
  });

  group('reorder', () {
    testWidgets('dragging a chip handle reorders the chain in order', (
      tester,
    ) async {
      final chain = oneNoteChain(
        transforms: const [
          TransposeTransform(semitones: 1, label: 'first'),
          TransposeTransform(semitones: 2, label: 'second'),
        ],
      );
      await pump(tester, chain);

      // Drag the first chip's handle down past the second.
      final firstHandle = find.byIcon(Icons.drag_indicator).first;
      await tester.drag(firstHandle, const Offset(0, 48));
      await tester.pumpAndSettle();

      expect(chain.transforms.map((t) => t.label), ['second', 'first']);

      chain.dispose();
    });
  });

  group('chip context menu', () {
    Future<void> openMenuOn(WidgetTester tester, Finder chip) async {
      await tester.tap(chip, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
    }

    testWidgets('remove deletes the chip', (tester) async {
      final chain = oneNoteChain(
        transforms: const [TransposeTransform(semitones: 1, label: 'gone')],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip));
      await tester.tap(find.text('remove'));
      await tester.pumpAndSettle();

      expect(chain.transforms, isEmpty);
      expect(find.byType(TransformChip), findsNothing);

      chain.dispose();
    });

    testWidgets('duplicate inserts a copy right after the original', (
      tester,
    ) async {
      final chain = oneNoteChain(
        transforms: const [
          TransposeTransform(semitones: 5, label: 'dup me'),
          TransposeTransform(semitones: 1, label: 'tail'),
        ],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip).first);
      await tester.tap(find.text('duplicate'));
      await tester.pumpAndSettle();

      expect(chain.transforms.map((t) => t.label), [
        'dup me',
        'dup me',
        'tail',
      ]);

      chain.dispose();
    });

    testWidgets('edit parameters shows current values and applies live', (
      tester,
    ) async {
      final chain = oneNoteChain(
        transforms: const [TransposeTransform(semitones: 12, label: 'tr')],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip));
      await tester.tap(find.text('edit parameters…'));
      await tester.pumpAndSettle();

      // The editor round-trips the current value into its field.
      expect(find.text('semitones'), findsOneWidget);
      expect(find.widgetWithText(TextField, '12'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '-12');
      await tester.pump();

      // Live: the chain already reflects the edit while the dialog is open.
      expect(chain.output.single.pitch, 48);

      await tester.tap(find.text('done'));
      await tester.pumpAndSettle();

      expect(chain.transforms.single.label, 'tr');
      expect(chain.output.single.pitch, 48);

      chain.dispose();
    });

    testWidgets('edited values clamp to the param bounds', (tester) async {
      final chain = oneNoteChain(
        transforms: const [
          QuantizationTransform(gravity: 0.5, label: 'q', grid: 0.25),
        ],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip));
      await tester.tap(find.text('edit parameters…'));
      await tester.pumpAndSettle();

      // Fields follow params order: grid, then gravity. Gravity is [0, 1].
      await tester.enterText(find.byType(TextField).at(1), '5');
      await tester.pump();

      final edited = chain.transforms.single as QuantizationTransform;
      expect(edited.gravity, 1.0);

      chain.dispose();
    });

    testWidgets('text that does not parse leaves the last valid value', (
      tester,
    ) async {
      final chain = oneNoteChain(
        transforms: const [TransposeTransform(semitones: 12, label: 'tr')],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip));
      await tester.tap(find.text('edit parameters…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '-');
      await tester.pump();

      expect(chain.output.single.pitch, 72);

      chain.dispose();
    });

    testWidgets('a struct-family edit reshapes the output live', (
      tester,
    ) async {
      final chain = oneNoteChain(
        transforms: const [
          LoopTransform(loopLengthBeats: 4, repeatCount: 1, label: 'loop'),
        ],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip));
      await tester.tap(find.text('edit parameters…'));
      await tester.pumpAndSettle();

      // Fields follow params order: length, repeats, phase.
      await tester.enterText(find.byType(TextField).at(1), '3');
      await tester.pump();

      expect(chain.output, hasLength(3));

      chain.dispose();
    });

    testWidgets('the context menu reopens after the param editor closes', (
      tester,
    ) async {
      final chain = oneNoteChain(
        transforms: const [TransposeTransform(semitones: 12, label: 'tr')],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip));
      await tester.tap(find.text('edit parameters…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('done'));
      await tester.pumpAndSettle();

      await openMenuOn(tester, find.byType(TransformChip));
      expect(find.text('remove'), findsOneWidget);

      chain.dispose();
    });

    testWidgets('edit parameters is greyed out for a parameterless stub', (
      tester,
    ) async {
      // With #108/#109 landed, no transform is callback-driven; a plain stub
      // with no scalar params and no typed editor is what still greys out.
      final chain = oneNoteChain(
        transforms: const [
          StubTransform(kind: MidiTransformKind.struct, label: 'branch'),
        ],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip));

      final item =
          tester.widget(
                find.ancestor(
                  of: find.text('edit parameters…'),
                  matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
                ),
              )
              as PopupMenuItem;
      expect(item.enabled, isFalse);

      chain.dispose();
    });

    testWidgets('rename changes the chip label', (tester) async {
      final chain = oneNoteChain(
        transforms: const [TransposeTransform(semitones: 1, label: 'old name')],
      );
      await pump(tester, chain);

      await openMenuOn(tester, find.byType(TransformChip));
      await tester.tap(find.text('rename…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'new name');
      await tester.tap(find.text('rename'));
      await tester.pumpAndSettle();

      expect(chain.transforms.single.label, 'new name');
      expect(find.text('new name'), findsOneWidget);

      chain.dispose();
    });
  });
}
