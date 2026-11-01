import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/patcher/tutorial/patch_tutorial.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_catalog.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/state/patch_library_controller.dart';
import 'package:phi/engine/state/patch_reconciler.dart';
import 'package:phi/engine/state/tutorial/memory_patch_tutorial_source.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// The tutorial half of [PatchLibraryController] (issue #489): a transient
/// native patcher that is never a registry entity, shown through
/// `openEditor`, torn down on close, and copied into the project as an
/// ordinary journaled `patch.tutorials.<slug>` entity.
void main() {
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);

  /// A tutorial in the fake gateway's dump format: a note, and — when
  /// [audible] — a sine into a dac.
  String tutorialFile({bool audible = false}) => jsonEncode(
    PatchTutorial(
      title: 'sine — a tone',
      covers: const [Obj.dSine],
      payload: PatchPayload(
        dump: {
          'objects': [
            {'id': 0, 'type': '.text', 'args': '# sine', 'x': 10, 'y': 10},
            {'id': 1, 'type': Obj.dSine, 'args': '440', 'x': 10, 'y': 80},
            if (audible)
              {'id': 2, 'type': Obj.dDac, 'args': '', 'x': 10, 'y': 160},
          ],
          'cables': [
            if (audible) {'from': 1, 'outlet': 0, 'to': 2, 'inlet': 0},
          ],
        },
      ),
    ).toJson(),
  );

  late FakePatcherGateway gateway;
  late ProjectRegistry registry;
  late PatchReconciler reconciler;
  late List<ProjectCommand> recorded;

  PatchLibraryController build({bool audible = false}) =>
      PatchLibraryController(
        registry: registry,
        patches: reconciler,
        gateway: gateway,
        busOptions: () => const [],
        recordCommand: recorded.add,
        tutorialSource: MemoryPatchTutorialSource({
          TutorialCatalog.indexPath: jsonEncode({Obj.dSine: 'sine'}),
          TutorialCatalog.assetPathFor('sine'): tutorialFile(audible: audible),
        }),
      );

  setUp(() {
    gateway = FakePatcherGateway();
    registry = ProjectRegistry();
    recorded = [];
    reconciler = PatchReconciler(
      gateway: gateway,
      resolveBus: (_) => (channelId: null),
      onNotice: (_) {},
    );
    registry.createEntity(patch('main'), payload: PatchPayload.empty.toJson());
  });

  tearDown(() => registry.dispose());

  test('the index loads and answers hasTutorial', () async {
    final library = build();
    addTearDown(library.dispose);
    expect(library.hasTutorial(Obj.dSine), isFalse, reason: 'not loaded yet');
    await library.loadTutorials();
    expect(library.hasTutorial(Obj.dSine), isTrue);
    expect(library.hasTutorial(Obj.dDac), isFalse);
  });

  test('a missing index leaves the catalog empty', () async {
    final library = PatchLibraryController(
      registry: registry,
      patches: reconciler,
      gateway: gateway,
      busOptions: () => const [],
      tutorialSource: const MemoryPatchTutorialSource({}),
    );
    addTearDown(library.dispose);
    await library.loadTutorials();
    expect(library.tutorials.isEmpty, isTrue);
  });

  test('opening a tutorial shows a transient patcher, not a project entity, '
      'and closing it frees it', () async {
    final library = build()..open(patch('main'));
    addTearDown(library.dispose);
    await library.loadTutorials();
    final projectEditor = library.openEditor!;
    final instancesBefore = gateway.instances.length;
    final registryBefore = registry.childrenOfKind(RegistryKinds.patch).length;

    expect(await library.openTutorial(Obj.dSine), isTrue);

    final session = library.tutorial!;
    expect(session.slug, 'sine');
    expect(library.openEditor, same(session.editor));
    expect(
      session.editor.graph.nodes.map((n) => n.type),
      containsAll(['.text', Obj.dSine]),
      reason: 'the editor mirror is rebuilt from the parsed dump',
    );
    expect(gateway.instances.length, instancesBefore + 1);
    expect(
      registry.childrenOfKind(RegistryKinds.patch).length,
      registryBefore,
      reason: 'a tutorial is not a registry entity',
    );
    expect(recorded, isEmpty, reason: 'nothing is journaled');
    expect(library.openAddress, patch('main'));
    expect(
      gateway.calls,
      contains('mountAsSource:${session.instanceId}:null:1.000'),
      reason:
          'mounted even without a ~dac, so audio-clocked objects run '
          '(#528)',
    );
    expect(
      gateway.calls.where((c) => c.startsWith('mountAsSource')),
      hasLength(1),
      reason: 'only the tutorial is mounted, never the project patch (#523)',
    );

    library.closeTutorial();
    expect(library.tutorial, isNull);
    expect(library.openEditor, same(projectEditor));
    expect(gateway.calls, contains('unmountSource:${session.instanceId}'));
    expect(gateway.instances.containsKey(session.instanceId), isFalse);
  });

  test('a tutorial with a ~dac is mounted on master while open', () async {
    final library = build(audible: true)..open(patch('main'));
    addTearDown(library.dispose);
    await library.loadTutorials();
    await library.openTutorial(Obj.dSine);
    final id = library.tutorial!.instanceId;
    expect(gateway.calls, contains('mountAsSource:$id:null:1.000'));
    library.closeTutorial();
    expect(gateway.calls, contains('unmountSource:$id'));
  });

  test('a type with no tutorial opens nothing', () async {
    final library = build()..open(patch('main'));
    addTearDown(library.dispose);
    await library.loadTutorials();
    expect(await library.openTutorial(Obj.dDac), isFalse);
    expect(library.tutorial, isNull);
  });

  test('opening a project patch closes the tutorial', () async {
    final library = build()..open(patch('main'));
    addTearDown(library.dispose);
    await library.loadTutorials();
    await library.openTutorial(Obj.dSine);
    final id = library.tutorial!.instanceId;
    library.open(patch('main'));
    expect(library.tutorial, isNull);
    expect(gateway.instances.containsKey(id), isFalse);
  });

  test('copy to project mints an editable, journaled patch.tutorials entity '
      'and opens it', () async {
    final library = build()..open(patch('main'));
    addTearDown(library.dispose);
    await library.loadTutorials();
    await library.openTutorial(Obj.dSine);

    final copy = library.copyTutorialToProject()!;

    expect(
      copy,
      EntityAddress(kind: RegistryKinds.patch, segments: ['tutorials', 'sine']),
    );
    expect(recorded, hasLength(1));
    expect(library.tutorial, isNull);
    expect(library.openAddress, copy);
    expect(
      library.openEditor!.graph.nodes.map((n) => n.type),
      containsAll(['.text', Obj.dSine]),
    );
    // Undoable: reverting the recorded command removes the copy.
    recorded.single.revert();
    expect(registry.contains(copy), isFalse);
  });

  test('a session restart and dispose close the tutorial', () async {
    final library = build()..open(patch('main'));
    await library.loadTutorials();
    await library.openTutorial(Obj.dSine);
    final id = library.tutorial!.instanceId;
    library.releaseEditors();
    expect(library.tutorial, isNull);
    expect(gateway.instances.containsKey(id), isFalse);

    await library.openTutorial(Obj.dSine);
    final id2 = library.tutorial!.instanceId;
    library.dispose();
    expect(gateway.instances.containsKey(id2), isFalse);
  });

  test('requestTutorialBrowser bumps the request counter', () {
    final library = build();
    addTearDown(library.dispose);
    var heard = 0;
    library.tutorialBrowserRequests.addListener(() => heard++);
    library.requestTutorialBrowser();
    expect(heard, 1);
  });

  test('export writes the open project patch in the tutorial format', () async {
    final library = build()..open(patch('main'));
    addTearDown(library.dispose);
    gateway.createObject(library.openEditor!.instanceId, Obj.dSine);

    final json = library.exportOpenAsTutorial()!;
    final back = PatchTutorial.fromJson(
      (jsonDecode(json) as Map).cast<String, Object?>(),
    );
    expect(back.title, 'main');
    expect(back.covers, isEmpty);
    expect((back.payload.dump['objects']! as List), hasLength(1));

    await library.loadTutorials();
    await library.openTutorial(Obj.dSine);
    expect(library.exportOpenAsTutorial(), isNull, reason: 'not a tutorial');
  });
}
