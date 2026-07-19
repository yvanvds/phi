import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/scale_tuning.dart';
import 'package:phi/domain/midi/spawn_axis.dart';
import 'package:phi/domain/midi/spawn_source.dart';
import 'package:phi/domain/midi/transforms/agent_spawn_transform.dart';
import 'package:phi/domain/midi/transforms/conditional_muting_transform.dart';
import 'package:phi/domain/midi/transforms/note_condition.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';
import 'package:phi/domain/midi/transforms/spectral_mapping_transform.dart';
import 'package:phi/domain/midi/transforms/split_voice.dart';
import 'package:phi/domain/midi/transforms/splitting_transform.dart';
import 'package:phi/domain/midi/transforms/stub_transform.dart';
import 'package:phi/domain/midi/transforms/velocity_curve.dart';
import 'package:phi/domain/midi/transforms/velocity_curve_shape.dart';
import 'package:phi/domain/midi/transforms/velocity_to_parameter_transform.dart';
import 'package:phi/domain/midi/transforms/voice_routing_rule.dart';
import 'package:phi/domain/midi/transforms/voice_routing_transform.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/surfaces/midi/midi_surface.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';
import '../../engine/test_doubles/fake_yse_gateway.dart';

/// The typed parameter editors (issue #95): each table/rule-list transform
/// opens its dedicated dialog from the chip's "edit parameters…" action, and
/// editing mutates the chip in place — live through the same
/// `MidiTransformChain.replaceAt` path the scalar editor uses.
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

  MidiTransformChain oneNoteChain(List<MidiTransform> transforms) =>
      MidiTransformChain(
        source: MidiClip(
          notes: const [
            MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
          ],
          bars: 1,
        ),
        transforms: transforms,
      );

  Future<void> pump(WidgetTester tester, MidiTransformChain chain) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 480,
            child: MidiSurface(engine: engine, chain: chain),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byType(TransformChip), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('edit parameters…'));
    await tester.pumpAndSettle();
  }

  /// TextFields scoped to the open editor dialog, in tree (field) order.
  Finder dialogFields() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  testWidgets('spectral: adding a mapping retunes the note live', (
    tester,
  ) async {
    final chain = oneNoteChain(const [
      SpectralMappingTransform(table: {}, label: 'spectral · map'),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    // Empty table passes the note through untouched.
    expect(chain.output.single.pitch, 60);

    await tester.tap(find.text('+ add mapping'));
    await tester.pumpAndSettle();
    await tester.enterText(dialogFields().at(0), '60');
    await tester.enterText(dialogFields().at(1), '72');
    await tester.pump();

    // 60 → 72 lands live on the chain output.
    expect(chain.output.single.pitch, 72);

    chain.dispose();
  });

  testWidgets('routing: adding a rule re-routes the note, voice editable', (
    tester,
  ) async {
    final chain = oneNoteChain(const [
      VoiceRoutingTransform(rules: [], label: 'route'),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    // No rules: the note keeps its source voice (unrouted).
    expect(chain.output.single.voice, isNull);

    await tester.tap(find.text('+ add rule'));
    await tester.pumpAndSettle();
    // Default pitch-range rule (0..127 → voice.default) catches the note.
    expect(chain.output.single.voice, 'voice.default');

    // The voice field is the third field in the block (min, max, voice).
    await tester.enterText(dialogFields().at(2), 'voice.bass');
    await tester.pump();
    expect(chain.output.single.voice, 'voice.bass');

    chain.dispose();
  });

  testWidgets('routing: switching a rule kind rebuilds it as that kind', (
    tester,
  ) async {
    final chain = oneNoteChain(const [
      VoiceRoutingTransform(
        rules: [PitchRangeRule(minPitch: 0, maxPitch: 127, voice: 'voice.two')],
        label: 'route',
      ),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    // The kind picker shows the current kind; switch it to scale degree.
    await tester.tap(find.text('pitch range'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('scale degree').last);
    await tester.pumpAndSettle();

    final rule =
        (chain.transforms.single as VoiceRoutingTransform).rules.single;
    expect(rule, isA<ScaleDegreeRule>());
    // The voice carries across the kind switch.
    expect(rule.voice, 'voice.two');
    // The tonic-degree default routes the middle-C note (degree 1 of C).
    expect(chain.output.single.voice, 'voice.two');

    chain.dispose();
  });

  testWidgets('split: adding a layer doubles the note, offset editable', (
    tester,
  ) async {
    final chain = oneNoteChain(const [
      SplittingTransform(voices: [SplitVoice()], label: 'split'),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    // One identity layer: the note passes through.
    expect(chain.output, hasLength(1));

    await tester.tap(find.text('+ add layer'));
    await tester.pumpAndSettle();
    expect(chain.output, hasLength(2));

    // Second row's pitch field (row 2 → fields ch/pitch/vel at indices 3/4/5).
    await tester.enterText(dialogFields().at(4), '12');
    await tester.pump();
    expect(chain.output.map((n) => n.pitch), containsAll(<double>[60, 72]));

    chain.dispose();
  });

  testWidgets('agent spawn: editing an axis input domain mutates the chip', (
    tester,
  ) async {
    final chain = oneNoteChain([
      AgentSpawnTransform(
        x: SpawnAxis.of(SpawnSource.pitch),
        y: SpawnAxis.of(SpawnSource.velocity),
        z: SpawnAxis.of(SpawnSource.time),
        label: 'spawn · agent',
      ),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    // First field is axis x's input min (default 0 for a pitch axis).
    expect((chain.transforms.single as AgentSpawnTransform).x.inMin, 0);
    await tester.enterText(dialogFields().at(0), '5');
    await tester.pump();

    expect((chain.transforms.single as AgentSpawnTransform).x.inMin, 5);

    chain.dispose();
  });

  testWidgets('scale: picking a preset retunes, tonic still editable', (
    tester,
  ) async {
    final chain = oneNoteChain([
      ScaleConformanceTransform.diatonic(
        scale: MusicScale.ionian,
        tonic: 60,
        label: 'scale · major C',
      ),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    // Pick 'dorian' from the scale choice.
    await tester.tap(find.text('ionian'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dorian').last);
    await tester.pumpAndSettle();

    final retuned = chain.transforms.single as ScaleConformanceTransform;
    expect(
      retuned.tuning.degreesCents,
      ScaleTuning.diatonic(MusicScale.dorian).degreesCents,
    );

    // The tonic field (the only text field here) still round-trips.
    await tester.enterText(dialogFields().at(0), '62');
    await tester.pump();
    expect((chain.transforms.single as ScaleConformanceTransform).tonic, 62);

    chain.dispose();
  });

  testWidgets('velocity: reshaping the curve mutates the chip live', (
    tester,
  ) async {
    // A mid-velocity note, so a shape change moves the value, not just endpoints.
    final chain = MidiTransformChain(
      source: MidiClip(
        notes: const [
          MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5),
        ],
        bars: 1,
      ),
      transforms: const [
        VelocityToParameterTransform(
          parameter: 'filter.cutoff',
          curve: VelocityCurve.identity(),
          label: 'vel → param',
        ),
      ],
    );
    await pump(tester, chain);
    await openEditor(tester);

    VelocityToParameterTransform vel() =>
        chain.transforms.single as VelocityToParameterTransform;
    double eventValue() => vel().eventsFor(chain.output).single.value;

    // Identity default: 0.5 → 0.5.
    expect(eventValue(), 0.5);

    // Fields: [0] param, [1] value@vel0, [2] value@vel1. Widen the range.
    await tester.enterText(dialogFields().at(2), '100');
    await tester.pump();
    expect(eventValue(), 50); // linear: 0.5 → 50

    // Switch the shape to exponential (ease-in): 0.5² * 100 = 25.
    await tester.tap(find.text('linear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('exponential').last);
    await tester.pumpAndSettle();
    expect(vel().curve.shape, VelocityCurveShape.exponential);
    expect(eventValue(), 25);

    // Retarget the parameter path through the first field.
    await tester.enterText(dialogFields().at(0), 'fm.index');
    await tester.pump();
    expect(vel().parameter, 'fm.index');

    chain.dispose();
  });

  testWidgets('velocity: the stepped shape reveals the steps field', (
    tester,
  ) async {
    final chain = oneNoteChain(const [
      VelocityToParameterTransform(
        parameter: 'filter.cutoff',
        curve: VelocityCurve.identity(),
        label: 'vel → param',
      ),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    // Linear: param + two range fields, no steps field yet.
    expect(dialogFields(), findsNWidgets(3));

    await tester.tap(find.text('linear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('stepped').last);
    await tester.pumpAndSettle();

    // The steps field appears as the fourth field once the shape is stepped.
    expect(dialogFields(), findsNWidgets(4));
    expect(
      (chain.transforms.single as VelocityToParameterTransform).curve.shape,
      VelocityCurveShape.stepped,
    );

    chain.dispose();
  });

  testWidgets('muting: adding and editing a condition mutes notes live', (
    tester,
  ) async {
    final chain = oneNoteChain(const [
      ConditionalMutingTransform(
        condition: NoteConditionGroup.empty(),
        label: 'mute · if',
      ),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    ConditionalMutingTransform mute() =>
        chain.transforms.single as ConditionalMutingTransform;

    // Empty keep-all default: the one note plays.
    expect(chain.output, hasLength(1));

    // Add a condition — default `velocity < 0.5`. The note's velocity is 1, so
    // it still plays: the model landed but doesn't yet catch this note.
    await tester.tap(find.text('+ add condition'));
    await tester.pumpAndSettle();
    expect(chain.output, hasLength(1));
    expect(mute().condition, isA<NoteConditionGroup>());

    // Widen the threshold so `velocity < 2` catches the note → muted live.
    await tester.enterText(dialogFields().at(0), '2');
    await tester.pump();
    expect(chain.output, isEmpty);

    // Flip the comparison to ≥: `velocity ≥ 2` is false for vel 1 → plays again.
    await tester.tap(find.text('<'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('≥').last);
    await tester.pumpAndSettle();
    expect(chain.output, hasLength(1));

    chain.dispose();
  });

  testWidgets('muting: switching the field re-gates, combinator persists', (
    tester,
  ) async {
    final chain = oneNoteChain(const [
      ConditionalMutingTransform(
        condition: NoteConditionGroup.empty(),
        label: 'mute · if',
      ),
    ]);
    await pump(tester, chain);
    await openEditor(tester);

    ConditionalMutingTransform mute() =>
        chain.transforms.single as ConditionalMutingTransform;

    await tester.tap(find.text('+ add condition'));
    await tester.pumpAndSettle();

    // Switch the field velocity → pitch, comparison < → ≥, threshold 60:
    // the note's pitch is 60, so `pitch ≥ 60` catches it → muted.
    await tester.tap(find.text('velocity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pitch').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('<'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('≥').last);
    await tester.pumpAndSettle();
    await tester.enterText(dialogFields().at(0), '60');
    await tester.pump();
    expect(chain.output, isEmpty);

    final condition = mute().condition as NoteConditionGroup;
    expect(condition.conditions.single, isA<NoteFieldCondition>());

    // The combinator picker carries into the model.
    await tester.tap(find.text('any'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('all').last);
    await tester.pumpAndSettle();
    expect(
      (mute().condition as NoteConditionGroup).combinator,
      NoteConditionCombinator.all,
    );

    chain.dispose();
  });

  testWidgets('a parameterless stub chip greys out edit parameters', (
    tester,
  ) async {
    // With #108/#109 landed, no transform is callback-driven; a plain stub with
    // no scalar params and no typed editor is what still greys out.
    final chain = oneNoteChain(const [
      StubTransform(kind: MidiTransformKind.struct, label: 'branch · state'),
    ]);
    await pump(tester, chain);

    await tester.tap(find.byType(TransformChip), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
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

  testWidgets('a data-model chip is editable (dispatch diverts it)', (
    tester,
  ) async {
    // A split transform opens its typed dialog, proving the dispatch diverts the
    // data-model families rather than greying them out.
    final chain = oneNoteChain(const [
      SplittingTransform(voices: [SplitVoice()], label: 'split'),
    ]);
    await pump(tester, chain);

    await tester.tap(find.byType(TransformChip), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    final item =
        tester.widget(
              find.ancestor(
                of: find.text('edit parameters…'),
                matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
              ),
            )
            as PopupMenuItem;
    expect(item.enabled, isTrue);

    chain.dispose();
  });
}
