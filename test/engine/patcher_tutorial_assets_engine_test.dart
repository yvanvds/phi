import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
      // Replacement from the inlet, with the list built by pack: a
      // multi-word message box keeps only its first word on libYSE 3.1.0
      // (#521), which the note says.
      final list = at('.l', 60, 690);
      final target = msg('0');
      List<String> cells(int id) => [
        for (var k = 0; k < gateway.guiValueCount(inst, id); k++)
          gateway.guiValueAt(inst, id, k),
      ];
      final before = cells(list);
      click(at('.b', 60, 520));
      expect(cells(list), before, reason: 'replacing sends nothing');
      expect(cells(target).join(' '), '1 2 3', reason: 'the whole list stored');
      click(target);
      expect(cells(list).join(' '), '1 2 3', reason: 'it now sends 1 2 3');
      expect(
        graph.objects.where((o) => o.type == '.m' && o.args.contains(' ')),
        isEmpty,
        reason: 'no multi-word message box until the engine keeps all words',
      );
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

  test('every selection and slider control has a tutorial (#492)', () {
    for (final type in [
      '.umenu',
      '.radiogroup',
      '.tab',
      '.rslider',
      '.xyslider',
      '.multislider',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.umenu'), 'menus');
    expect(index.tutorialFor('.radiogroup'), 'menus');
    expect(index.tutorialFor('.tab'), 'menus');
  });

  group('selection and slider control tutorials (#492) do what their notes '
      'say', () {
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
    void click(int id) => gateway.sendBang(inst, id, 0);
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));
    // A multi-value control's state, or a list of numbers, as numbers.
    List<double> numbers(int id) => [
      for (final t in value(id).split(' ')) double.parse(t),
    ];

    test('menus: one protocol in three drawings, three outlets, multi', () {
      open('menus');
      final menu = at('.umenu', 60, 200);
      final radio = at('.radiogroup', 220, 200);
      final tabs = at('.tab', 360, 200);
      final index = at('.i', 60, 310);
      final name = at('.l', 150, 310);
      final state = at('.l', 270, 310);
      click(at('.m', 60, 140)); // 2
      expect([value(menu), value(radio), value(tabs)], ['2', '2', '2']);
      expect((value(index), value(name), value(state)), ('2', 'noise', '2'));
      click(at('.m', 170, 140)); // saw
      expect([value(menu), value(radio), value(tabs)], ['1', '1', '1']);
      expect((value(index), value(name), value(state)), ('1', 'saw', '1'));
      gateway.sendInt(inst, menu, 0, 7);
      gateway.sendList(inst, menu, 0, 'square');
      expect(value(menu), '1', reason: 'out of range and unknown: ignored');
      gateway.sendInt(inst, menu, 0, 0);
      expect((value(index), value(name)), ('0', 'sine'));
      expect(value(radio), '1', reason: 'separate objects');

      final multi = at('.radiogroup', 60, 460);
      final changed = at('.i', 200, 570);
      final flags = at('.l', 300, 570);
      click(at('.m', 60, 400)); // 1 toggles saw on
      expect((value(flags), value(changed)), ('0 1 0', '1'));
      click(at('.m', 60, 400));
      expect(value(flags), '0 0 0', reason: 'toggled off again');
      click(at('.b', 220, 380)); // pack 1 0 1
      expect((value(flags), value(changed)), ('1 0 1', '0'));
      expect(value(multi), '1 0 1');
      expect(graph.objects.map((o) => o.type), contains('~dac'));
    });

    test('rslider: a silent end, sorted ends, set, and a random range', () {
      open('rslider');
      final low = at('.f', 60, 380);
      final high = at('.f', 150, 380);
      final both = at('.l', 240, 380);
      click(at('.m', 60, 140)); // 48 -> right inlet
      expect(value(both), '', reason: 'the right inlet is silent');
      click(at('.m', 170, 140)); // 84 -> left inlet
      expect((number(low), number(high)), (48.0, 84.0));
      click(at('.b', 280, 140)); // pack 90 40
      expect((number(low), number(high)), (40.0, 90.0), reason: 'sorted');
      expect(numbers(both), [40, 90]);
      click(at('.m', 390, 140)); // 60 -> prepend set 0
      expect((number(low), number(high)), (60.0, 90.0));
      gateway.sendList(inst, at('.rslider', 60, 200), 0, '10 120');
      expect((number(low), number(high)), (36.0, 96.0), reason: 'clamped');
      gateway.sendList(inst, at('.rslider', 60, 200), 0, '70 72');
      final out = at('.f', 60, 650);
      for (var i = 0; i < 40; i++) {
        click(at('.b', 60, 470));
        expect(number(out), inInclusiveRange(70, 72));
      }
    });

    test('xyslider: x sends, y is silent, set per axis, the pair', () {
      open('xyslider');
      final pad = at('.xyslider', 60, 200);
      final x = at('.f', 60, 360);
      final y = at('.f', 150, 360);
      final pair = at('.l', 240, 360);
      click(at('.m', 60, 140)); // 300
      expect(number(x), 300.0);
      click(at('.m', 170, 140)); // 2000 -> right inlet
      expect(number(y), isNot(2000.0), reason: 'the right inlet is silent');
      click(at('.b', 280, 140));
      expect((number(x), number(y)), (300.0, 2000.0));
      expect(numbers(pair), [300, 2000]);
      click(at('.m', 330, 140)); // 4000 -> prepend set 1
      expect((number(x), number(y)), (300.0, 4000.0));
      gateway.sendFloat(inst, pad, 0, 5000);
      expect(number(x), 1000.0, reason: 'clamped to its own range');
      expect(graph.objects.map((o) => o.type), contains('~dac'));
    });

    test('multislider: loads a pattern, fetches steps, resizes, fills', () {
      open('multislider');
      final bank = at('.multislider', 60, 260);
      final note = at('.f', 170, 470);
      final count = at('.counter', 280, 380);
      expect(numbers(bank), [0, 3, 7, 10, 12, 10, 7, 3], reason: 'loadmess');
      final heard = <double>[];
      for (var i = 0; i < 8; i++) {
        click(count);
        heard.add(number(note));
      }
      expect(heard, [48, 51, 55, 58, 60, 58, 55, 51]);
      expect(value(at('.i', 400, 440)), '7');
      click(at('.m', 200, 140)); // 12
      expect(numbers(bank), [12, 12, 12, 12, 12, 12, 12, 12]);
      click(at('.b', 330, 140)); // pack 0 4 7 12
      expect(numbers(bank), [0, 4, 7, 12], reason: 'resized');
      heard.clear();
      for (var i = 0; i < 8; i++) {
        click(count);
        heard.add(number(note));
      }
      expect(heard, [48, 52, 55, 60, 60, 60, 60, 60]);
      click(at('.b', 60, 140)); // loadmess again
      expect(numbers(bank), [0, 3, 7, 10, 12, 10, 7, 3]);
      expect(graph.objects.map((o) => o.type), contains('~dac'));
    });
  });

  test('every structured control has a tutorial (#493)', () {
    for (final type in [
      '.matrixctrl',
      '.function',
      '.nodes',
      '.preset',
      '.kslider',
      '.nslider',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  group('structured control tutorials (#493) do what their notes say', () {
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
    void click(int id) => gateway.sendBang(inst, id, 0);
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));
    List<double> numbers(int id) => [
      for (final t in value(id).split(' '))
        if (t.isNotEmpty) double.parse(t),
    ];

    test('matrixctrl: a patchbay into router, a stepped column, clear', () {
      open('matrixctrl');
      // The patchbay: column 0 row 1 sends the first input to the second
      // output, through pack 0 0 0 (#522).
      final bay = at('.matrixctrl', 330, 140);
      final left = at('.i', 330, 360);
      final right = at('.i', 420, 360);
      gateway.sendList(inst, bay, 0, '0 1 1');
      expect(numbers(at('.l', 420, 140)), [0, 1, 1], reason: 'the cell form');
      click(at('.m', 450, 200)); // 100
      expect((value(left), value(right)), ('0', '100'));
      gateway.sendList(inst, bay, 0, '1 0 1');
      click(at('.m', 450, 250)); // 200
      expect((value(left), value(right)), ('200', '100'));
      gateway.sendList(inst, bay, 0, '0 0 1');
      click(at('.m', 450, 200));
      expect(value(left), '100', reason: 'both inputs share an output');

      // The sequencer: hits on step 3, rows 0 and 2.
      final grid = at('.matrixctrl', 60, 420);
      final column = at('.l', 200, 500);
      expect(gateway.guiValueCount(inst, grid), 64, reason: '16 by 4');
      gateway.sendList(inst, grid, 0, '3 0 1');
      gateway.sendList(inst, grid, 0, '3 2 1');
      expect(numbers(at('.l', 60, 500)), [3, 2, 1]);
      final counter = at('.counter', 60, 240);
      for (var i = 0; i < 4; i++) {
        click(counter);
      }
      expect(value(at('.i', 190, 290)), '3');
      expect(numbers(column), [1, 0, 1, 0], reason: 'getcolumn 3');
      click(at('.m', 190, 140)); // clear
      for (var i = 0; i < 16; i++) {
        click(counter);
      }
      expect(numbers(column), [0, 0, 0, 0]);
      expect(graph.objects.map((o) => o.type), contains('~dac'));
    });

    test('function: saved points, the ramp, y for x, a curve, dump', () {
      open('function');
      final fn = at('.function', 60, 200);
      expect(
        [
          for (var i = 0; i < gateway.guiValueCount(inst, fn); i++)
            gateway.guiValueAt(inst, fn, i),
        ],
        ['0. 0. 0.', '30. 1. 0.', '120. 0.5 0.', '600. 0. 0.'],
        reason: 'the points come back with the patch',
      );
      final ramp = at('.l', 150, 340);
      click(at('.b', 60, 140));
      expect(numbers(ramp), [0, 0, 1, 30, 0.5, 90, 0, 480]);
      final y = at('.f', 60, 340);
      click(at('.m', 150, 140)); // 15
      expect(number(y), closeTo(0.5, 1e-6));
      click(at('.m', 260, 140)); // 300
      expect(number(y), closeTo(0.3125, 1e-6));
      click(at('.m', 370, 200)); // 0.5 -> setcurve 3 0.5
      click(at('.m', 260, 140));
      expect(number(y), closeTo(0.5 - 0.5 * 0.375 * 0.375 * 0.375, 1e-4));
      click(at('.b', 60, 140));
      expect(numbers(ramp), [
        0,
        0,
        1,
        30,
        0.5,
        90,
        0,
        480,
      ], reason: 'the ramp ignores curves');
      click(at('.m', 370, 140)); // dump
      expect(numbers(at('.l', 300, 340)), [3, 600, 0, 0.5]);
      expect(graph.objects.map((o) => o.type), contains('~dac'));
    });

    test('nodes: a layout on load, weights sum to 1 inside, 0 outside', () {
      open('nodes');
      final field = at('.nodes', 60, 250);
      expect(numbers(field), [
        0.25, 0.25, 0.3, 0.75, 0.25, 0.3, //
        0.25, 0.75, 0.3, 0.75, 0.75, 0.3,
      ], reason: 'loadmess');
      final weights = at('.l', 60, 440);
      click(at('.b', 260, 250)); // 0.5 0.25
      expect(numbers(weights), [0.5, 0.5, 0, 0]);
      click(at('.b', 400, 250)); // the middle
      expect(numbers(weights), [0, 0, 0, 0], reason: 'inside no node');
      gateway.sendList(inst, field, 0, '0.48 0.25');
      final w = numbers(weights);
      expect(w[0], greaterThan(w[1]), reason: 'nearer the first node');
      expect(w[1], greaterThan(0));
      expect(w.reduce((a, b) => a + b), closeTo(1, 1e-5));
      expect(numbers(at('.l', 260, 440)), hasLength(4), reason: 'distances');
      expect(graph.objects.map((o) => o.type), contains('~dac'));
    });

    test('preset: shipped slots recall, empty sends nothing, store', () {
      open('preset');
      final bank = at('.preset', 60, 680);
      final note = at('.i', 250, 140);
      final recalled = at('.i', 60, 740);
      click(at('.m', 170, 560)); // 1
      expect(value(note), '57');
      expect(value(at('.t', 60, 140)), 'on');
      expect(number(at('.slider', 440, 140)), closeTo(0.6, 1e-6));
      expect(number(at('.f', 340, 200)), closeTo(220, 0.01), reason: 'sent on');
      expect(value(recalled), '1');
      click(at('.m', 280, 560)); // 2
      expect((value(note), value(recalled)), ('52', '2'));
      click(at('.m', 390, 560)); // 5: empty
      expect((value(note), value(recalled)), ('52', '2'));
      gateway.sendInt(inst, note, 0, 64);
      click(at('.m', 500, 560)); // 3 -> store 3
      expect(value(at('.i', 190, 740)), '3');
      click(at('.m', 60, 560)); // 0
      expect(value(note), '45');
      gateway.sendInt(inst, bank, 0, 3);
      expect(value(note), '64');
      final slots = gateway.objectState(inst, bank)!['slots']! as List;
      expect([for (final s in slots) (s as Map)['slot']], [0, 1, 2, 3]);
    });

    test('kslider: a cable note lights its key, release, stored velocity', () {
      open('kslider');
      final keys = at('.kslider', 60, 250);
      final pitch = at('.i', 60, 350);
      final velocity = at('.i', 260, 350);
      click(at('.m', 60, 140)); // 60
      expect((value(pitch), value(velocity)), ('60', '100'));
      expect(gateway.guiValueAt(inst, keys, 60), '100', reason: 'key down');
      click(at('.b', 170, 140)); // pack 60 0
      expect((value(pitch), value(velocity)), ('60', '0'));
      expect(gateway.guiValueAt(inst, keys, 60), '0', reason: 'released');
      click(at('.m', 260, 140)); // 40 -> velocity inlet
      expect(value(velocity), '0', reason: 'the right inlet is silent');
      click(at('.m', 370, 140)); // 64
      expect((value(pitch), value(velocity)), ('64', '40'));
      click(at('.b', 480, 140)); // pack 67 110
      expect((value(pitch), value(velocity)), ('67', '110'));
      gateway.sendInt(inst, keys, 0, 72);
      expect(value(velocity), '110', reason: 'the list set the velocity');
      click(at('.b', 170, 140)); // pack 60 0
      click(at('.m', 60, 140)); // 60 now plays at 0: a release
      expect((value(pitch), value(velocity)), ('60', '0'));
      expect(graph.objects.map((o) => o.type), contains('~dac'));
    });

    test('nslider: sharps against flats, a chosen spelling, the range', () {
      open('nslider');
      final sharpPitch = at('.i', 60, 420);
      final sharpSign = at('.i', 140, 420);
      final flatPitch = at('.i', 240, 420);
      final flatSign = at('.i', 320, 420);
      click(at('.m', 60, 140)); // 61
      expect((value(sharpPitch), value(sharpSign)), ('61', '1'));
      expect((value(flatPitch), value(flatSign)), ('61', '-1'));
      click(at('.b', 170, 140)); // pack 61 -1
      expect((value(sharpPitch), value(sharpSign)), ('61', '-1'));
      click(at('.m', 390, 140)); // 1 -> set 1 1
      expect(value(sharpSign), '1', reason: 'respelled in place');
      click(at('.m', 280, 140)); // 90
      expect(value(sharpPitch), '90');
      expect(value(flatPitch), '72', reason: 'the staff covers 48 to 72');
      gateway.sendInt(inst, at('.nslider', 60, 250), 0, 60);
      click(at('.m', 390, 140));
      expect(value(sharpSign), '0', reason: 'a white key is natural');
      expect(graph.objects.map((o) => o.type), contains('~dac'));
    });
  });

  test('every audio basics type has a tutorial (#494)', () {
    for (final type in [
      '~sine',
      '~saw',
      '~noise',
      '~line',
      '~adc',
      '~dac',
      '~+',
      '~-',
      '~*',
      '~/',
      '~clip',
      '~lp',
      '~hp',
      '~bp',
      '~vcf',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  // The audio tutorials are played the way a tutorial plays in the app:
  // mounted on master. The offline session renders a block at a time, and the
  // master meter reports the peak of what reached it.
  group('audio basics tutorials (#494) sound the way their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    // Renders [blocks] blocks and returns the loudest master peak among them.
    double loudness([int blocks = 60]) {
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

    // The master peak of each of the next [blocks] blocks.
    List<double> peaks(int blocks) => [
      for (var i = 0; i < blocks; i++) loudness(1),
    ];

    void open(String slug) {
      inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      loudness(20); // the mount settles
    }

    tearDown(() {
      gateway.disposeInstance(inst);
      loudness(20); // and drains
    });

    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    void click(int id) => gateway.sendBang(inst, id, 0);
    void toggle(int id, bool on) => gateway.sendInt(inst, id, 0, on ? 1 : 0);
    double number(int id) => double.parse(gateway.guiValue(inst, id));

    test('sine: silent until switched on, a set frequency, beating', () {
      open('sine');
      expect(loudness(), lessThan(1e-4), reason: 'both toggles start off');
      final freq = at('.f', 60, 200);
      toggle(at('.t', 170, 260), true);
      final one = loudness();
      click(at('.m', 170, 140)); // 440.
      expect(number(freq), 440);
      gateway.sendFloat(inst, at('.slider', 300, 140), 0, 0.5);
      expect(number(freq), closeTo(495, 1e-3), reason: 'scale 0 1 110 880');
      click(at('.m', 60, 140)); // 220.
      toggle(at('.t', 410, 380), true);
      // 220 against 222 Hz: the sum swells and fades twice a second.
      final beat = peaks(400);
      expect(beat.reduce(math.max), greaterThan(1.8 * one));
      expect(beat.reduce(math.min), lessThan(0.3 * one));
    });

    test('saw: bipolar, brighter than the sine, the filter darkens it', () {
      open('saw');
      final cutoff = at('.f', 340, 360);
      expect(number(cutoff), closeTo(4050, 1e-3), reason: 'loadmess 0.5');
      toggle(at('.t', 60, 140), true);
      final open8000 = (() {
        gateway.sendFloat(inst, at('.slider', 340, 140), 0, 1);
        return loudness(200);
      })();
      expect(open8000, greaterThan(0.1));
      gateway.sendFloat(inst, cutoff, 0, 2);
      // Centred on 0, a saw filtered at 2 Hz leaves almost nothing; a saw
      // from 0 to 1 would leave half its level as an offset.
      loudness(400);
      expect(loudness(), lessThan(0.05 * open8000), reason: 'bipolar');
      toggle(at('.t', 60, 140), false);
      toggle(at('.t', 200, 140), true);
      gateway.sendFloat(inst, cutoff, 0, 8000);
      final sine8000 = loudness(200);
      gateway.sendFloat(inst, cutoff, 0, 1000);
      final sine1000 = loudness(200);
      expect(sine1000, greaterThan(0.9 * sine8000), reason: 'barely changes');
    });

    test('noise: a level slider, raw against lowpass and bandpass', () {
      open('noise');
      expect(number(at('.slider', 480, 190)), closeTo(0.5, 1e-6));
      expect(loudness(), lessThan(1e-4));
      final raw = at('.t', 60, 140);
      toggle(raw, true);
      final full = loudness(100);
      expect(full, greaterThan(0.01));
      gateway.sendFloat(inst, at('.slider', 480, 190), 0, 0);
      expect(loudness(), lessThan(1e-4), reason: 'level 0');
      gateway.sendFloat(inst, at('.slider', 480, 190), 0, 0.5);
      toggle(raw, false);
      toggle(at('.t', 200, 140), true);
      final low = loudness(100);
      toggle(at('.t', 200, 140), false);
      toggle(at('.t', 340, 140), true);
      final band = loudness(100);
      expect(low, inExclusiveRange(0, 0.5 * full), reason: 'lp 500');
      expect(band, inExclusiveRange(0, 0.5 * full), reason: 'bp 1000 5');
    });

    test('line: fades, a held ramp, ints and lists ignored, unpack', () {
      open('sig-line');
      final line = at('~line', 60, 220);
      expect(loudness(), lessThan(1e-4), reason: 'starts at 0');
      click(at('.m', 60, 140)); // 1. over 2000 ms
      final early = loudness(40);
      expect(early, greaterThan(0));
      final full = loudness(1200);
      expect(early, lessThan(0.3 * full), reason: 'a ramp, not a jump');
      click(at('.m', 170, 140)); // 0.
      loudness(300);
      click(at('.m', 280, 140)); // stop
      final held = loudness(5);
      expect(held, inExclusiveRange(0.1 * full, 0.95 * full));
      expect(loudness(300), closeTo(held, 0.02 * full), reason: 'held');
      gateway.sendInt(inst, line, 0, 1);
      gateway.sendList(inst, line, 0, '1 10');
      expect(loudness(300), closeTo(held, 0.02 * full), reason: 'ignored');
      click(at('.m', 410, 250)); // 10.
      click(at('.m', 170, 140)); // 0.
      loudness(40);
      expect(loudness(5), lessThan(0.01 * full), reason: 'a quick fade');
      click(at('.b', 410, 320)); // pack 0.25 500 -> unpack 0. 0.
      loudness(400);
      expect(loudness(), closeTo(0.25 * full, 0.02 * full));
    });

    test(
      'adc and dac: two dacs sum, unconnected noise and adc stay silent',
      () {
        open('adc-dac');
        expect(
          number(at('.slider', 180, 470)),
          closeTo(1, 1e-6),
          reason: 'loadmess',
        );
        expect(
          loudness(),
          lessThan(1e-4),
          reason: 'the noise reaches no dac, and adc is silent as a source',
        );
        toggle(at('.t', 60, 140), true);
        final one = loudness(400);
        expect(one, greaterThan(0.05));
        toggle(at('.t', 300, 140), true);
        expect(loudness(400), greaterThan(1.5 * one), reason: 'the dacs sum');
      },
    );

    test(
      'signal math: gain, clip limits by float and int, ring modulation',
      () {
        open('signal-math');
        expect(loudness(), lessThan(1e-4));
        final slider = at('.slider', 440, 140);
        gateway.sendFloat(inst, slider, 0, 1);
        // A sine at full scale, through the bare ~- and ~clip -1 1, divided by
        // 8.
        final unit = loudness(200);
        expect(unit, greaterThan(0.05));
        click(at('.m', 360, 500)); // 0.2
        expect(loudness(200), closeTo(0.2 * unit, 0.01 * unit));
        click(at('.m', 250, 500)); // 1, an int
        expect(loudness(200), closeTo(unit, 0.01 * unit));
        gateway.sendFloat(inst, slider, 0, 0);
        toggle(at('.t', 330, 200), true);
        click(at('.m', 280, 140)); // 300.
        final ring = loudness(400);
        expect(ring, closeTo(unit, 0.05 * unit), reason: 'sine times sine');
        gateway.sendFloat(inst, slider, 0, 1);
        expect(loudness(400), lessThan(1.01 * unit), reason: 'clipped at 1');
      },
    );

    test('lp and hp: the cutoff from the slider, the two halves', () {
      open('lp-hp');
      final cutoff = at('.f', 340, 360);
      final slider = at('.slider', 340, 140);
      expect(number(cutoff), closeTo(1000, 1e-3), reason: 'loadmess 0.2');
      final low = at('.t', 60, 140);
      final high = at('.t', 200, 140);
      toggle(low, true);
      final lp1000 = loudness(200);
      gateway.sendFloat(inst, slider, 0, 1);
      expect(number(cutoff), closeTo(5000, 1e-3));
      final lp5000 = loudness(200);
      expect(lp5000, greaterThan(lp1000), reason: 'more of the hiss');
      toggle(low, false);
      toggle(high, true);
      gateway.sendFloat(inst, slider, 0, 0.02); // 100 Hz
      final hp100 = loudness(200);
      toggle(high, false);
      toggle(low, true);
      final lp100 = loudness(200);
      expect(lp100, lessThan(0.5 * lp1000), reason: 'a rumble');
      expect(hp100, greaterThan(3 * lp100), reason: 'hp keeps the rest');
    });

    test('bp and vcf: a band over noise, a resonant sweep over a saw', () {
      open('bp-vcf');
      expect(loudness(), lessThan(1e-4));
      toggle(at('.t', 60, 140), true);
      final wide = loudness(200);
      expect(wide, greaterThan(0.01));
      click(at('.m', 280, 140)); // Q 10.
      final narrow = loudness(200);
      expect(narrow, inExclusiveRange(0, wide), reason: 'a narrower band');
      click(at('.m', 170, 140)); // Q 1.
      toggle(at('.t', 60, 140), false);
      toggle(at('.t', 60, 400), true);
      final soft = loudness(400);
      expect(soft, greaterThan(0.01), reason: 'the vcf sweeps');
      click(at('.m', 280, 400)); // 20.
      expect(loudness(400), inExclusiveRange(0, soft), reason: 'narrower');
      // Sharpness 0 passes the saw through unfiltered, at full level.
      gateway.sendFloat(inst, at('~vcf', 250, 580), 2, 0);
      expect(loudness(400), greaterThan(soft));
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
