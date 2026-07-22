import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/code/completion/phi_completion_item.dart';
import 'package:phi/domain/code/completion/phi_completion_item_kind.dart';
import 'package:phi/domain/code/completion/phi_method_table.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/code/completion/phi_completion_list_view.dart';
import 'package:phi/surfaces/code/completion/phi_completion_prompt.dart';
import 'package:re_editor/re_editor.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the registry-driven completion (issue #236) through the
/// real [PhiApp]: a fresh project seeds `voice.default`, `clip.phrase_a` and the
/// demo domains, so once the Code surface is open the editor's `CodeAutocomplete`
/// hook — wired to the *live* engine registry — resolves each `phi` namespace to
/// its real entities, a leaf to the static method table, and a plain Python line
/// to nothing.
///
/// **Why the popup isn't driven by simulated typing.** `re_editor` only raises
/// its autocomplete overlay from real keystrokes delivered as text-input
/// *deltas* (`updateEditingValueWithDeltas`); it deliberately ignores the
/// non-delta `updateEditingValue` that `WidgetTester.enterText` sends, and
/// flutter_test exposes no way to inject deltas into its custom input client. So
/// the keystroke→overlay hop is not drivable in CI. This test instead exercises
/// the exact seam `re_editor` itself calls — the wired `promptsBuilder.build`
/// against the real registry, and the `viewBuilder` that paints the overlay —
/// which is everything user-visible except that final un-fakeable hop.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('completion resolves phi namespaces from the live registry', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final controller = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => FakeProjectStore(codecs: defaultEntityCodecs()),
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Open the Code surface — its editor is wrapped in the completion hook.
    await tester.tap(railFor(SurfaceId.code));
    await tester.pumpAndSettle();

    final autocomplete = tester.widget<CodeAutocomplete>(
      find.byType(CodeAutocomplete),
    );
    final ctx = tester.element(find.byType(CodeEditor));

    CodeAutocompleteEditingValue? build(String line) =>
        autocomplete.promptsBuilder.build(
          ctx,
          CodeLine(line),
          CodeLineSelection.collapsed(index: 0, offset: line.length),
        );

    List<PhiCompletionItem> items(String line) => build(
      line,
    )!.prompts.whereType<PhiCompletionPrompt>().map((p) => p.item).toList();

    // `voice.` → the seeded starter voice, with its colour swatch token.
    final voiceItems = items('voice.');
    final voiceDefault = voiceItems.firstWhere(
      (i) => i.identifier == 'default',
    );
    expect(voiceDefault.kind, PhiCompletionItemKind.entity);
    expect(voiceDefault.colorToken, 'voice1');

    // Selecting a row inserts only the identifier (design §6).
    final defaultPrompt = build('voice.')!.prompts
        .whereType<PhiCompletionPrompt>()
        .firstWhere((p) => p.word == 'default');
    expect(defaultPrompt.autocomplete.word, 'default');

    // `clip.` → the seeded demo clip, carrying its bar length.
    final phrase = items('clip.').firstWhere((i) => i.identifier == 'phrase_a');
    expect(phrase.kind, PhiCompletionItemKind.entity);
    expect(phrase.bars, isNotNull);

    // `voice.default.` → the static method table (one level past an entity).
    expect(
      items('voice.default.').map((i) => i.identifier).toList(),
      phiMethodTable,
    );

    // `state.` → the seeded graph's states — the rows the live-code mirror
    // exposes to scripts (issue #246).
    final states = items('state.');
    expect(states.map((i) => i.identifier).toList(), ['intro', 'verse']);
    expect(states.every((i) => i.kind == PhiCompletionItemKind.entity), isTrue);

    // `state.verse.` → the method table again; `fire` is what
    // `state.verse.fire()` completes from.
    expect(
      items('state.verse.').map((i) => i.identifier).toList(),
      phiMethodTable,
    );
    expect(phiMethodTable, contains('fire'));

    // A plain Python line pops nothing.
    expect(build('print('), isNull);
    expect(build('gain'), isNull);

    // The overlay the hook would show is our Phi-flavoured list view.
    final view = autocomplete.viewBuilder(
      ctx,
      ValueNotifier(build('voice.')!),
      (_) {},
    );
    expect(view, isA<PhiCompletionListView>());

    await engine.dispose();
    await gateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
