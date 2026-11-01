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

    // The mean of the per-block master peaks over [blocks] blocks, after 20
    // blocks for a change to settle. A stable level for noise and filters,
    // where the single loudest block varies from run to run (#525).
    double level([int blocks = 400]) {
      loudness(20);
      final p = peaks(blocks);
      return p.reduce((a, b) => a + b) / p.length;
    }

    void open(String slug) {
      inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      // libyse sets a new sound up on a worker thread, in wall-clock time;
      // an offline render outruns it, so wait until the sound is in the mix
      // before measuring anything (#525).
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        loudness(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: '$slug mounted');
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
      final full = level();
      expect(full, greaterThan(0.01));
      gateway.sendFloat(inst, at('.slider', 480, 190), 0, 0);
      expect(loudness(), lessThan(1e-4), reason: 'level 0');
      gateway.sendFloat(inst, at('.slider', 480, 190), 0, 0.5);
      toggle(raw, false);
      toggle(at('.t', 200, 140), true);
      final low = level();
      toggle(at('.t', 200, 140), false);
      toggle(at('.t', 340, 140), true);
      final band = level();
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
      final lp1000 = level();
      gateway.sendFloat(inst, slider, 0, 1);
      expect(number(cutoff), closeTo(5000, 1e-3));
      final lp5000 = level();
      expect(lp5000, greaterThan(lp1000), reason: 'more of the hiss');
      toggle(low, false);
      toggle(high, true);
      gateway.sendFloat(inst, slider, 0, 0.02); // 100 Hz
      final hp100 = level();
      toggle(high, false);
      toggle(low, true);
      final lp100 = level();
      expect(lp100, lessThan(0.5 * lp1000), reason: 'a rumble');
      expect(hp100, greaterThan(3 * lp100), reason: 'hp keeps the rest');
    });

    test('bp and vcf: a band over noise, a resonant sweep over a saw', () {
      open('bp-vcf');
      expect(loudness(), lessThan(1e-4));
      toggle(at('.t', 60, 140), true);
      final wide = level();
      expect(wide, greaterThan(0.01));
      click(at('.m', 280, 140)); // Q 10.
      final narrow = level();
      expect(narrow, inExclusiveRange(0, wide), reason: 'a narrower band');
      click(at('.m', 170, 140)); // Q 1.
      toggle(at('.t', 60, 140), false);
      toggle(at('.t', 60, 400), true);
      // Each level spans one 4 s cycle of the 0.25 Hz sweep, so where the
      // sweep stands does not matter.
      final sweep = (4 * 48000 / System.blockSize).ceil();
      final soft = level(sweep);
      expect(soft, greaterThan(0.01), reason: 'the vcf sweeps');
      click(at('.m', 280, 400)); // 20.
      expect(level(sweep), inExclusiveRange(0, soft), reason: 'narrower');
      // Sharpness 0 passes the saw through unfiltered, at full level.
      gateway.sendFloat(inst, at('~vcf', 250, 580), 2, 0);
      expect(level(sweep), greaterThan(soft));
    });
  });

  test('every control math type has a tutorial (#495)', () {
    for (final type in [
      '.+', '.-', '.*', './', '.%', '.!-', '.!/', //
      '.==', '.!=', '.<', '.<=', '.>', '.>=', //
      '.&&', '.||', '.&', '.|', '.<<', '.>>', //
      '.abs', '.round', '.clip', '.scale', '.zmap', //
      '.sin', '.cos', '.tan', '.asin', '.acos', '.atan', '.atan2', //
      '.sinh', '.cosh', '.tanh', '.asinh', '.acosh', '.atanh', //
      '.pow', '.sqrt', '.expr', '.vexpr', //
      '.mtof', '.ftom', '.atodb', '.dbtoa',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  group('control math tutorials (#495) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    double loudness([int blocks = 200]) {
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

    void open(String slug, {bool mount = false}) {
      inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
      if (!mount) return;
      gateway.mountAsSource(inst);
      // Wait for the sound to join the mix before measuring (#525).
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        loudness(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: '$slug mounted');
      loudness(20);
    }

    tearDown(() {
      gateway.disposeInstance(inst);
      loudness(20);
    });

    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    // A message box by its text: each tutorial's are unique.
    int msg(String text) => graph.objects
        .singleWhere((o) => o.type == '.m' && o.args == text)
        .handleId;
    void click(int id) => gateway.sendBang(inst, id, 0);
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));
    List<double> numbers(int id) => [
      for (final t in value(id).split(' '))
        if (t.isNotEmpty) double.parse(t),
    ];
    List<double> row(String type, double y, List<double> xs) => [
      for (final x in xs) number(at(type, x, y)),
    ];
    const six = [60.0, 150.0, 240.0, 330.0, 420.0, 510.0];

    test('arithmetic: hot and cold, trigger b f, swapped, by zero', () {
      open('arithmetic');
      final sum = at('.f', 60, 270);
      click(msg('3'));
      expect(number(sum), 13, reason: 'the argument is the right operand');
      click(msg('100'));
      expect(number(sum), 13, reason: 'cold');
      gateway.sendBang(inst, at('.+', 60, 220), 0);
      expect(number(sum), 13, reason: 'a bang on the left sends nothing');
      click(msg('7'));
      expect(number(sum), 107);
      click(msg('2'));
      click(msg('5'));
      expect(number(at('.f', 60, 550)), 7);
      click(msg('8'));
      expect(number(at('.f', 60, 550)), 10, reason: 'both inlets hot');
      click(msg('10'));
      final r = row('.f', 790, six);
      expect(r.sublist(0, 5), [6, 40, 2.5, 2, -6]);
      expect(r[5], closeTo(0.4, 1e-6));
      click(msg('-7'));
      expect(number(at('.f', 330, 790)), -3, reason: 'the sign of the left');
      expect(value(at('.f', 330, 790)), isNot(contains('.5')));
      click(msg('0'));
      click(msg('10'));
      expect(row('.f', 790, six), [10, 0, 0, 0, -10, 0]);
      gateway.sendInt(inst, at('.!/', 510, 740), 1, 4);
      gateway.sendInt(inst, at('.!/', 510, 740), 0, 0);
      expect(number(at('.f', 510, 790)), 0, reason: '!/ by a left 0');
    });

    test('comparison: 0 or 1, a threshold crossing once, a gate', () {
      open('comparison');
      click(msg('3'));
      expect(row('.i', 330, six), [0, 1, 1, 1, 0, 0]);
      click(msg('5'));
      expect(row('.i', 330, six), [1, 0, 0, 1, 0, 1]);
      click(msg('5.5'));
      expect(row('.i', 330, six), [0, 1, 0, 0, 1, 1], reason: 'not truncated');
      click(msg('8'));
      expect(row('.i', 330, six), [0, 1, 0, 0, 1, 1]);
      final slider = at('.slider', 60, 410);
      final passed = at('.i', 330, 750);
      click(msg('42'));
      expect(value(passed), '0', reason: 'closed');
      // >= answers on every move; change lets each crossing through once.
      // Count what reaches the two buttons.
      final sel = at('.sel', 60, 750);
      int counter(int outlet) {
        final c = gateway.createObject(inst, '.counter');
        gateway.connect(
          inst,
          fromHandleId: sel,
          outlet: outlet,
          toHandleId: c,
          inlet: 0,
        );
        final shown = gateway.createObject(inst, '.i');
        gateway.connect(
          inst,
          fromHandleId: c,
          outlet: 0,
          toHandleId: shown,
          inlet: 0,
        );
        return shown;
      }

      final rises = counter(0);
      final falls = counter(1);
      final answers = <String>[];
      for (final v in [0.2, 0.6, 0.7, 0.9, 0.4, 0.3, 0.8]) {
        gateway.sendFloat(inst, slider, 0, v);
        answers.add(value(at('.i', 60, 630)));
      }
      expect(answers, ['0', '1', '1', '1', '0', '0', '1']);
      expect((value(rises), value(falls)), ('2', '1'), reason: 'crossings');
      click(msg('42'));
      expect(value(passed), '42', reason: 'opened by the comparison');
    });

    test('logic: toggles, bits, shifts, packing and unpacking', () {
      open('logic');
      final and = at('.i', 60, 320);
      final or = at('.i', 170, 320);
      gateway.sendInt(inst, at('.t', 60, 160), 0, 1);
      expect((value(and), value(or)), ('0', '1'));
      gateway.sendInt(inst, at('.t', 200, 160), 0, 1);
      expect((value(and), value(or)), ('1', '1'), reason: 'both answer');
      gateway.sendInt(inst, at('.i', 60, 210), 0, 7);
      expect(value(and), '1', reason: 'any non-zero number is true');
      gateway.sendInt(inst, at('.t', 200, 160), 0, 0);
      expect(value(and), '0');
      gateway.sendBang(inst, at('.&&', 60, 270), 0);
      expect(value(and), '0', reason: 'a bang works nothing out');
      click(msg('12'));
      expect(
        (value(at('.i', 60, 500)), value(at('.i', 170, 500))),
        ('8', '14'),
      );
      click(msg('6'));
      expect(
        (value(at('.i', 300, 500)), value(at('.i', 410, 500))),
        ('12', '3'),
      );
      click(msg('-8'));
      expect(
        (value(at('.i', 300, 500)), value(at('.i', 410, 500))),
        ('-16', '-4'),
      );
      click(msg('2'));
      click(msg('5'));
      expect(value(at('.i', 60, 790)), '37');
      expect((value(at('.i', 60, 900)), value(at('.i', 200, 900))), ('2', '5'));
      click(msg('9'));
      click(msg('15'));
      expect(value(at('.i', 60, 790)), '159');
      expect(
        (value(at('.i', 60, 900)), value(at('.i', 200, 900))),
        ('9', '15'),
      );
    });

    test('range: abs, a grid, limits, scale past the range, zmap, a curve', () {
      open('range');
      const xs = [60.0, 170.0, 300.0];
      click(msg('-3.5'));
      expect(row('.f', 330, xs), [3.5, -3.5, 0]);
      click(msg('0.37'));
      expect(row('.f', 330, xs)[1], 0.25);
      click(msg('150'));
      expect(row('.f', 330, xs), [150, 150, 100]);
      click(msg('0.5'));
      click(msg('0.37'));
      expect(number(at('.f', 170, 330)), 0.5, reason: 'a grid of halves');
      gateway.sendFloat(inst, at('.clip', 300, 280), 2, 0.2);
      click(msg('0.37'));
      expect(number(at('.f', 300, 330)), closeTo(0.2, 1e-6), reason: 'high');
      click(msg('64'));
      expect(number(at('.f', 60, 570)), closeTo(0.5, 0.01));
      click(msg('160'));
      expect(number(at('.f', 60, 570)), closeTo(1.26, 0.005));
      expect(number(at('.f', 300, 570)), 1);
      final slider = at('.slider', 60, 650);
      gateway.sendFloat(inst, slider, 0, 0.5);
      expect(number(at('.f', 140, 700)), closeTo(1650, 1e-3));
      expect(number(at('.f', 140, 810)), closeTo(875, 1e-3));
    });

    test('math functions: twelve answers, finite, the LFO, pow, atan2', () {
      open('math-functions', mount: true);
      click(msg('0.5'));
      final top = row('.f', 330, six);
      final bottom = row('.f', 440, six);
      final want = [
        math.sin(0.5), math.cos(0.5), math.tan(0.5), //
        math.asin(0.5), math.acos(0.5), math.atan(0.5),
      ];
      for (var i = 0; i < 6; i++) {
        expect(top[i], closeTo(want[i], 1e-5), reason: 'row 1 #$i');
      }
      expect(bottom[2], closeTo(0.462117, 1e-5), reason: 'tanh');
      expect(bottom[4], 0, reason: 'acosh below 1');
      click(msg('2.'));
      expect([row('.f', 330, six)[3], row('.f', 330, six)[4]], [0, 0]);
      expect(row('.f', 440, six)[5], 0, reason: 'atanh outside -1 to 1');
      expect(row('.f', 440, six)[4], closeTo(1.316958, 1e-5), reason: 'acosh');
      click(msg('-3'));
      expect(row('.f', 440, six)[4], 0);
      expect(row('.f', 440, six)[2], closeTo(-0.995055, 1e-5));
      // The LFO, stepped by hand: 10 steps is a quarter circle, the top.
      expect(loudness(), lessThan(1e-4), reason: 'silent until switched on');
      final counter = at('.counter', 60, 620);
      for (var i = 0; i < 10; i++) {
        click(counter);
      }
      expect(number(at('.f', 200, 780)), closeTo(1, 1e-4), reason: 'sin');
      expect(number(at('.f', 60, 890)), closeTo(600, 0.01), reason: 'Hz');
      for (var i = 0; i < 30; i++) {
        click(counter);
      }
      expect(number(at('.f', 60, 890)), closeTo(450, 0.01), reason: 'wrapped');
      gateway.sendInt(inst, at('.t', 60, 520), 0, 1);
      expect(loudness(), greaterThan(0.05), reason: 'the sine on master');
      gateway.sendInt(inst, at('.t', 60, 520), 0, 0);
      gateway.sendFloat(inst, at('.slider', 330, 520), 0, 0.5);
      expect(number(at('.f', 420, 570)), 0.125);
      expect(number(at('.f', 520, 570)), closeTo(0.707107, 1e-5));
      click(msg('1.'));
      expect(number(at('.f', 330, 940)), closeTo(math.pi / 2, 1e-5));
      expect(number(at('.f', 330, 1050)), closeTo(90, 1e-3));
      click(msg('-1.'));
      expect(number(at('.f', 330, 1050)), closeTo(135, 1e-3));
    });

    test('expr: two inlets, int and float, a list, vexpr item by item', () {
      open('expr');
      final out = at('.f', 60, 270);
      click(msg('1'));
      expect(number(out), 0, reason: 'only stored');
      click(msg('3'));
      expect(number(out), 7);
      gateway.sendInt(inst, at('.expr', 60, 220), 1, 4);
      gateway.sendBang(inst, at('.expr', 60, 220), 0);
      expect(number(out), 10, reason: 'a bang works it out again');
      click(msg('7'));
      expect((number(at('.f', 60, 450)), number(at('.f', 250, 450))), (3, 3.5));
      click(at('.b', 60, 520));
      expect(number(at('.f', 60, 680)), 5);
      final list = at('.l', 60, 920);
      click(at('.b', 300, 760));
      click(at('.b', 60, 760));
      expect(numbers(list), [10, 40, 90]);
      click(msg('2'));
      click(at('.b', 60, 760));
      expect(numbers(list), [2, 4, 6]);
      // What the title note promises about expressions the engine can't read.
      final probe = gateway.createObject(
        inst,
        '.expr',
        args: r'$f1 > 2 ? 10 : 20',
      );
      final seen = gateway.createObject(inst, '.f', args: '5');
      gateway.connect(
        inst,
        fromHandleId: probe,
        outlet: 0,
        toHandleId: seen,
        inlet: 0,
      );
      gateway.sendInt(inst, probe, 0, 4);
      expect(number(seen), 0, reason: '?: sends 0 on libYSE 3.1.0');
    });

    test('conversions: keys to Hz, a decibel fader, back again', () {
      open('conversions', mount: true);
      expect(loudness(), lessThan(1e-4), reason: 'the fader starts down');
      final keys = at('.kslider', 60, 160);
      final hz = at('.f', 60, 310);
      gateway.sendInt(inst, keys, 0, 69);
      expect(number(hz), closeTo(440, 1e-3));
      gateway.sendInt(inst, keys, 0, 81);
      expect(number(hz), closeTo(880, 1e-3));
      final fader = at('.slider', 400, 160);
      gateway.sendFloat(inst, fader, 0, 1);
      expect(number(at('.f', 400, 380)), closeTo(100, 1e-4));
      expect(number(at('.f', 400, 480)), closeTo(1, 1e-4));
      final full = loudness();
      expect(full, greaterThan(0.1));
      gateway.sendFloat(inst, fader, 0, 0.5);
      expect(number(at('.f', 400, 480)), closeTo(0.1, 1e-4), reason: '80 dB');
      expect(loudness(), closeTo(0.1 * full, 0.02 * full));
      gateway.sendFloat(inst, fader, 0, 0);
      expect(number(at('.f', 400, 480)), closeTo(0.01, 1e-5), reason: '-40');
      click(msg('440.'));
      expect(number(at('.f', 60, 750)), closeTo(69, 1e-4));
      click(msg('452.89'));
      expect(number(at('.f', 60, 750)), closeTo(69.5, 1e-3));
      click(msg('0.'));
      expect(number(at('.f', 60, 750)), -1500);
      final db = at('.f', 60, 940);
      final dbfs = at('.f', 60, 1050);
      click(msg('1'));
      expect((number(db), number(dbfs)), (100, 0));
      click(msg('0.5'));
      expect(number(dbfs), closeTo(-6.02, 0.01));
      click(msg('0.01'));
      expect(number(dbfs), closeTo(-40, 1e-3));
      gateway.sendInt(inst, at('.atodb', 60, 890), 0, 0);
      expect(number(db), 0, reason: 'finite: 0 dB, not minus infinity');
    });
  });

  test('every stateful math type has a tutorial (#496)', () {
    for (final type in [
      '.counter', '.accum', '.change', '.togedge', //
      '.past', '.peak', '.trough', '.maximum', '.minimum', //
      '.mean', '.histo', '.anal', '.slide', '.linedrive', //
      '.div', '.swap', '.pong', '.cartopol', '.poltocar',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  group('stateful math tutorials (#496) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    double loudness([int blocks = 200]) {
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

    void open(String slug, {bool mount = false}) {
      inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
      if (!mount) return;
      gateway.mountAsSource(inst);
      // Wait for the sound to join the mix before measuring (#525).
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        loudness(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: '$slug mounted');
      loudness(20);
    }

    tearDown(() {
      gateway.disposeInstance(inst);
      loudness(20);
    });

    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    // A message box by its text: each tutorial's are unique.
    int msg(String text) => graph.objects
        .singleWhere((o) => o.type == '.m' && o.args == text)
        .handleId;
    void click(int id) => gateway.sendBang(inst, id, 0);
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));
    List<double> numbers(int id) => [
      for (final t in value(id).split(' '))
        if (t.isNotEmpty) double.parse(t),
    ];
    // A counter wired to [outlet] of [from], counting what leaves it.
    int tally(int from, int outlet) {
      final c = gateway.createObject(inst, '.counter');
      final t = gateway.createObject(inst, '.trigger', args: 'b');
      gateway
        ..connect(
          inst,
          fromHandleId: from,
          outlet: outlet,
          toHandleId: t,
          inlet: 0,
        )
        ..connect(inst, fromHandleId: t, outlet: 0, toHandleId: c, inlet: 0);
      return c;
    }

    test('counter: bangs, a set count, the step, reset, wrap, fold, steps', () {
      open('counter', mount: true);
      final count = at('.i', 60, 270);
      final button = at('.b', 60, 160);
      final seen = <String>[];
      for (var i = 0; i < 3; i++) {
        click(button);
        seen.add(value(count));
      }
      expect(seen, ['1', '2', '3'], reason: 'start 0 plus the step');
      click(msg('20'));
      expect(value(count), '20');
      click(button);
      expect(value(count), '21');
      click(msg('3'));
      click(button);
      expect(value(count), '24', reason: 'step 3');
      click(msg('-1'));
      click(button);
      expect(value(count), '23', reason: 'counting down');
      click(msg('reset'));
      expect(value(count), '23', reason: 'reset sends nothing');
      click(button);
      expect(value(count), '-1', reason: 'the start value plus the step');
      final wrapped = <String>[];
      final folded = <String>[];
      for (var i = 0; i < 7; i++) {
        click(at('.b', 60, 350));
        wrapped.add(value(at('.i', 60, 510)));
        folded.add(value(at('.i', 170, 510)));
      }
      expect(wrapped, ['1', '2', '3', '0', '1', '2', '3']);
      expect(folded, ['1', '2', '3', '2', '1', '0', '1']);
      // The sequencer, stepped by hand: metro runs in real time.
      expect(loudness(), lessThan(1e-4), reason: 'silent until switched on');
      final clock = at('.counter', 60, 690);
      final steps = <String>[];
      final hz = <double>[];
      for (var i = 0; i < 8; i++) {
        click(clock);
        steps.add(value(at('.i', 200, 740)));
        hz.add(number(at('.f', 170, 920)));
      }
      expect(steps, ['1', '2', '3', '0', '1', '2', '3', '0']);
      final want = [
        64,
        67,
        72,
        60,
      ].map((n) => 440 * math.pow(2, (n - 69) / 12));
      for (var i = 0; i < 8; i++) {
        expect(hz[i], closeTo(want.elementAt(i % 4), 0.01), reason: 'step $i');
      }
      expect(value(at('.i', 500, 910)), '2', reason: 'two bars: the carry');
      gateway.sendInt(inst, at('.t', 60, 590), 0, 1);
      expect(loudness(), greaterThan(0.05), reason: 'the sequence on master');
      gateway.sendInt(inst, at('.t', 60, 590), 0, 0);
    });

    test('accum: add, multiply, replace, reset, a running sum, a fade', () {
      open('accum');
      final out = at('.f', 60, 330);
      final button = at('.b', 60, 220);
      click(button);
      expect(number(out), 10, reason: 'the argument');
      click(msg('5'));
      expect(number(out), 10, reason: 'adds without sending');
      click(button);
      expect(number(out), 15);
      click(msg('1'));
      click(msg('1'));
      click(button);
      expect(number(out), 17);
      click(msg('2'));
      click(button);
      expect(number(out), 34, reason: 'multiplied');
      click(msg('0.5'));
      click(button);
      expect(number(out), 17);
      click(msg('100'));
      expect(number(out), 100, reason: 'replaced and sent');
      click(msg('reset'));
      expect(number(out), 100, reason: 'reset sends nothing');
      click(button);
      expect(number(out), 10);
      final sum = at('.f', 60, 580);
      final sums = <double>[];
      for (final m in ['3', '4', '10']) {
        click(msg(m));
        sums.add(number(sum));
      }
      expect(sums, [3, 7, 17]);
      click(msg('0'));
      click(msg('4'));
      expect(number(sum), 4, reason: 'started again');
      final fade = at('.f', 60, 820);
      final fades = <double>[];
      for (var i = 0; i < 3; i++) {
        click(at('.b', 60, 660));
        fades.add(number(fade));
      }
      expect(fades[0], closeTo(0.8, 1e-6));
      expect(fades[1], closeTo(0.64, 1e-6));
      expect(fades[2], closeTo(0.512, 1e-6));
      click(msg('1.'));
      click(at('.b', 60, 660));
      expect(number(fade), closeTo(0.8, 1e-6), reason: 'from 1 again');
    });

    test('change togedge: repeats filtered, leaving and returning to 0', () {
      open('change-togedge');
      final slider = at('.slider', 60, 160);
      for (final v in [0.0, 0.05, 0.1, 0.2, 0.3, 0.35, 0.4, 0.6, 0.7]) {
        gateway.sendFloat(inst, slider, 0, v);
      }
      expect(value(at('.i', 300, 380)), '9', reason: 'every move arrives');
      // 0 0 0 1 1 1 2 2 3, against a starting 0: 1, 2 and 3 pass.
      expect(value(at('.i', 420, 380)), '3', reason: 'only the changes pass');
      expect(number(at('.f', 140, 330)), 3);
      final change = at('.change', 60, 540);
      final rises = at('.i', 150, 700);
      final falls = at('.i', 250, 700);
      final passed = tally(change, 0);
      click(msg('1'));
      expect((value(passed), value(rises), value(falls)), ('1', '1', '0'));
      click(msg('2'));
      expect((value(passed), value(rises), value(falls)), ('2', '1', '0'));
      click(msg('0'));
      expect((value(passed), value(rises), value(falls)), ('3', '1', '1'));
      click(msg('0'));
      expect((value(passed), value(rises), value(falls)), ('3', '1', '1'));
      final on = at('.i', 360, 650);
      final off = at('.i', 470, 650);
      expect((value(on), value(off)), ('1', '1'), reason: '1 2 is one on');
      click(msg('0.5'));
      expect((value(on), value(off)), ('2', '1'), reason: '0.5 counts as on');
      click(at('.b', 500, 480));
      expect((value(on), value(off)), ('2', '2'), reason: 'a bang flips off');
      click(at('.b', 500, 480));
      expect((value(on), value(off)), ('3', '2'), reason: 'and on again');
    });

    test('extremes: a threshold once, records, larger and smaller', () {
      open('extremes');
      final slider = at('.slider', 60, 160);
      final crossings = at('.i', 140, 330);
      for (final v in [0.2, 0.5, 0.6, 0.8, 0.55, 0.3, 0.7]) {
        gateway.sendFloat(inst, slider, 0, v);
      }
      expect(value(crossings), '2', reason: 'at 50, and again after 30');
      click(msg('clear'));
      gateway.sendFloat(inst, slider, 0, 0.75);
      expect(value(crossings), '3', reason: 'clear re-arms above 50');
      final peaks = <String>[];
      final troughs = <String>[];
      final newPeak = <String>[];
      final newTrough = <String>[];
      for (final m in ['5', '3', '9', '1']) {
        click(msg(m));
        peaks.add(value(at('.f', 60, 540)));
        newPeak.add(value(at('.i', 150, 540)));
        troughs.add(value(at('.f', 300, 540)));
        newTrough.add(value(at('.i', 390, 540)));
      }
      expect(peaks.map(double.parse), [5, 5, 9, 9]);
      expect(newPeak, ['1', '0', '1', '0']);
      expect(troughs.map(double.parse), [5, 3, 3, 1]);
      expect(newTrough, ['1', '1', '0', '1']);
      click(msg('reset'));
      gateway.sendBang(inst, at('.peak', 60, 480), 0);
      gateway.sendBang(inst, at('.trough', 300, 480), 0);
      expect(
        (number(at('.f', 60, 540)), number(at('.f', 300, 540))),
        (0, 128),
        reason: 'reset goes back to 0 and 128',
      );
      final mx = at('.f', 60, 800);
      final mn = at('.f', 200, 800);
      click(msg('4'));
      expect((number(mx), number(mn)), (6, 4));
      click(msg('12'));
      expect((number(mx), number(mn)), (12, 6));
      click(msg('20'));
      click(msg('12'));
      expect((number(mx), number(mn)), (20, 12));
      click(at('.b', 390, 630));
      expect((number(mx), number(mn)), (17, 2), reason: 'a list');
      click(msg('4'));
      expect((number(mx), number(mn)), (8, 4), reason: 'second largest');
    });

    test('statistics: an average, a histogram, pairs into prob', () {
      open('statistics');
      final mean = at('.f', 60, 270);
      final count = at('.i', 150, 270);
      final means = <double>[];
      for (final m in ['2', '4', '9']) {
        click(msg(m));
        means.add(number(mean));
      }
      expect(means, [2, 3, 5]);
      expect(value(count), '3');
      click(msg('reset'));
      click(msg('4'));
      expect((number(mean), value(count)), (4, '1'), reason: 'reset');
      click(at('.b', 500, 160));
      expect((number(mean), value(count)), (4, '4'), reason: 'a list');
      click(msg('9'));
      expect(number(mean), 5, reason: '(1+2+3+10+9)/5');
      final histo = at('.l', 60, 470);
      final rejects = at('.i', 200, 520);
      final counts = <String>[];
      for (final m in ['1', '3', '3', '6']) {
        click(msg(m));
        counts.add(value(histo));
      }
      expect(counts, ['1 1', '3 1', '3 2', '6 1']);
      click(msg('12'));
      expect(value(rejects), '1', reason: 'outside 0 to 7');
      expect(value(histo), '6 1');
      click(msg('clear'));
      click(msg('3'));
      expect(value(histo), '3 1', reason: 'cleared');
      final pairs = <String>[];
      for (final m in ['60', '62', '60', '62', '64']) {
        click(msg(m));
        pairs.add(value(at('.l', 60, 670)));
      }
      expect(pairs, ['', '60 62 1', '62 60 1', '60 62 2', '62 64 1']);
      final prob = at('.prob', 300, 680);
      final stuck = tally(prob, 1);
      final jumps = tally(prob, 0);
      // Follow the chain bang by bang: what may come next from where it is.
      // From 64 nothing ever followed, so that bang sends nothing, bangs the
      // stuck outlet, and the chain is back at 60.
      var state = '60';
      final seen = <String>{};
      var dead = 0;
      for (var i = 0; i < 60; i++) {
        final before = value(jumps);
        click(at('.b', 390, 620));
        final now = value(at('.i', 300, 730));
        if (state == '64') {
          expect(value(jumps), before, reason: 'a dead end sends nothing');
          dead++;
          expect(value(stuck), '$dead');
          state = '60';
          continue;
        }
        final allowed = state == '60' ? {'62'} : {'60', '64'};
        expect(allowed, contains(now), reason: 'from $state');
        seen.add(now);
        state = now;
      }
      expect(seen, {'60', '62', '64'});
      expect(dead, greaterThan(0));
    });

    test('slide linedrive: slides, jitter, the curve, line to a sine', () {
      open('slide-linedrive', mount: true);
      final out = at('.f', 60, 270);
      click(msg('100'));
      expect(number(out), closeTo(33.333, 1e-3));
      click(msg('100'));
      expect(number(out), closeTo(55.556, 1e-3));
      click(at('.b', 280, 160));
      expect(number(out), closeTo(70.370, 1e-3), reason: 'the button');
      click(msg('0'));
      expect(number(out), closeTo(70.370 * 11 / 12, 1e-3), reason: 'a 12th');
      // Jitter: random stepped by hand, metro runs in real time.
      final random = at('.random', 60, 450);
      final raw = <double>[];
      final smooth = <double>[];
      for (var i = 0; i < 200; i++) {
        click(random);
        raw.add(number(at('.f', 200, 450)));
        smooth.add(number(at('.f', 60, 560)));
      }
      double spread(List<double> xs) {
        final tail = xs.sublist(100);
        return tail.reduce(math.max) - tail.reduce(math.min);
      }

      for (final r in raw) {
        expect(r, inInclusiveRange(0, 99));
      }
      expect(spread(smooth), lessThan(0.6 * spread(raw)), reason: 'smoothed');
      final slider = at('.slider', 60, 650);
      gateway.sendFloat(inst, slider, 0, 1);
      expect(number(at('.f', 140, 760)), closeTo(2000, 1e-2));
      expect(numbers(at('.l', 300, 820)), [closeTo(2000, 1e-2), 300]);
      gateway.sendFloat(inst, slider, 0, 0.5);
      expect(
        number(at('.f', 140, 760)),
        closeTo(2000 * math.pow(1.06, -63.5), 0.01),
      );
      expect(number(at('.f', 140, 760)), closeTo(49, 0.5), reason: 'about 49');
      gateway.sendFloat(inst, slider, 0, (127 - 12) / 127);
      expect(
        number(at('.f', 140, 760)),
        closeTo(2000 / math.pow(1.06, 12), 0.01),
      );
      expect(number(at('.f', 140, 760)), closeTo(1000, 10), reason: '12 halve');
      // line glides on the audio clock: render, and watch it arrive.
      final glide = at('.f', 140, 930);
      loudness(400);
      expect(number(glide), closeTo(2000 / math.pow(1.06, 12), 0.01));
      gateway.sendFloat(inst, slider, 0, 1);
      final path = <double>[];
      for (var i = 0; i < 40; i++) {
        loudness(10);
        path.add(number(glide));
      }
      expect(path.last, closeTo(2000, 1e-3), reason: 'arrives in 300 ms');
      expect(path.where((v) => v > 1000 && v < 1990), isNotEmpty);
      expect(loudness(), lessThan(1e-4), reason: 'silent until switched on');
      gateway.sendInt(inst, at('.t', 300, 880), 0, 1);
      expect(loudness(), greaterThan(0.1), reason: 'the sine on master');
      gateway.sendInt(inst, at('.t', 300, 880), 0, 0);
    });

    test('div swap pong: whole parts, a crossed pair, fold wrap clip', () {
      open('div-swap-pong');
      final q = at('.i', 60, 270);
      final r = at('.i', 170, 270);
      click(msg('17'));
      expect((value(q), value(r)), ('3', '2'));
      click(msg('-17'));
      expect((value(q), value(r)), ('-3', '-2'));
      click(msg('0'));
      click(msg('17'));
      expect(value(q), '0', reason: 'divided by 0');
      click(msg('7'));
      expect(value(at('.l', 60, 570)), isEmpty, reason: 'stored only');
      click(msg('3'));
      expect((number(at('.f', 60, 460)), number(at('.f', 170, 460))), (7, 3));
      expect(numbers(at('.l', 60, 570)), [7, 3]);
      List<double> pongs() => [
        for (final x in [60.0, 200.0, 340.0]) number(at('.f', x, 810)),
      ];
      click(msg('13'));
      expect(pongs(), [7, 3, 10]);
      click(msg('-3'));
      expect(pongs(), [3, 7, 0]);
      click(msg('25'));
      expect(pongs(), [5, 5, 10]);
    });

    test('cartopol poltocar: the pad in polar form, back, and a circle', () {
      open('cartopol-poltocar');
      final pad = at('.xyslider', 60, 160);
      final amp = at('.f', 60, 430);
      final angle = at('.f', 170, 430);
      final degrees = at('.f', 170, 540);
      gateway.sendList(inst, pad, 0, '0.6 0.8');
      expect(number(amp), closeTo(1, 1e-5));
      expect(number(angle), closeTo(math.atan2(0.8, 0.6), 1e-5));
      expect(number(at('.f', 60, 650)), closeTo(0.6, 1e-5), reason: 'x back');
      expect(number(at('.f', 170, 650)), closeTo(0.8, 1e-5), reason: 'y back');
      gateway.sendList(inst, pad, 0, '-1 0');
      expect(number(angle), closeTo(math.pi, 1e-5), reason: 'straight left');
      expect(number(degrees), closeTo(180, 1e-3));
      gateway.sendList(inst, pad, 0, '0 -0.5');
      expect(number(degrees), closeTo(-90, 1e-3), reason: 'below: negative');
      expect(number(amp), closeTo(0.5, 1e-5));
      final clock = at('.counter', 330, 260);
      final angles = <double>[];
      for (var i = 0; i < 40; i++) {
        click(clock);
        expect(number(amp), closeTo(0.8, 1e-4), reason: 'on the circle');
        angles.add(number(angle));
      }
      final xy = numbers(pad);
      expect(xy[0], closeTo(0.8, 1e-4), reason: 'step 40: angle 0');
      expect(xy[1], closeTo(0, 1e-4));
      expect(angles[9], closeTo(math.pi / 2, 1e-4), reason: 'step 10: up');
      expect(angles.reduce(math.min), lessThan(-3));
      expect(angles.reduce(math.max), greaterThan(2.9));
    });
  });

  test('every clock, delay and ramp type has a tutorial (#497)', () {
    for (final type in [
      '.metro', '.delay', '.pipe', '.line', '.bline', '.speedlim', //
      '.qlim', '.timer', '.clocker', '.thresh', '.quickthresh',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.line'), index.tutorialFor('.bline'));
    expect(index.tutorialFor('.speedlim'), index.tutorialFor('.qlim'));
    expect(index.tutorialFor('.timer'), index.tutorialFor('.clocker'));
    expect(index.tutorialFor('.thresh'), index.tutorialFor('.quickthresh'));
  });

  group('clock, delay and ramp tutorials (#497) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    // One block is 128 frames at 48 kHz: about 2.67 ms of audio.
    const blockMs = 128 / 48;
    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // [ms] milliseconds of audio time: delay, pipe, line, speedlim, qlim and
    // thresh count it, and run only in a mounted patcher (#528).
    void audio(double ms) => render((ms / blockMs).ceil());

    // Every tutorial is mounted while open (#528); so is this copy.
    void open(String slug) {
      inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      // Wait for the sound to join the mix before counting audio (#525).
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: '$slug mounted');
      render(20);
    }

    tearDown(() {
      gateway.disposeInstance(inst);
      render(20);
    });

    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    // A message box by its text: each tutorial's are unique.
    int msg(String text) => graph.objects
        .singleWhere((o) => o.type == '.m' && o.args == text)
        .handleId;
    void click(int id) => gateway.sendBang(inst, id, 0);
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));
    int whole(int id) => int.parse(value(id));
    // metro, timer and clocker run on wall-clock time.
    void wait(int ms) => sleep(Duration(milliseconds: ms));

    test('metro: on and off, the interval while running, bang and stop', () {
      open('metro');
      final toggle = at('.t', 60, 160);
      final ticks = at('.i', 60, 400);
      expect(value(at('.i', 360, 230)), '500', reason: 'loadmess on load');
      gateway.sendInt(inst, toggle, 0, 1);
      expect(value(ticks), '1', reason: 'a tick the moment it starts');
      wait(1120);
      expect(whole(ticks), 3, reason: 'then one every 500 ms');
      click(msg('125'));
      final before = whole(ticks);
      wait(530);
      expect(
        whole(ticks) - before,
        inInclusiveRange(3, 5),
        reason: 'four times as fast, without stopping',
      );
      gateway.sendInt(inst, toggle, 0, 0);
      final stopped = whole(ticks);
      wait(300);
      expect(whole(ticks), stopped, reason: '0 stops it');
      click(msg('bang'));
      expect(whole(ticks), stopped + 1, reason: 'bang starts it, at once');
      wait(80);
      click(msg('bang'));
      expect(whole(ticks), stopped + 2, reason: 'and restarts it from now');
      click(msg('stop'));
      final last = whole(ticks);
      wait(300);
      expect(whole(ticks), last, reason: 'stop stops it');
      click(msg('1000'));
      expect(value(at('.i', 360, 230)), '1000');
    });

    test('delay: later, restarted, cancelled, either inlet, chained', () {
      open('delay');
      final button = at('.b', 60, 160);
      final arrived = at('.i', 60, 340);
      final clicks = at('.i', 220, 340);
      click(button);
      expect((value(clicks), value(arrived)), ('1', '0'));
      audio(900);
      expect(value(arrived), '0', reason: 'not yet');
      audio(150);
      expect(value(arrived), '1', reason: 'a second later');
      for (var i = 0; i < 3; i++) {
        click(button);
        audio(400);
      }
      expect(value(arrived), '1', reason: 'each bang starts the wait again');
      audio(700);
      expect(value(arrived), '2', reason: 'one bang, after the last click');
      click(button);
      audio(500);
      click(msg('stop'));
      audio(1000);
      expect(value(arrived), '2', reason: 'stop cancels');
      click(msg('250'));
      expect(value(arrived), '2', reason: 'the right inlet does not start');
      click(button);
      audio(300);
      expect(value(arrived), '3', reason: '250 ms');
      click(msg('2000'));
      audio(1900);
      expect(value(arrived), '3');
      audio(200);
      expect(value(arrived), '4', reason: '2000 sets the time and starts');
      click(msg('1000'));
      click(at('.b', 60, 440));
      audio(400);
      expect(
        (value(at('.i', 340, 490)), value(at('.i', 340, 560))),
        ('0', '0'),
      );
      audio(200);
      expect(
        (value(at('.i', 340, 490)), value(at('.i', 340, 560))),
        ('1', '0'),
      );
      audio(500);
      expect(
        (value(at('.i', 340, 490)), value(at('.i', 340, 560))),
        ('1', '1'),
      );
    });

    test('pipe: every value kept, its own delay, flush, clear, a list', () {
      open('pipe');
      final out = at('.f', 60, 340);
      final arrived = at('.i', 170, 440);
      click(msg('1'));
      audio(100);
      click(msg('2'));
      audio(100);
      click(msg('3.5'));
      audio(750);
      expect(value(arrived), '0', reason: 'nothing yet');
      final seen = <double>[];
      for (var i = 0; i < 3; i++) {
        audio(100);
        seen.add(number(out));
      }
      expect(seen, [1, 2, 3.5], reason: 'all three, in order and spacing');
      expect(value(arrived), '3');
      click(msg('1000'));
      click(msg('1'));
      audio(200);
      click(msg('250'));
      click(msg('2'));
      audio(300);
      expect(number(out), 2, reason: '2 overtakes 1');
      audio(600);
      expect(number(out), 1, reason: '1 keeps its second');
      click(msg('1'));
      click(msg('flush'));
      expect(number(out), 1);
      expect(value(arrived), '6', reason: 'flushed at once');
      click(msg('2'));
      click(msg('clear'));
      audio(500);
      expect(value(arrived), '6', reason: 'cleared, never arrives');
      click(at('.b', 60, 520));
      final list = at('.l', 60, 690);
      audio(400);
      expect(value(list), isEmpty);
      audio(150);
      expect(value(list), '60 64 67', reason: 'the list, half a second later');
    });

    test('line bline: a glide, the grain, a function stepped by bangs', () {
      open('line-bline');
      final smooth = at('.f', 110, 340);
      final steps = at('.f', 270, 340);
      final arrivals = at('.i', 400, 380);
      click(msg('1'));
      final path = <double>[];
      final coarse = <double>[];
      for (var i = 0; i < 22; i++) {
        audio(50);
        path.add(number(smooth));
        coarse.add(number(steps));
      }
      expect(path.last, 1, reason: 'arrives in a second');
      expect(coarse.last, 1);
      expect(path.where((v) => v > 0 && v < 1).length, greaterThan(15));
      expect(
        coarse.where((v) => v > 0 && v < 1).toSet(),
        hasLength(3),
        reason: 'steps of 250 ms: 0.25 0.5 0.75',
      );
      expect(number(at('.slider', 60, 340)), 1, reason: 'the slider rose');
      expect(value(arrivals), '1');
      click(msg('0.3'));
      audio(1100);
      expect(number(smooth), closeTo(0.3, 1e-6));
      expect(value(arrivals), '2');
      // bline: the function's shape as bang counts.
      click(at('.b', 60, 560));
      final out = at('.f', 300, 740);
      final done = at('.i', 440, 780);
      final walk = <double>[];
      for (var i = 0; i < 11; i++) {
        click(at('.b', 300, 560));
        walk.add(number(out));
      }
      expect(walk, [0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.375, 0.25, 0.125, 0]);
      expect(value(done), '1', reason: 'at the end');
      click(at('.b', 60, 560));
      gateway.sendInt(inst, at('.t', 400, 560), 0, 1);
      wait(1300);
      gateway.sendInt(inst, at('.t', 400, 560), 0, 0);
      expect(value(done), '2', reason: 'the metro played it through');
    });

    test('speedlim qlim: one per interval, the last value held by qlim', () {
      open('speedlim-qlim');
      final slider = at('.slider', 60, 160);
      final raw = at('.i', 60, 440);
      final sp = at('.i', 320, 390);
      final ql = at('.i', 510, 390);
      // A drag: a move every 20 ms for two seconds.
      for (var i = 1; i <= 100; i++) {
        gateway.sendFloat(inst, slider, 0, i / 100);
        audio(20);
      }
      expect(whole(raw), 100);
      expect(whole(sp), inInclusiveRange(4, 5), reason: 'twice a second');
      expect(whole(ql), inInclusiveRange(4, 5));
      audio(600);
      expect(number(at('.f', 430, 290)), closeTo(100, 1e-3), reason: 'held');
      expect(number(at('.f', 240, 290)), lessThan(100), reason: 'dropped');
      expect(whole(ql), whole(sp) + 1, reason: 'qlim sent the last one');
      click(msg('0'));
      expect((value(raw), value(sp), value(ql)), ('0', '0', '0'));
      click(msg('100'));
      for (var i = 1; i <= 50; i++) {
        gateway.sendFloat(inst, slider, 0, i / 50);
        audio(20);
      }
      expect(whole(sp), inInclusiveRange(9, 11), reason: 'every 100 ms');
    });

    test('timer clocker: a tap tempo, a stopwatch, an elapsed count', () {
      open('timer-clocker');
      final tap = at('.b', 60, 160);
      final ms = at('.f', 60, 340);
      click(tap);
      wait(500);
      click(tap);
      expect(number(ms), closeTo(500, 40), reason: 'between the taps');
      expect(number(at('.f', 60, 450)), closeTo(60000 / number(ms), 1e-3));
      expect(number(at('.f', 60, 450)), closeTo(120, 10), reason: 'bpm');
      gateway.sendInt(inst, at('.t', 200, 160), 0, 1);
      wait(1120);
      gateway.sendInt(inst, at('.t', 200, 160), 0, 0);
      expect(whole(at('.i', 200, 500)), 3, reason: 'the metro at the tempo');
      final lap = at('.f', 360, 280);
      click(at('.b', 360, 160));
      wait(200);
      click(at('.b', 460, 160));
      expect(number(lap), closeTo(200, 40));
      wait(200);
      click(at('.b', 460, 160));
      expect(number(lap), closeTo(400, 40), reason: 'lap keeps the start');
      final elapsed = at('.i', 60, 700);
      gateway.sendInt(inst, at('.t', 60, 580), 0, 1);
      wait(450);
      expect(whole(elapsed), 400, reason: 'every 100 ms, the time so far');
      click(at('.b', 170, 580));
      wait(150);
      expect(whole(elapsed), lessThan(200), reason: 'the button restarts');
      click(msg('1000'));
      wait(400);
      final held = whole(elapsed);
      wait(300);
      expect(whole(elapsed), held, reason: 'once a second now');
      gateway.sendInt(inst, at('.t', 60, 580), 0, 0);
      click(msg('100'));
    });

    test('thresh quickthresh: a chord, a pause, a trickle', () {
      open('thresh-quickthresh');
      final tl = at('.l', 60, 340);
      final ql = at('.l', 300, 340);
      final tn = at('.i', 180, 440);
      final qn = at('.i', 420, 440);
      click(at('.b', 400, 160));
      audio(350);
      expect((value(tl), value(ql)), ('60 64 67', '60 64 67'));
      expect((value(tn), value(qn)), ('1', '1'));
      // By hand: a click every 200 ms.
      for (final m in ['60', '64', '67']) {
        click(msg(m));
        audio(200);
      }
      audio(400);
      expect(value(tl), '60 64 67', reason: 'never a 300 ms pause');
      expect(value(tn), '2');
      expect(value(ql), '60 64', reason: 'closed 300 ms after the first');
      expect(value(qn), '3', reason: '67 alone is a group of its own');
      // The trickle: the counter stepped every 150 ms.
      final counter = at('.counter', 60, 640);
      for (var i = 0; i < 12; i++) {
        click(counter);
        audio(150);
      }
      expect(value(tn), '2', reason: 'thresh holds on');
      expect(whole(qn), inInclusiveRange(6, 9), reason: 'two or three each');
      audio(300);
      expect(value(tl), '1 2 3 4 5 6 7 8 9 10 11 12', reason: 'one long list');
    });
  });

  test(
    'every transport, tempo and domain clock type has a tutorial (#498)',
    () {
      for (final type in [
        '.transport', '.tempo', '.timepoint', '.setclock', '.when', //
        '.translate',
      ]) {
        expect(index.hasTutorial(type), isTrue, reason: type);
      }
    },
  );

  group('transport, tempo and domain clock tutorials (#498) do what their '
      'notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    // One block is 128 frames at 48 kHz: about 2.67 ms of audio.
    const blockMs = 128 / 48;
    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // [ms] milliseconds of audio time. Domain clocks advance with the audio
    // blocks, and a tempo write lands on the next block.
    void audio(double ms) => render((ms / blockMs).ceil());

    // Every tutorial is mounted while open (#528); so is this copy.
    void open(String slug) {
      inst = gateway.createInstance();
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: '$slug mounted');
      render(20);
    }

    tearDown(() {
      gateway.disposeInstance(inst);
      render(20);
    });

    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    // A message box by its text: each tutorial's are unique.
    int msg(String text) => graph.objects
        .singleWhere((o) => o.type == '.m' && o.args == text)
        .handleId;
    // A click, and the block a tempo write takes to land on its clock.
    void click(int id) {
      gateway.sendBang(inst, id, 0);
      render(1);
    }

    void toggle(int id, int on) {
      gateway.sendInt(inst, id, 0, on);
      render(1);
    }

    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));
    int whole(int id) => int.parse(value(id));
    // metro keeps wall-clock time.
    void wait(int ms) => sleep(Duration(milliseconds: ms));

    test('transport: start, stop, the tempo, a glide, the beat on a bang', () {
      open('transport');
      final beat = at('.f', 60, 440);
      final bpm = at('.f', 220, 440);
      // The button above transport asks where the clock is.
      void ask() => gateway.sendBang(inst, at('.b', 260, 320), 0);
      ask();
      expect(number(bpm), 0, reason: 'loadmess 0: stopped on load');
      final start = number(beat);
      click(msg('start'));
      audio(1000);
      ask();
      expect(number(bpm), 120);
      expect(number(beat), closeTo(start + 2, 0.02), reason: '2 a second');
      click(msg('stop'));
      ask();
      final held = number(beat);
      audio(500);
      ask();
      expect((number(beat), number(bpm)), (held, 0), reason: 'a pause');
      toggle(at('.t', 60, 160), 1);
      audio(500);
      ask();
      expect(number(beat), closeTo(held + 1, 0.02), reason: 'carries on');
      click(msg('60'));
      final slow = number(beat);
      audio(1000);
      ask();
      expect(number(bpm), 60, reason: 'at once while running');
      expect(number(beat), closeTo(slow + 1, 0.02));
      toggle(at('.t', 60, 160), 0);
      click(msg('120'));
      ask();
      expect(number(bpm), 0, reason: 'kept for the next start');
      click(msg('start'));
      audio(100);
      ask();
      expect(number(bpm), 120);
      expect(
        whole(at('.i', 60, 550)),
        (number(beat) / 4).floor(),
        reason: 'the bar in 4/4',
      );
      click(at('.b', 360, 220));
      audio(2000);
      ask();
      expect(number(bpm), closeTo(180, 2), reason: 'half way to 240');
      audio(2100);
      ask();
      expect(number(bpm), 240, reason: 'over 4 seconds');
      // The watch toggle: metro asks ten times a second.
      final before = number(beat);
      toggle(at('.t', 540, 250), 1);
      audio(500);
      wait(250);
      expect(number(beat), greaterThan(before + 1.5), reason: 'followed');
      toggle(at('.t', 540, 250), 0);
      click(msg('stop'));
    });

    test('tempo: quarter notes round a bar, the tempo, the division', () {
      open('tempo');
      final count = at('.i', 60, 360);
      final bars = at('.i', 200, 460);
      final steps = at('.i', 340, 460);
      toggle(at('.t', 60, 160), 1);
      expect((value(count), value(bars), value(steps)), ('0', '1', '1'));
      final seen = <int>[];
      for (var i = 0; i < 16; i++) {
        audio(125);
        if (seen.isEmpty || seen.last != whole(count)) seen.add(whole(count));
      }
      expect(seen, [0, 1, 2, 3, 0], reason: 'a quarter note is 500 ms');
      expect((value(bars), value(steps)), ('2', '5'));
      click(msg('60'));
      audio(900);
      expect(value(steps), '5', reason: 'a beat is a second now');
      audio(200);
      expect(value(steps), '6');
      click(msg('180'));
      click(msg('16'));
      final from = whole(steps);
      audio(1000);
      expect(
        whole(steps) - from,
        inInclusiveRange(11, 13),
        reason: '12 sixteenths a second at 180',
      );
      final shown = <int>{};
      for (var i = 0; i < 40; i++) {
        audio(1000 / 12);
        shown.add(whole(count));
      }
      expect(shown.reduce(math.max), 15, reason: 'a cycle of 16');
      toggle(at('.t', 60, 160), 0);
      final stopped = whole(steps);
      audio(500);
      expect(whole(steps), stopped, reason: 'off stops the count');
    });

    test('timepoint: a bang four beats from now, a passed beat, active', () {
      open('timepoint');
      final now = at('.f', 60, 320);
      final target = at('.f', 220, 320);
      final fired = at('.i', 220, 490);
      final firedAt = at('.f', 360, 490);
      double ask() {
        gateway.sendBang(inst, at('.when', 60, 260), 0);
        return number(now);
      }

      final start = ask();
      audio(500);
      expect(ask(), closeTo(start + 0.5, 0.02), reason: '60 BPM');
      click(at('.b', 220, 160));
      expect(number(target), closeTo(ask() + 4, 0.02), reason: 'now + 4');
      audio(3800);
      expect(value(fired), '0', reason: 'not yet');
      audio(400);
      expect(value(fired), '1', reason: 'four beats later');
      expect(number(firedAt), closeTo(number(target), 0.02));
      // A beat already passed never bangs.
      gateway.sendFloat(inst, target, 0, ask() - 1);
      audio(1500);
      expect(value(fired), '1', reason: 'spent');
      // active 0 lets the beat go by; active 1 arms it again.
      gateway.sendFloat(inst, target, 0, ask() + 1);
      click(msg('0'));
      audio(1500);
      expect(value(fired), '1', reason: 'active 0');
      gateway.sendFloat(inst, target, 0, ask() + 2);
      click(msg('0'));
      audio(500);
      click(msg('1'));
      audio(2000);
      expect(value(fired), '2', reason: 'active 1, still ahead');
      // The watch: metro asks four times a second.
      toggle(at('.t', 60, 160), 1);
      final watched = number(now);
      audio(1000);
      wait(400);
      expect(number(now), greaterThan(watched + 0.9));
      toggle(at('.t', 60, 160), 0);
    });

    test('setclock: two clocks, a metro on each, a delay in beats', () {
      open('setclock');
      final left = at('.i', 60, 470);
      final right = at('.i', 300, 470);
      toggle(at('.t', 60, 300), 1);
      expect((value(left), value(right)), ('1', '1'), reason: 'at once');
      audio(1020);
      expect((value(left), value(right)), ('2', '5'), reason: '60 and 240');
      click(msg('120'));
      audio(1020);
      expect(whole(left), 4, reason: 'twice as fast at 120');
      click(msg('0'));
      audio(2000);
      expect(whole(left), 4, reason: 'a stopped clock');
      expect(whole(right), greaterThan(12), reason: 'fast runs on');
      click(msg('60'));
      toggle(at('.t', 60, 300), 0);
      final arrived = at('.i', 60, 730);
      click(at('.b', 60, 560));
      audio(3800);
      expect(value(arrived), '0', reason: 'four beats at 60');
      audio(400);
      expect(value(arrived), '1');
      click(msg('120'));
      click(at('.b', 60, 560));
      audio(1800);
      expect(value(arrived), '1', reason: 'four beats at 120');
      audio(400);
      expect(value(arrived), '2');
      click(msg('0'));
      click(at('.b', 60, 560));
      audio(3000);
      expect(value(arrived), '2', reason: 'not while slow is at 0');
      click(msg('60'));
      audio(4200);
      expect(value(arrived), '3', reason: 'and on again');
    });

    test('when: beat and tempo on any input; asking makes no clock', () {
      open('when');
      final beat = at('.f', 300, 340);
      final bpm = at('.f', 440, 340);
      click(at('.b', 300, 160));
      expect(number(bpm), 0, reason: 'loadmess 0');
      final start = number(beat);
      toggle(at('.t', 60, 160), 1);
      audio(1000);
      click(at('.b', 300, 160));
      expect(number(beat), closeTo(start + 2, 0.02), reason: '2 a second');
      expect(number(bpm), 120);
      audio(500);
      click(msg('42'));
      expect(number(beat), closeTo(start + 3, 0.02), reason: 'any input');
      toggle(at('.t', 500, 160), 1);
      audio(1000);
      wait(600);
      expect(number(beat), greaterThan(start + 4.4), reason: 'the metro');
      toggle(at('.t', 500, 160), 0);
      toggle(at('.t', 60, 160), 0);
      click(at('.b', 300, 160));
      expect(number(bpm), 0, reason: 'paused');
      click(at('.b', 300, 440));
      expect(value(at('.i', 300, 660)), '0', reason: 'no answer at all');
    });

    test('translate: ms to beats, ticks and Hz, again, note values', () {
      open('translate');
      final beats = at('.f', 60, 480);
      final ticks = at('.f', 270, 480);
      final hz = at('.f', 480, 480);
      final ms = at('.f', 60, 680);
      click(msg('500'));
      expect((number(beats), number(ticks), number(hz)), (1, 480, 2));
      click(msg('250'));
      expect((number(beats), number(ticks), number(hz)), (0.5, 240, 4));
      click(msg('1000'));
      click(msg('240'));
      expect(number(beats), 2, reason: 'not followed by itself');
      click(at('.b', 420, 300));
      expect((number(beats), number(ticks), number(hz)), (4, 1920, 1));
      click(msg('4n'));
      expect(number(ms), 250, reason: 'a quarter note at 240');
      click(msg('120'));
      click(msg('4n'));
      expect(number(ms), 500);
      click(msg('8n'));
      expect(number(ms), 250);
      click(msg('8nt'));
      expect(number(ms), closeTo(1000 / 6, 1e-3));
      click(msg('4nd'));
      expect(number(ms), 750);
      click(msg('2'));
      expect(number(ms), 1000);
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
