import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_type_name.dart';
import 'package:phi/domain/patcher/tutorial/patch_tutorial.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_catalog.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_slug.dart';
import 'package:phi/engine/bridge/patcher_graph_snapshot.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:yse/yse.dart';

/// The **bundled tutorials** against the real engine, headless (issue #489):
/// every index entry points at a file that exists, every indexed and covered
/// type is in the engine's catalogue, and every tutorial's dump `parseJson`s
/// into a patch with objects in it. A non-failing report lists the object
/// types that still have no tutorial.
///
/// This is the test a content issue (#490–#510) leans on: add the file, add
/// the index lines, and this proves the tutorial loads on the engine Phi ships.
void main() {
  late RealPatcherGateway gateway;
  late Set<String> engineTypes;
  var engineUp = false;

  final index = TutorialCatalog.fromJson(
    (jsonDecode(File(TutorialCatalog.indexPath).readAsStringSync()) as Map)
        .cast<String, Object?>(),
  );

  PatchTutorial load(String slug) => PatchTutorial.fromJson(
    (jsonDecode(
      File(TutorialCatalog.assetPathFor(slug)).readAsStringSync(),
    ) as Map).cast<String, Object?>(),
  );

  setUpAll(() {
    System.instance
      ..requestedSampleRate = 48000
      ..initOffline();
    engineUp = true;
    gateway = RealPatcherGateway();
    engineTypes = {for (final d in gateway.objectTypes()) d.type};
  });

  tearDownAll(() {
    if (!engineUp) return;
    gateway.disposeAll();
    System.instance.close();
  });

  test('the index is not empty', () {
    expect(index.isEmpty, isFalse);
  });

  test('every index entry points at an existing tutorial file', () {
    for (final slug in index.slugs) {
      expect(
        File(TutorialCatalog.assetPathFor(slug)).existsSync(),
        isTrue,
        reason: 'index names "$slug" but its file is missing',
      );
    }
  });

  test('every tutorial file in the folder is indexed', () {
    final files = Directory(TutorialCatalog.assetDir)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith(TutorialCatalog.extension))
        .map((n) => n.substring(0, n.length - TutorialCatalog.extension.length))
        .toSet();
    expect(files, index.slugs);
  });

  test('every indexed and covered type exists in the engine catalogue', () {
    for (final type in index.types) {
      expect(engineTypes, contains(type), reason: 'index entry $type');
    }
    for (final slug in index.slugs) {
      final tutorial = load(slug);
      expect(tutorial.covers, isNotEmpty, reason: '$slug covers nothing');
      for (final type in tutorial.covers) {
        expect(engineTypes, contains(type), reason: '$slug covers $type');
        expect(
          index.tutorialFor(type),
          slug,
          reason: '$slug covers $type but the index does not point there',
        );
      }
    }
  });

  test('a single-type tutorial is named by the slug rule', () {
    for (final slug in index.slugs) {
      final types = index.typesFor(slug);
      if (types.length != 1) continue;
      expect(
        slug,
        TutorialSlug.of(types.single, knownTypes: engineTypes),
        reason: '${types.single} is stored as "$slug"',
      );
    }
  });

  test('every tutorial parses on the real engine and has a title note', () {
    for (final slug in index.slugs) {
      final tutorial = load(slug);
      final inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(tutorial.payload.dump));
      final graph = gateway.enumerate(inst);
      expect(graph.objects, isNotEmpty, reason: '$slug parsed to nothing');
      expect(
        graph.objects.any((o) => PatchTypeName.isNote(o.type)),
        isTrue,
        reason: '$slug has no note explaining it',
      );
      gateway.disposeInstance(inst);
    }
  });

  test('the metro tutorial sets itself up on load', () {
    final tutorial = load('metro');
    final inst = gateway.createInstance();
    gateway.parseJson(inst, jsonEncode(tutorial.payload.dump));
    final graph = gateway.enumerate(inst);
    final numbers = [
      for (final o in graph.objects)
        if (o.type == '.i') o.handleId,
    ];
    // `.loadmess 500` fills the interval box when the patch loads.
    expect(
      numbers.map((id) => gateway.guiValue(inst, id)),
      contains(startsWith('500')),
    );
    gateway.disposeInstance(inst);
  });

  test('every GUI basics type has a tutorial (#490)', () {
    for (final type in ['.b', '.t', '.slider', '.i', '.f', '.m', '.text']) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.i'), index.tutorialFor('.f'));
  });

  group('GUI basics tutorials (#490) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void open(String slug) {
      inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
    }

    tearDown(() => gateway.disposeInstance(inst));

    // An object by type and its place on the canvas — tutorials repeat types.
    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    // A message box by its text.
    int msg(String text) => graph.objects
        .firstWhere((o) => o.type == '.m' && o.args == text)
        .handleId;
    void click(int id) => gateway.sendBang(inst, id, 0);
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));

    test('b: a click, a number and the metro all press the button', () {
      open('b');
      final count = at('.i', 60, 400);
      click(at('.b', 60, 260));
      expect(value(count), '1');
      click(msg('42'));
      expect(value(count), '2', reason: 'a number presses it like a bang');
      gateway.sendInt(inst, at('.t', 60, 130), 0, 1);
      expect(value(count), '3', reason: 'the metro presses it as it starts');
      gateway.sendInt(inst, at('.t', 60, 130), 0, 0);
    });

    test('t: an int sets it, a bang flips it, and it gates the metro', () {
      open('t');
      final toggle = at('.t', 60, 210);
      final state = at('.i', 60, 290);
      final ticks = at('.i', 180, 410);
      click(msg('7'));
      expect((value(toggle), value(state)), ('on', '1'));
      expect(value(ticks), '1', reason: 'the metro started and ticked');
      click(msg('0'));
      expect((value(toggle), value(state)), ('off', '0'));
      click(at('.b', 390, 130));
      expect(value(state), '1', reason: 'a bang flips it');
      click(at('.b', 390, 130));
      expect(value(state), '0');
    });

    test('slider: loads at 0.5, clamps, and scales to 200–2000 Hz', () {
      open('slider');
      final position = at('.f', 60, 360);
      final hz = at('.f', 170, 420);
      expect((number(position), number(hz)), (0.5, 1100.0));
      click(msg('0.25'));
      expect((number(position), number(hz)), (0.25, 650.0));
      click(msg('2'));
      expect((number(position), number(hz)), (1.0, 2000.0), reason: 'clamped');
      expect(
        graph.objects.map((o) => o.type),
        contains('~dac'),
        reason: 'audible, so it plays on master',
      );
    });

    test('number boxes: hot and cold inlets, resend, truncation', () {
      open('number-boxes');
      final box = at('.i', 60, 200);
      final below = at('.i', 60, 270);
      click(msg('7'));
      expect((value(box), value(below)), ('7', '7'));
      click(msg('99'));
      expect((value(box), value(below)), ('99', '7'), reason: 'cold inlet');
      click(at('.b', 280, 130));
      expect(value(below), '99', reason: 'a bang resends');
      final i = at('.i', 60, 420);
      final f = at('.f', 170, 420);
      click(msg('2.9'));
      expect((value(i), number(f)), ('2', 2.9));
      click(msg('-2.9'));
      expect((value(i), number(f)), ('-2', -2.9), reason: 'toward zero');
    });

    test('m: numbers, bang, a command, and replacement from the inlet', () {
      open('m');
      click(msg('440'));
      expect(value(at('.i', 60, 190)), '440');
      click(msg('0.5'));
      expect(number(at('.f', 170, 190)), 0.5);
      final count = at('.i', 60, 440);
      click(msg('bang'));
      expect(value(count), '1');
      click(msg('1'));
      expect(value(count), '2', reason: 'the metro started');
      click(msg('stop'));
      final out = at('.i', 60, 650);
      final target = msg('0');
      click(msg('1 2 3'));
      expect(value(out), '0', reason: 'replacing sends nothing');
      click(target);
      expect(value(out), '1', reason: 'it now sends 1 2 3');
      click(msg('7 8 9'));
      click(target);
      expect(value(out), '7');
    });

    test('text: notes have no ports', () {
      open('text');
      final notes = graph.objects.where((o) => PatchTypeName.isNote(o.type));
      expect(notes.length, greaterThanOrEqualTo(5));
      for (final n in notes) {
        expect((n.ports.inputs, n.ports.outputs), (0, 0));
      }
    });
  });

  test('every single-value control has a tutorial (#491)', () {
    for (final type in [
      '.dial',
      '.incdec',
      '.led',
      '.textbutton',
      '.textedit',
      '.l',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  group('single-value control tutorials (#491) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void open(String slug) {
      inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
    }

    tearDown(() => gateway.disposeInstance(inst));

    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    int msg(String text) => graph.objects
        .firstWhere((o) => o.type == '.m' && o.args == text)
        .handleId;
    void click(int id) => gateway.sendBang(inst, id, 0);
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));

    test('dial: a range, an exponent of 1 against 3, and intMode', () {
      open('dial');
      final linear = at('.f', 60, 290);
      final curved = at('.f', 170, 290);
      click(msg('0.5'));
      expect((number(linear), number(curved)), (500.0, 125.0));
      expect(number(at('.dial', 170, 200)), 0.5, reason: 'stores position');
      click(msg('1'));
      expect((number(linear), number(curved)), (1000.0, 1000.0));
      click(msg('0'));
      expect((number(linear), number(curved)), (0.0, 0.0));
      click(msg('0.75'));
      expect(value(at('.i', 60, 550)), '8', reason: 'a half rounds up');
      expect(number(at('.f', 170, 550)), 7.5);
    });

    test('incdec: inc/dec, nudge, step, silent set, clamp and wrap', () {
      open('incdec');
      final stepper = at('.incdec', 60, 270);
      final out = at('.i', 60, 340);
      // Two message boxes say inc: this one, and the wrap demo's below.
      final inc = at('.m', 60, 140);
      click(inc);
      expect(value(out), '1');
      click(msg('dec'));
      click(msg('dec'));
      expect(value(out), '0', reason: 'clamped at the minimum');
      click(msg('3'));
      expect(value(out), '3');
      click(msg('-3'));
      expect(value(out), '0');
      click(msg('5'));
      click(inc);
      expect(value(out), '5', reason: 'step 5');
      click(msg('1'));
      click(msg('7'));
      expect((value(stepper), value(out)), ('7', '5'), reason: 'silent set');
      click(at('.b', 170, 200));
      expect(value(out), '7', reason: 'a bang sends');
      for (var i = 0; i < 30; i++) {
        click(inc);
      }
      expect(value(out), '20', reason: 'clamped at the maximum');
      final wrapInc = at('.m', 60, 450);
      final clamped = at('.i', 60, 580);
      final wrapped = at('.i', 200, 580);
      for (var i = 0; i < 4; i++) {
        click(wrapInc);
      }
      expect((value(clamped), value(wrapped)), ('3', '0'));
    });

    test('led: latching, momentary presses, and labels', () {
      open('led');
      final state = at('.i', 60, 270);
      click(msg('1'));
      expect(value(state), '1');
      click(at('.b', 280, 140));
      expect(value(state), '0', reason: 'a bang flips it');
      gateway.sendInt(inst, at('.led', 60, 200), 0, 7);
      expect(value(state), '1', reason: 'any number but 0 is on');
      final presses = at('.i', 60, 590);
      gateway.sendBang(inst, at('.led', 60, 410), 0);
      click(at('.m', 60, 350));
      expect(value(presses), '2', reason: 'even 0 is a press');
      final field = at('.textedit', 60, 750);
      gateway.sendBang(inst, at('.led', 170, 680), 0);
      expect(value(field), 'green');
      gateway.sendBang(inst, at('.led', 280, 680), 0);
      expect(value(field), 'blue');
    });

    test('textbutton: latching mute, and a bank selecting through route', () {
      open('textbutton');
      final state = at('.i', 60, 270);
      gateway.sendInt(inst, at('.textbutton', 60, 200), 0, 1);
      expect(value(state), '1');
      click(at('.b', 280, 140));
      expect(value(state), '0');
      final speed = at('.i', 60, 580);
      gateway.sendInt(inst, at('.textbutton', 170, 370), 0, 1);
      expect(value(speed), '250');
      gateway.sendInt(inst, at('.textbutton', 280, 370), 0, 1);
      expect(value(speed), '125');
      gateway.sendInt(inst, at('.textbutton', 60, 370), 0, 1);
      expect(value(speed), '500');
    });

    test('textedit: typed text as a list, sprintf, resend and clear', () {
      open('textedit');
      final field = at('.textedit', 60, 210);
      final result = at('.l', 60, 350);
      final sends = at('.i', 230, 470);
      expect(value(field), 'world');
      gateway.sendList(inst, field, 0, 'Bob');
      expect(value(result), 'hello Bob');
      expect(value(sends), '1');
      click(msg('Ann'));
      expect((value(field), value(result)), ('Ann', 'hello Ann'));
      click(at('.b', 170, 140));
      expect(value(sends), '3', reason: 'a bang resends');
      click(at('.l', 220, 140));
      expect(value(field), '', reason: 'an empty list clears it');
    });

    test('l: collects from pack silently, sends on demand', () {
      open('l');
      final box = at('.l', 60, 280);
      final a = at('.i', 60, 420);
      final b = at('.i', 170, 420);
      click(msg('7'));
      click(msg('60'));
      expect(value(box), '60 7');
      expect((value(a), value(b)), ('0', '0'), reason: 'stored silently');
      click(box);
      expect((value(a), value(b)), ('60', '7'));
      click(msg('64'));
      expect(value(box), '64 7');
      expect(value(a), '60', reason: 'still silent');
      click(at('.b', 200, 280));
      expect((value(a), value(b)), ('64', '7'));
    });
  });

  test('report: object types with no tutorial yet', () {
    final missing = [
      for (final t in engineTypes.toList()..sort())
        if (!index.hasTutorial(t) && t != 'patcher') t,
    ];
    // ignore: avoid_print
    print(
      'tutorials: ${index.types.length} of ${engineTypes.length} types '
      'covered; without one: ${missing.join(' ')}',
    );
  });
}
