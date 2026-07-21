import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/code/code_script.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/engine/state/code_library_controller.dart';

EntityAddress _addr(String dotted) => EntityAddress.parse(dotted);

Map<String, Object?> _payload([String source = '']) =>
    CodeScript(source: source).toJson();

String _sourceOf(ProjectRegistry registry, String dotted) {
  final payload = registry.entityAt(_addr(dotted))!.payload;
  if (payload is CodeScript) return payload.source;
  return CodeScript.fromJson((payload! as Map).cast()).source;
}

void main() {
  const idle = Duration(milliseconds: 300);

  group('CodeLibraryController — tree + structural commands', () {
    late ProjectRegistry registry;
    late List<ProjectCommand> recorded;
    late CodeLibraryController controller;

    setUp(() {
      registry = ProjectRegistry();
      recorded = [];
      controller = CodeLibraryController(
        registry: registry,
        recordCommand: recorded.add,
        idleDelay: idle,
      );
    });

    tearDown(() {
      controller.dispose();
      registry.dispose();
    });

    void seedTree() {
      registry.createEntity(_addr('code.a'), payload: _payload());
      registry.createEntity(_addr('code.utils.gain'), payload: _payload());
      registry.createEntity(_addr('code.utils.env'), payload: _payload());
      registry.createEntity(_addr('code.b'), payload: _payload());
    }

    test('renders the code.* namespace as an ordered tree with groups', () {
      seedTree();

      final tree = controller.tree;
      expect(tree.map((n) => n.name), ['a', 'utils', 'b']);

      final utils = tree[1];
      expect(utils.isGroup, isTrue);
      expect(utils.children.map((n) => n.name), ['gain', 'env']);
      expect(tree.first.isGroup, isFalse);
    });

    test('the tree re-renders (notifies) when the registry mutates', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      registry.createEntity(_addr('code.a'), payload: _payload());

      expect(notifications, greaterThan(0));
      expect(controller.tree, hasLength(1));
    });

    test('newScript creates + records + opens the fresh script', () {
      final created = controller.newScript();

      expect(registry.entityAt(created), isNotNull);
      expect(controller.openAddress, created);
      expect(recorded, hasLength(1));
    });

    test('newGroup creates a group folder + records', () {
      final group = controller.newGroup();

      expect(registry.groupAt(group), isNotNull);
      expect(recorded, hasLength(1));
    });

    test('duplicate copies the source to <name>_copy + opens it', () {
      registry.createEntity(_addr('code.a'), payload: _payload('print(1)\n'));

      final copy = controller.duplicate(_addr('code.a'));

      expect(copy, _addr('code.a_copy'));
      expect(_sourceOf(registry, 'code.a_copy'), 'print(1)\n');
      expect(controller.openAddress, copy);
    });

    test('rename moves the entity to the slug of the new name (refactor)', () {
      registry.createEntity(_addr('code.a'), payload: _payload());

      controller.rename(_addr('code.a'), 'lead riff');

      expect(registry.contains(_addr('code.a')), isFalse);
      expect(registry.contains(_addr('code.lead_riff')), isTrue);
      expect(recorded, hasLength(1));
    });

    test('renaming the open script re-opens it at the new address', () {
      registry.createEntity(_addr('code.a'), payload: _payload('body\n'));
      controller.select(_addr('code.a'));

      controller.rename(_addr('code.a'), 'renamed');

      expect(controller.openAddress, _addr('code.renamed'));
      expect(controller.openSource, 'body\n');
    });

    test('renaming a non-first open script keeps ITS source (not first)', () {
      registry.createEntity(_addr('code.a'), payload: _payload('aaa\n'));
      registry.createEntity(_addr('code.b'), payload: _payload('bbb\n'));
      controller.select(_addr('code.b'));

      controller.rename(_addr('code.b'), 'renamed');

      // The editor follows b to its new address with b's own source — the
      // mid-move notification must not re-home it onto the first script (a).
      expect(controller.openAddress, _addr('code.renamed'));
      expect(controller.openSource, 'bbb\n');
    });

    test('regrouping the open script re-opens it at the new address', () {
      registry.createEntity(_addr('code.a'), payload: _payload('aaa\n'));
      registry.createEntity(_addr('code.b'), payload: _payload('bbb\n'));
      registry.createGroup(_addr('code.utils'));
      controller.select(_addr('code.b'));

      controller.regroup(_addr('code.b'), _addr('code.utils'));

      expect(controller.openAddress, _addr('code.utils.b'));
      expect(controller.openSource, 'bbb\n');
    });

    test('delete removes the node + records', () {
      registry.createEntity(_addr('code.a'), payload: _payload());
      registry.createEntity(_addr('code.b'), payload: _payload());

      controller.delete(_addr('code.b'));

      expect(registry.contains(_addr('code.b')), isFalse);
      expect(recorded, hasLength(1));
    });

    test('deleting the open script re-homes the editor onto a survivor', () {
      registry.createEntity(_addr('code.a'), payload: _payload('aaa\n'));
      registry.createEntity(_addr('code.b'), payload: _payload('bbb\n'));
      controller.select(_addr('code.b'));
      expect(controller.openAddress, _addr('code.b'));

      controller.delete(_addr('code.b'));

      expect(controller.openAddress, _addr('code.a'));
      expect(controller.openSource, 'aaa\n');
    });

    test('regroup re-parents a script into a group (drag-to-group)', () {
      registry.createEntity(_addr('code.a'), payload: _payload());
      registry.createGroup(_addr('code.utils'));

      controller.regroup(_addr('code.a'), _addr('code.utils'));

      expect(registry.contains(_addr('code.a')), isFalse);
      expect(registry.contains(_addr('code.utils.a')), isTrue);
    });

    test('reorderBefore reorders within a section', () {
      seedTree();
      controller.reorderBefore(_addr('code.b'), _addr('code.a'));

      expect(controller.tree.map((n) => n.name), ['b', 'a', 'utils']);
      expect(recorded.last.toJson()['type'], 'reorder_child');
    });
  });

  group('CodeLibraryController — open-swap + revision', () {
    test('opens the first script on construction (scratch-alive)', () {
      final registry = ProjectRegistry();
      registry.createEntity(_addr('code.scratch'), payload: _payload('seed\n'));

      final controller = CodeLibraryController(registry: registry);
      addTearDown(() {
        controller.dispose();
        registry.dispose();
      });

      expect(controller.openAddress, _addr('code.scratch'));
      expect(controller.openSource, 'seed\n');
    });

    test('select swaps the open script + bumps the revision', () {
      final registry = ProjectRegistry();
      registry.createEntity(_addr('code.a'), payload: _payload('aaa\n'));
      registry.createEntity(_addr('code.b'), payload: _payload('bbb\n'));
      final controller = CodeLibraryController(registry: registry);
      addTearDown(() {
        controller.dispose();
        registry.dispose();
      });

      final before = controller.openRevision;
      final opened = controller.openAddress;
      final other = opened == _addr('code.a')
          ? _addr('code.b')
          : _addr('code.a');

      controller.select(other);

      expect(controller.openAddress, other);
      expect(controller.openRevision, greaterThan(before));
    });

    test('selecting the already-open script is a no-op (no revision bump)', () {
      final registry = ProjectRegistry();
      registry.createEntity(_addr('code.a'), payload: _payload('aaa\n'));
      final controller = CodeLibraryController(registry: registry);
      addTearDown(() {
        controller.dispose();
        registry.dispose();
      });

      final rev = controller.openRevision;
      controller.select(controller.openAddress!);
      expect(controller.openRevision, rev);
    });
  });

  group('CodeLibraryController — journaled edits (coalesced)', () {
    test(
      'an edit burst journals one UpdateEntityPayloadCommand per idle pause',
      () {
        fakeAsync((async) {
          final registry = ProjectRegistry();
          final recorded = <ProjectCommand>[];
          registry.createEntity(_addr('code.a'), payload: _payload('a = 1\n'));
          final controller = CodeLibraryController(
            registry: registry,
            recordCommand: recorded.add,
            idleDelay: idle,
          );

          // Three rapid keystrokes inside one idle window → coalesced to one.
          controller.onEditorChanged('a = 1\nb');
          async.elapse(const Duration(milliseconds: 50));
          controller.onEditorChanged('a = 1\nb =');
          async.elapse(const Duration(milliseconds: 50));
          controller.onEditorChanged('a = 1\nb = 2\n');
          expect(recorded, isEmpty); // nothing journaled mid-burst

          async.elapse(idle);

          expect(recorded, hasLength(1));
          expect(recorded.single.toJson()['type'], 'update_payload');
          expect(_sourceOf(registry, 'code.a'), 'a = 1\nb = 2\n');

          // A settle with identical text does not journal again (de-duped).
          controller.onEditorChanged('a = 1\nb = 2\n');
          async.elapse(idle);
          expect(recorded, hasLength(1));

          controller.dispose();
          registry.dispose();
        });
      },
    );

    test('flushPendingEdits journals immediately (before the idle pause)', () {
      fakeAsync((async) {
        final registry = ProjectRegistry();
        final recorded = <ProjectCommand>[];
        registry.createEntity(_addr('code.a'), payload: _payload('a\n'));
        final controller = CodeLibraryController(
          registry: registry,
          recordCommand: recorded.add,
          idleDelay: idle,
        );

        controller.onEditorChanged('a\nnew\n');
        controller.flushPendingEdits();

        expect(recorded, hasLength(1));
        expect(_sourceOf(registry, 'code.a'), 'a\nnew\n');

        async.elapse(idle); // the cancelled timer never re-fires
        expect(recorded, hasLength(1));

        controller.dispose();
        registry.dispose();
      });
    });

    test('selecting another script flushes the pending edit first (guard)', () {
      fakeAsync((async) {
        final registry = ProjectRegistry();
        final recorded = <ProjectCommand>[];
        registry.createEntity(_addr('code.a'), payload: _payload('aaa\n'));
        registry.createEntity(_addr('code.b'), payload: _payload('bbb\n'));
        final controller = CodeLibraryController(
          registry: registry,
          recordCommand: recorded.add,
          idleDelay: idle,
        );
        controller.select(_addr('code.a'));

        // Type into A but do NOT wait out the idle pause, then swap to B.
        controller.onEditorChanged('aaa\nedited\n');
        controller.select(_addr('code.b'));

        // The un-idled edit to A was flushed on the swap — never lost.
        expect(_sourceOf(registry, 'code.a'), 'aaa\nedited\n');
        expect(recorded, hasLength(1));
        expect(controller.openAddress, _addr('code.b'));
        expect(controller.openSource, 'bbb\n');

        async.elapse(idle);
        expect(recorded, hasLength(1));

        controller.dispose();
        registry.dispose();
      });
    });
  });
}
