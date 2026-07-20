import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/select/phi_select.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/synth/fm_bank_reader.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/sampler_synth.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/synth/va_synth.dart';
import 'package:phi/domain/synth/va_waveform.dart';
import 'package:phi/engine/state/rack_definitions_controller.dart';
import 'package:phi/surfaces/racks/definition_editor_pane.dart';
import 'package:phi/surfaces/racks/editors/editor_slider_row.dart';
import 'package:phi/surfaces/racks/editors/fm_synth_editor.dart';
import 'package:phi/surfaces/racks/editors/sampler_synth_editor.dart';
import 'package:phi/surfaces/racks/rack_asset_source.dart';

EntityAddress _addr(String dotted) => EntityAddress.parse(dotted);

/// A fake bank reader that returns canned patch names for a given ref — the
/// "populating from a fake bank" the issue's *Done when* calls for.
class _FakeFmBankReader implements FmBankReader {
  _FakeFmBankReader(this.names);
  final List<String> names;
  String? lastRef;

  @override
  List<String> patchNames(String? bankRef) {
    lastRef = bankRef;
    return bankRef == null ? const [] : names;
  }
}

/// A fake asset source that returns a canned ref (as if imported) and records
/// the requested kind.
class _FakeRackAssetSource implements RackAssetSource {
  _FakeRackAssetSource(this.ref);
  final String? ref;
  RackAssetKind? lastKind;

  @override
  Future<String?> pickAsset(RackAssetKind kind) async {
    lastKind = kind;
    return ref;
  }
}

void main() {
  late ProjectRegistry registry;
  late List<ProjectCommand> recorded;
  late RackDefinitionsController controller;

  setUp(() {
    registry = ProjectRegistry();
    recorded = [];
    controller = RackDefinitionsController(
      registry: registry,
      recordCommand: recorded.add,
    );
  });

  tearDown(() {
    controller.dispose();
    registry.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    RackAssetSource? assetSource,
    FmBankReader? bankReader,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 900,
            child: DefinitionEditorPane(
              controller: controller,
              assetSource: assetSource,
              bankReader: bankReader,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('VA editor', () {
    setUp(() {
      registry.createEntity(
        _addr('synth.lead'),
        payload: const VaSynth().toJson(),
      );
      controller.select(_addr('synth.lead'));
      recorded.clear();
    });

    testWidgets('a slider drag coalesces into one journaled edit', (
      tester,
    ) async {
      await pump(tester);

      final slider = find.widgetWithText(EditorSliderRow, 'detune');
      expect(slider, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(slider));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      // Mid-drag: nothing committed yet — the whole gesture coalesces.
      expect(recorded, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();

      // Exactly one command for the whole drag, and the payload moved.
      expect(recorded, hasLength(1));
      final va = controller.synthAt(_addr('synth.lead'))! as VaSynth;
      expect(va.oscillators.first.detune, greaterThan(0));
    });

    testWidgets('the wave select mutates the oscillator payload', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byType(PhiSelect<VaWaveform>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('triangle'));
      await tester.pumpAndSettle();

      final va = controller.synthAt(_addr('synth.lead'))! as VaSynth;
      expect(va.oscillators.first.wave, VaWaveform.triangle);
      expect(recorded, hasLength(1));
    });
  });

  testWidgets('sine editor edits the voice count', (tester) async {
    registry.createEntity(
      _addr('synth.s'),
      payload: const SineSynth().toJson(),
    );
    controller.select(_addr('synth.s'));
    recorded.clear();
    await pump(tester);

    await tester.enterText(find.byType(TextField).first, '16');
    await tester.pump();

    expect((controller.synthAt(_addr('synth.s'))! as SineSynth).voiceCount, 16);
    expect(recorded, hasLength(1));
  });

  group('FM editor', () {
    testWidgets(
      'patch browser populates from a fake bank and selects a patch',
      (tester) async {
        registry.createEntity(
          _addr('synth.fm'),
          payload: const FmSynth(bankAsset: 'assets/rhodes.syx').toJson(),
        );
        controller.select(_addr('synth.fm'));
        recorded.clear();
        final reader = _FakeFmBankReader(['BRASS 1', 'E.PIANO 1', 'STRINGS']);

        await pump(tester, bankReader: reader);

        // The bank's patch names render.
        expect(find.text('BRASS 1'), findsOneWidget);
        expect(find.text('E.PIANO 1'), findsOneWidget);
        expect(reader.lastRef, 'assets/rhodes.syx');

        // Selecting a patch commits its index.
        await tester.tap(find.byKey(FmSynthEditor.patchRowKey(1)));
        await tester.pumpAndSettle();
        expect(
          (controller.synthAt(_addr('synth.fm'))! as FmSynth).patchIndex,
          1,
        );
        expect(recorded, hasLength(1));
      },
    );

    testWidgets('load bank imports a .syx and sets the ref', (tester) async {
      registry.createEntity(
        _addr('synth.fm'),
        payload: const FmSynth().toJson(),
      );
      controller.select(_addr('synth.fm'));
      recorded.clear();
      final source = _FakeRackAssetSource('assets/new.syx');

      await pump(
        tester,
        assetSource: source,
        bankReader: _FakeFmBankReader([]),
      );

      await tester.tap(find.byKey(FmSynthEditor.loadBankKey));
      await tester.pumpAndSettle();

      expect(source.lastKind, RackAssetKind.fmBank);
      expect(
        (controller.synthAt(_addr('synth.fm'))! as FmSynth).bankAsset,
        'assets/new.syx',
      );
      expect(recorded, hasLength(1));
    });
  });

  testWidgets('sampler editor loads a sample into a recipe', (tester) async {
    registry.createEntity(
      _addr('synth.smp'),
      payload: const SamplerSynth().toJson(),
    );
    controller.select(_addr('synth.smp'));
    recorded.clear();
    final source = _FakeRackAssetSource('assets/kick.wav');

    await pump(tester, assetSource: source);

    await tester.tap(find.byKey(SamplerSynthEditor.loadSampleKey));
    await tester.pumpAndSettle();

    expect(source.lastKind, RackAssetKind.sample);
    final smp = controller.synthAt(_addr('synth.smp'))! as SamplerSynth;
    expect(smp.recipe?.file, 'assets/kick.wav');
    expect(recorded, hasLength(1));
  });

  group('fx editor', () {
    setUp(() {
      registry.createEntity(
        _addr('fx.comp'),
        payload: const FxDefinition(kind: FxKind.compressor).toJson(),
      );
      controller.select(_addr('fx.comp'));
      recorded.clear();
    });

    testWidgets('a param slider drag writes one param and coalesces', (
      tester,
    ) async {
      await pump(tester);

      final slider = find.widgetWithText(EditorSliderRow, 'ratio');
      expect(slider, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(slider));
      await tester.pump();
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(recorded, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(recorded, hasLength(1));
      expect(
        controller.fxAt(_addr('fx.comp'))!.params.containsKey('ratio'),
        isTrue,
      );
    });

    testWidgets('the bypass toggle writes the bypass param', (tester) async {
      await pump(tester);

      expect(controller.fxAt(_addr('fx.comp'))!.params['bypass'] ?? 0, 0);
      await tester.tap(find.byType(PhiToggle));
      await tester.pumpAndSettle();

      expect(controller.fxAt(_addr('fx.comp'))!.params['bypass'], 1);
      expect(recorded, hasLength(1));
    });
  });
}
