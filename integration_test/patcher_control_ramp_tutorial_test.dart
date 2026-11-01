import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_catalog.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/tutorial/memory_patch_tutorial_source.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette_tab.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/tutorial/patch_tutorial_bar.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/patcher/test_support/open_tutorial_by_search.dart';

/// End-to-end proof that a **control-only tutorial ramps** (issue #528)
/// through the real [PhiApp]: real rail navigation, layout and the real
/// patcher engine ([RealPatcherGateway] on an offline libyse session). Only
/// the audio device, MIDI and the tutorial content are fakes: the tutorial is
/// a message `2000`, packed with a ramp time of 2000 ms, into `line 0.` and a
/// number box, and nothing else — no `~dac`.
///
/// On libYSE 3.1.0 a `.line` advances on the audio clock, so it ramps only in
/// a mounted, rendered patcher. Before #528 a tutorial without a `~dac` was
/// never mounted and the number box sat at 0. Now every tutorial is mounted
/// while open: clicking the message makes the number box on the canvas glide
/// up to 2000, silently, and the user's own (empty, stopped) patch is never
/// mounted along with it (#523).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  // One object of a tutorial in the engine's dump format.
  Map<String, Object?> object(
    int id,
    String type,
    double y, {
    String parms = '',
    int? to,
  }) => {
    'ID': id,
    'gui': {'x': '60.0', 'y': '$y'},
    'parms': parms,
    'type': type,
    'outputs': {
      'output 0': {
        if (to != null) '0': {'Inlet': 0, 'Object': to},
        'Count': to == null ? 0 : 1,
      },
    },
  };
  final tutorial = {
    'title': 'line — a control ramp',
    'covers': ['.line'],
    'summary': 'A number that glides instead of jumping.',
    'payload': {
      'dump': {
        'object 0': object(
          0,
          '.text',
          20,
          parms: '# line — a control ramp\nline glides to a target.',
        ),
        // A one-word message, packed with a time: a multi-word .m keeps only
        // its first word on libYSE 3.1.0 (#521).
        'object 1': object(1, '.m', 160, parms: '2000', to: 2),
        'object 2': object(2, '.pack', 220, parms: '0. 2000', to: 3),
        'object 3': object(3, '.line', 280, parms: '0.', to: 4),
        'object 4': object(4, '.f', 340),
      },
    },
  };

  testWidgets('patcher: a control-only tutorial is mounted while open, so '
      'its line visibly glides', (tester) async {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    addTearDown(System.instance.close);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final gateway = RealPatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: gateway,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
      patchTutorialSource: MemoryPatchTutorialSource({
        TutorialCatalog.indexPath: jsonEncode({'.line': 'line-ramp'}),
        TutorialCatalog.assetPathFor('line-ramp'): jsonEncode(tutorial),
      }),
    );
    final session = SessionState();
    final project = ProjectController(
      session: session,
      settings: AppSettingsController(FakeAppSettingsStore()),
      storeFactory: (_) => store,
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: project,
        directoryPicker: FakeProjectDirectoryPicker(
          newLocationPath: '/projects/control-ramp.phi',
        ),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    final ownPatch = engine.patcher.instanceId;
    expect(gateway.isSourceReady(ownPatch), isFalse, reason: '#523');
    await tester.tap(
      find.byKey(PatcherPalette.tabKey(PatcherPaletteTab.tutorials)),
    );
    await tester.pumpAndSettle();

    // Renders [blocks] blocks and returns the loudest master peak.
    double render(int blocks) {
      var peak = 0.0;
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
        final p = Channel.master.peakLinearPost();
        if (p > peak) peak = p;
      }
      return peak;
    }

    await openTutorialBySearch(tester, '.line');
    final library = engine.patchLibrary;
    final open = library.tutorial!;
    expect(open.slug, 'line-ramp');
    expect(find.byKey(PatchTutorialBar.bannerKey), findsOneWidget);

    // The tutorial is mounted although it has no ~dac. libyse sets the sound
    // up on a worker thread, in wall-clock time: render with real pauses.
    for (var i = 0; i < 5000 && !gateway.isSourceReady(open.instanceId); i++) {
      render(1);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(gateway.isSourceReady(open.instanceId), isTrue, reason: 'mounted');
    expect(
      gateway.isSourceReady(ownPatch),
      isFalse,
      reason: 'opening a tutorial does not mount the user patch (#523)',
    );

    // What the number box below line shows on the canvas.
    final numberBox = find.descendant(
      of: find.byWidgetPredicate(
        (w) =>
            w is PatcherNodeView &&
            w.node.type == '.f' &&
            w.node.position == const Offset(60, 340),
      ),
      matching: find.descendant(
        of: find.byType(NumberNodeBody),
        matching: find.byType(TextField),
      ),
    );
    expect(numberBox, findsOneWidget);
    double shown() =>
        double.parse(tester.widget<TextField>(numberBox).controller!.text);
    // Lets the surface's live-value poll come due and its frame land.
    Future<void> settlePoll() async {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    expect(shown(), 0);

    final message = find.descendant(
      of: find.byType(PatchMessageBox),
      matching: find.text('2000'),
    );
    expect(message, findsOneWidget);
    await tester.tap(message);
    await tester.pumpAndSettle();

    // Two seconds of audio, a slice at a time, reading the canvas in between.
    final path = <double>[];
    var loudest = 0.0;
    for (var i = 0; i < 40 && (path.isEmpty || path.last < 2000); i++) {
      final p = render(25); // 25 blocks of 128 frames: ~67 ms
      if (p > loudest) loudest = p;
      await settlePoll();
      path.add(shown());
    }
    expect(
      path.where((v) => v > 0 && v < 2000),
      hasLength(greaterThan(2)),
      reason: 'the number box glides on the canvas: $path',
    );
    for (var i = 1; i < path.length; i++) {
      expect(path[i], greaterThanOrEqualTo(path[i - 1]), reason: '$path');
    }
    expect(path.last, 2000, reason: 'line arrives: $path');
    expect(loudest, 0, reason: 'mounted, but a patch without ~dac is silent');

    await tester.tap(find.byKey(PatchTutorialBar.closeKey));
    await tester.pumpAndSettle();
    expect(library.tutorial, isNull);
    expect(gateway.isSourceReady(ownPatch), isFalse, reason: '#523');
    expect(render(50), 0, reason: 'nothing left playing');

    session.dispose();
    await engine.dispose();
  });
}
