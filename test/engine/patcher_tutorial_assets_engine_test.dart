import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_level.dart' as phi;
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/domain/patcher/patch_type_name.dart';
import 'package:phi/domain/patcher/tutorial/patch_tutorial.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_catalog.dart';
import 'package:phi/domain/patcher/tutorial/tutorial_slug.dart';
import 'package:phi/engine/bridge/patch_pin_compatibility.dart';
import 'package:phi/engine/bridge/patcher_graph_snapshot.dart';
import 'package:phi/engine/bridge/real_patcher_gateway.dart';
import 'package:phi/engine/state/tutorial/patch_tutorial_session.dart';
import 'package:phi/shell/diagnostics/engine_log_level.dart';
import 'package:yse/yse.dart';

import '../surfaces/patcher/test_support/engine_file_dir.dart';

import 'test_support/midi_capture.dart';
import 'test_support/midi_driver_unavailable.dart';
import 'test_support/midi_loopback.dart';

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
      final inst = gateway.createInstance(mainOutputs: 1);
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

  // A tutorial opens as a patch with one main output, so its ~dac has one
  // inlet. A cord into an inlet the engine does not have is refused with
  // "Patcher: Invalid Connection", an error the log badges (#539). Every
  // tutorial is opened through PatchTutorialSession, the path the app takes,
  // and must log no engine error at all. (The tests below open their
  // instances with one main output too, the way the app does.)
  //
  // One exception, a fact about the host rather than the tutorial: on a
  // machine with no MIDI system (a CI runner without an ALSA sequencer), a
  // MIDI input object logs RtMidi's driver error when it opens, and so does a
  // .midiout when it opens its port in the background (#509). That line is
  // set apart only when it matches that message exactly and the tutorial, or
  // the one just before it for a line that arrived late, holds a MIDI port
  // object.
  test('every tutorial opens the way the app opens it without an engine '
      'error (#539)', () async {
    final lines = <String>[];
    final sub = Log.instance.messages.listen(lines.add);
    addTearDown(sub.cancel);
    final errors = <String>[];
    final hostErrors = <String>[];
    var heldPortBefore = false;
    for (final slug in index.slugs) {
      lines.clear();
      final tutorial = load(slug);
      final holdsPort = holdsMidiPort(tutorial.payload.dump);
      final midiWindow = holdsPort || heldPortBefore;
      heldPortBefore = holdsPort;
      final session = PatchTutorialSession.open(
        gateway,
        tutorial: tutorial,
        slug: slug,
      );
      // The engine's lines arrive through a port, in order: once this marker
      // is back, every line the open logged is in [lines].
      final marker = 'end of tutorial $slug (#539)';
      Log.instance.sendMessage(marker);
      final clock = Stopwatch()..start();
      while (!lines.any((l) => l.contains(marker)) &&
          clock.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(
        lines.any((l) => l.contains(marker)),
        isTrue,
        reason: 'the engine log reached the test after $slug',
      );
      session.dispose();
      for (final line in lines) {
        if (line.contains(marker)) continue;
        if (engineLogLevel(line) != phi.LogLevel.error) continue;
        if (midiWindow && isMidiDriverUnavailable(line)) {
          hostErrors.add('$slug: $line');
        } else {
          errors.add('$slug: $line');
        }
      }
    }
    expect(errors, isEmpty);
    if (hostErrors.isNotEmpty) {
      // ignore: avoid_print
      print('no MIDI system on this host:\n  ${hostErrors.join('\n  ')}');
    }
  });

  test('the metro tutorial sets itself up on load', () {
    final tutorial = load('metro');
    final inst = gateway.createInstance(mainOutputs: 1);
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
      inst = gateway.createInstance(mainOutputs: 1);
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
      inst = gateway.createInstance(mainOutputs: 1);
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
      inst = gateway.createInstance(mainOutputs: 1);
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
      inst = gateway.createInstance(mainOutputs: 1);
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
      expect(numbers(at('.l', 390, 340)), [3, 600, 0, 0.5]);
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
      expect(numbers(at('.l', 200, 440)), hasLength(4), reason: 'distances');
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
      inst = gateway.createInstance(mainOutputs: 1);
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
      inst = gateway.createInstance(mainOutputs: 1);
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
      inst = gateway.createInstance(mainOutputs: 1);
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
      inst = gateway.createInstance(mainOutputs: 1);
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

    // Their readings depend on how much real time the test takes, and a
    // sleep can overshoot on a busy or coarse-timed runner (#532). So each
    // reading is bounded by real time measured on this stopwatch, not by a
    // fixed window: at least the time from the end of one action to the
    // start of the next, at most the time from the start of the first to
    // the end of the second.
    final clock = Stopwatch()..start();
    double now() => clock.elapsedMicroseconds / 1000;
    // Runs [act] and returns when, on [clock], it started and ended.
    ({double start, double end}) timed(void Function() act) {
      final start = now();
      act();
      return (start: start, end: now());
    }

    // Scheduling jitter of a wall-clock object, in ms.
    const slack = 50.0;
    // How far the engine's clock and this stopwatch may disagree, in ms.
    const margin = 5.0;
    // The ticks of a metro of [period] ms switched on by [on] and read (or
    // switched off) at [off]: one at once, then one per period.
    Matcher ticksBetween(
      ({double start, double end}) on,
      ({double start, double end}) off,
      double period,
    ) => inInclusiveRange(
      1 + math.max(0, ((off.start - on.end - slack) / period).floor()),
      1 + ((off.end - on.start + slack) / period).floor(),
    );
    // The same, read now.
    Matcher ticksSince(({double start, double end}) on, double period) {
      final t = now();
      return ticksBetween(on, (start: t, end: t), period);
    }

    // What a timer bounded by [from] and [to] can have measured.
    Matcher spanning(
      ({double start, double end}) from,
      ({double start, double end}) to,
    ) => inInclusiveRange(
      to.start - from.end - margin,
      to.end - from.start + margin,
    );

    test('metro: on and off, the interval while running, bang and stop', () {
      open('metro');
      final toggle = at('.t', 60, 160);
      final ticks = at('.i', 60, 400);
      expect(value(at('.i', 360, 230)), '500', reason: 'loadmess on load');
      final on = timed(() => gateway.sendInt(inst, toggle, 0, 1));
      expect(whole(ticks), ticksSince(on, 500), reason: 'a tick at once');
      wait(1120);
      expect(whole(ticks), ticksSince(on, 500), reason: 'one every 500 ms');
      expect(whole(ticks), greaterThanOrEqualTo(3));
      final before = whole(ticks);
      final faster = timed(() => click(msg('125')));
      wait(1030);
      // The new interval takes over from the next tick of the old one,
      // which is at most 500 ms away; after it, one tick every 125 ms. At
      // 500 ms no more than three ticks fit in this wait.
      final t = now();
      expect(
        whole(ticks) - before,
        inInclusiveRange(
          math.max(4, 1 + ((t - faster.end - 500 - slack) / 125).floor()),
          1 + ((t - faster.start + slack) / 125).floor(),
        ),
        reason: 'four times as fast, without stopping',
      );
      gateway.sendInt(inst, toggle, 0, 0);
      final stopped = whole(ticks);
      wait(300);
      expect(whole(ticks), stopped, reason: '0 stops it');
      final banged = timed(() => click(msg('bang')));
      expect(
        whole(ticks) - stopped,
        ticksSince(banged, 125),
        reason: 'bang starts it, at once',
      );
      wait(80);
      final readAt = now();
      final mid = whole(ticks);
      final again = timed(() => click(msg('bang')));
      expect(
        whole(ticks) - mid,
        ticksSince((start: readAt, end: again.end), 125),
        reason: 'and restarts it from now, with a tick',
      );
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
      final tap1 = timed(() => click(tap));
      wait(500);
      final tap2 = timed(() => click(tap));
      final between = number(ms);
      expect(between, greaterThanOrEqualTo(500), reason: 'the wait at least');
      expect(between, spanning(tap1, tap2), reason: 'between the taps');
      expect(number(at('.f', 60, 450)), closeTo(60000 / between, 1e-3));
      final on = timed(() => gateway.sendInt(inst, at('.t', 200, 160), 0, 1));
      wait(1120);
      final off = timed(() => gateway.sendInt(inst, at('.t', 200, 160), 0, 0));
      expect(
        whole(at('.i', 200, 500)),
        ticksBetween(on, off, between),
        reason: 'the metro at the tempo',
      );
      final lap = at('.f', 360, 280);
      final start = timed(() => click(at('.b', 360, 160)));
      wait(200);
      final lap1 = timed(() => click(at('.b', 460, 160)));
      expect(number(lap), greaterThanOrEqualTo(200));
      expect(number(lap), spanning(start, lap1), reason: 'the stopwatch');
      final first = number(lap);
      wait(200);
      final lap2 = timed(() => click(at('.b', 460, 160)));
      expect(number(lap), spanning(start, lap2), reason: 'lap keeps the start');
      expect(number(lap) - first, spanning(lap1, lap2));
      final elapsed = at('.i', 60, 700);
      final started = timed(
        () => gateway.sendInt(inst, at('.t', 60, 580), 0, 1),
      );
      wait(450);
      // Every 100 ms clocker sends the whole milliseconds since its start:
      // within jitter of a multiple of 100, at most one interval old.
      final readAt = now();
      final so = whole(elapsed);
      expect(
        so,
        inInclusiveRange(
          readAt - started.end - 100 - slack,
          now() - started.start + margin,
        ),
        reason: 'every 100 ms, the time so far',
      );
      expect(so, greaterThanOrEqualTo(450 - 100), reason: 'the wait');
      expect(so % 100, lessThanOrEqualTo(slack), reason: 'on the interval');
      final restart = timed(() => click(at('.b', 170, 580)));
      // Long enough for a report (100 ms plus jitter) to arrive.
      wait(250);
      expect(
        whole(elapsed),
        lessThanOrEqualTo(now() - restart.start + margin),
        reason: 'the button restarts',
      );
      final slower = timed(() => click(msg('1000')));
      wait(400);
      final held = whole(elapsed);
      wait(300);
      // The next report comes a second after the last one, which was at
      // most 100 ms before the click: none can land sooner than that.
      if (whole(elapsed) != held) {
        expect(
          now() - slower.start,
          greaterThan(900 - slack),
          reason: 'once a second now',
        );
      }
      gateway.sendInt(inst, at('.t', 60, 580), 0, 0);
      click(msg('100'));
    });

    test('thresh quickthresh: a chord, a pause, a trickle', () {
      open('thresh-quickthresh');
      final tl = at('.l', 60, 490);
      final ql = at('.l', 300, 340);
      final tn = at('.i', 180, 440);
      final qn = at('.i', 540, 440);
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
      inst = gateway.createInstance(mainOutputs: 1);
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
      // Phi's drum domain clock, as the engine publishes it for a new
      // project (#529).
      final drum = gateway.publishClock('domain.drum', tempo: 124)!;
      addTearDown(drum.dispose);
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
      // when domain.drum reads Phi's drum domain clock (#529).
      final drumBeat = at('.f', 300, 680);
      final drumBpm = at('.f', 440, 680);
      void askDrum() => click(at('.b', 300, 560));
      askDrum();
      expect(number(drumBpm), 124, reason: 'the drum domain\'s tempo');
      final from = number(drumBeat);
      audio(1000);
      askDrum();
      expect(number(drumBeat), closeTo(from + 124 / 60, 0.02));
      // Phi re-tempos the clock when the domain's tempo changes.
      drum.setTempo(62);
      render(1);
      final slower = number(drumBeat);
      askDrum();
      final at62 = number(drumBeat);
      expect(number(drumBpm), 62);
      expect(at62, closeTo(slower, 0.02));
      audio(1000);
      askDrum();
      expect(number(drumBeat), closeTo(at62 + 62 / 60, 0.02));
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
      final drum = gateway.publishClock('domain.drum', tempo: 124)!;
      addTearDown(drum.dispose);
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
      // A metro on Phi's drum domain clock (#529): once a beat at 124 BPM,
      // and at the new tempo once Phi changes it.
      final ticks = at('.i', 360, 790);
      toggle(at('.t', 360, 620), 1);
      expect(value(ticks), '1', reason: 'at once');
      audio(2000);
      expect(whole(ticks), 5, reason: '4.1 beats in 2 s at 124');
      drum.setTempo(248);
      render(1);
      final before = whole(ticks);
      audio(1000);
      expect(whole(ticks) - before, inInclusiveRange(4, 5), reason: 'at 248');
      toggle(at('.t', 360, 620), 0);
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

  test('every control flow and ordering type has a tutorial (#499)', () {
    for (final type in [
      '.trigger', '.bangbang', '.uzi', '.if', '.loadbang', '.loadmess', //
      '.onebang', '.buddy', '.bondo', '.next', '.match',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.loadbang'), index.tutorialFor('.loadmess'));
    expect(index.tutorialFor('.buddy'), index.tutorialFor('.bondo'));
    expect(index.tutorialFor('.next'), index.tutorialFor('.match'));
  });

  group('control flow and ordering tutorials (#499) do what their notes '
      'say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // The loudest master peak over the next [blocks] blocks.
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

    // Every tutorial is mounted while open (#528); so is this copy.
    void open(String slug) {
      inst = gateway.createInstance(mainOutputs: 1);
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
    void click(int id) => gateway.sendBang(inst, id, 0);
    // Typing a number into a box sends it on.
    void type(int id, num v) => v is int
        ? gateway.sendInt(inst, id, 0, v)
        : gateway.sendFloat(inst, id, 0, v.toDouble());
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));
    // metro keeps wall-clock time.
    void wait(int ms) => sleep(Duration(milliseconds: ms));

    test('trigger: five conversions, right to left, broken vs fixed', () {
      open('trigger');
      final bangs = at('.i', 60, 380);
      final i = at('.i', 160, 380);
      final f = at('.f', 250, 380);
      final l = at('.l', 340, 380);
      final constant = at('.i', 460, 380);
      type(at('.f', 60, 160), 2.7);
      expect(value(bangs), '1', reason: 'b bangs the counter');
      expect(value(i), '2', reason: 'i truncates');
      expect(number(f), closeTo(2.7, 1e-6), reason: 'f keeps it');
      expect(value(constant), '7', reason: 'a constant');
      click(at('.b', 180, 160));
      expect(value(l), '5 6', reason: 'l passes the list on');
      expect((value(i), number(f)), ('0', 0), reason: 'no list in i or f');
      expect(value(bangs), '2');
      click(at('.b', 480, 160));
      expect(value(at('.l', 480, 320)), '3 2 1', reason: 'right to left');
      final x = at('.i', 60, 480);
      final broken = at('.i', 60, 610);
      final fixed = at('.i', 240, 670);
      type(x, 5);
      expect((value(broken), value(fixed)), ('5', '10'));
      type(x, 7);
      expect((value(broken), value(fixed)), ('12', '14'));
    });

    test('bangbang: right to left, and store then fire', () {
      open('bangbang');
      click(at('.b', 60, 160));
      expect(value(at('.l', 60, 390)), '3 2 1');
      click(msg('42'));
      expect(value(at('.l', 60, 390)), '3 2 1', reason: 'a number bangs');
      final box = at('.i', 60, 650);
      final out = at('.i', 60, 770);
      for (var n = 1; n <= 3; n++) {
        click(at('.b', 60, 480));
        expect(value(box), '$n');
        expect(value(out), '${n * 10}', reason: 'the right branch first');
      }
    });

    test('uzi: four bangs, a carry, the count, a table in one click', () {
      open('uzi');
      final bangs = at('.i', 60, 330);
      final carry = at('.i', 200, 330);
      final index = at('.i', 340, 330);
      click(at('.b', 60, 160));
      expect((value(bangs), value(carry), value(index)), ('4', '1', '4'));
      click(msg('5'));
      expect((value(bangs), value(carry), value(index)), ('9', '2', '5'));
      click(msg('2'));
      expect(value(bangs), '9', reason: 'the right inlet only sets');
      click(at('.b', 60, 160));
      expect((value(bangs), value(carry), value(index)), ('11', '3', '2'));
      final out = at('.i', 60, 770);
      click(at('.b', 60, 430));
      for (final a in [0, 3, 7]) {
        type(at('.i', 420, 650), a);
        expect(value(out), '${a * 12}', reason: 'address $a');
      }
      click(msg('sum'));
      expect(value(out), '336');
      click(msg('clear'));
      click(msg('sum'));
      expect(value(out), '0');
    });

    test('if: then and else, two inlets, a filter', () {
      open('if');
      final above = at('.i', 60, 490);
      final below = at('.i', 360, 440);
      final box = at('.i', 60, 320);
      type(box, 100);
      expect(value(above), '1');
      type(box, 65);
      expect(value(above), '2');
      type(box, 64);
      expect((value(above), value(below)), ('2', '64'));
      type(box, 10);
      expect((value(above), value(below)), ('2', '10'));
      // The slider drives the box.
      gateway.sendFloat(inst, at('.slider', 60, 160), 0, 0.75);
      expect((value(box), value(above)), ('95', '3'), reason: '0.75 * 127');
      final larger = at('.i', 60, 700);
      type(at('.i', 200, 580), 30);
      expect(value(larger), '0', reason: 'the right inlet only stores');
      type(at('.i', 60, 580), 20);
      expect(value(larger), '30');
      type(at('.i', 60, 580), 50);
      expect(value(larger), '50');
      final even = at('.i', 400, 700);
      type(at('.i', 400, 580), 4);
      expect(value(even), '4');
      type(at('.i', 400, 580), 3);
      expect(value(even), '4', reason: 'odd: nothing');
      type(at('.i', 400, 580), 8);
      expect(value(even), '8');
    });

    test('loadbang and loadmess: a gain and a metro set up on open', () {
      open('loadbang-loadmess');
      final gain = at('.f', 60, 220);
      expect(number(gain), closeTo(0.1, 1e-6), reason: 'loadmess 0.1');
      // A tutorial is one channel, centred on master: each side 3 dB down.
      final level = loudness();
      expect(level, closeTo(0.1 / math.sqrt2, 0.01), reason: 'the sine at 0.1');
      final ticks = at('.i', 60, 720);
      expect(value(at('.t', 60, 500)), 'on', reason: 'loadbang');
      final first = int.parse(value(ticks));
      expect(first, greaterThanOrEqualTo(1));
      wait(1100);
      expect(int.parse(value(ticks)), greaterThanOrEqualTo(first + 2));
      gateway.sendInt(inst, at('.t', 60, 500), 0, 0);
      click(msg('0'));
      expect(loudness(), 0, reason: 'silenced');
      click(at('.b', 300, 560));
      expect(number(gain), closeTo(0.1, 1e-6), reason: 'sent again');
      gateway.sendFloat(inst, at('.loadmess', 60, 160), 0, 0.5);
      expect(number(gain), closeTo(0.1, 1e-6), reason: 'a number: ignored');
      click(msg('0.02'));
      expect(number(gain), closeTo(0.1, 1e-6), reason: 'set does not send');
      click(at('.b', 300, 560));
      expect(number(gain), closeTo(0.02, 1e-6));
      expect(loudness(), closeTo(level / 5, 0.005), reason: 'a fifth as loud');
      click(msg('0'));
    });

    test('onebang: once, then the other way, armed again, stop', () {
      open('onebang');
      final passed = at('.i', 60, 350);
      final held = at('.i', 220, 350);
      final trigger = at('.b', 60, 160);
      final arm = at('.b', 400, 160);
      click(trigger);
      expect((value(passed), value(held)), ('1', '0'), reason: 'armed');
      click(trigger);
      click(trigger);
      expect((value(passed), value(held)), ('1', '2'));
      click(arm);
      click(arm);
      click(msg('0'));
      click(trigger);
      expect((value(passed), value(held)), ('2', '3'), reason: 'once');
      click(arm);
      click(msg('stop'));
      expect((value(passed), value(held)), ('2', '3'), reason: 'silent');
      click(trigger);
      expect((value(passed), value(held)), ('2', '4'), reason: 'called off');
    });

    test('buddy and bondo: wait for all, or send on any change', () {
      open('buddy-bondo');
      final o0 = at('.i', 60, 280);
      final o1 = at('.i', 200, 280);
      final sends = at('.i', 340, 380);
      type(at('.i', 200, 160), 60);
      expect(value(sends), '0', reason: 'waiting for the left');
      type(at('.i', 60, 160), 100);
      expect((value(o0), value(o1), value(sends)), ('100', '60', '1'));
      type(at('.i', 60, 160), 72);
      expect(value(sends), '1', reason: 'empty again');
      click(msg('clear'));
      type(at('.i', 200, 160), 61);
      expect(value(sends), '1', reason: 'clear forgot the 72');
      type(at('.i', 60, 160), 73);
      expect((value(o0), value(o1), value(sends)), ('73', '61', '2'));
      final q0 = at('.i', 60, 600);
      final q1 = at('.i', 200, 600);
      final sends2 = at('.i', 340, 700);
      type(at('.i', 200, 480), 60);
      expect((value(q0), value(q1), value(sends2)), ('0', '60', '1'));
      type(at('.i', 60, 480), 100);
      expect((value(q0), value(q1), value(sends2)), ('100', '60', '2'));
      click(at('.b', 340, 480));
      expect((value(q0), value(q1), value(sends2)), ('100', '60', '3'));
    });

    test('next and match: one event per click, a pattern with nn', () {
      open('next-match');
      final first = at('.i', 60, 420);
      final rest = at('.i', 200, 420);
      click(at('.b', 60, 160));
      expect((value(first), value(rest)), ('1', '0'));
      click(msg('42'));
      expect((value(first), value(rest)), ('2', '0'), reason: 'a click');
      click(at('.b', 300, 160));
      expect((value(first), value(rest)), ('3', '2'), reason: 'uzi 3');
      final found = at('.i', 240, 740);
      final list = at('.l', 60, 640);
      for (final n in ['60', '64', '67']) {
        click(msg(n));
      }
      expect((value(list), value(found)), ('60 64 67', '1'));
      for (final n in ['60', '62', '67']) {
        click(msg(n));
      }
      expect((value(list), value(found)), ('60 62 67', '2'));
      click(msg('60'));
      click(msg('67'));
      expect(value(found), '2', reason: '67 took the nn place');
      click(msg('64'));
      expect(value(found), '2', reason: '60 67 64 is no match');
      click(msg('clear'));
      for (final n in ['60', '64', '67']) {
        click(msg(n));
      }
      expect(value(found), '3');
    });
  });

  test('every routing type has a tutorial (#500)', () {
    for (final type in [
      '.route', '.routepass', '.sel', '.gate', '.switch', '.router', //
      '.matrix', '.split', '.spray', '.funnel', '.cycle', '.bucket', '.decode',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.route'), index.tutorialFor('.routepass'));
    expect(index.tutorialFor('.gate'), index.tutorialFor('.switch'));
    expect(index.tutorialFor('.router'), index.tutorialFor('.matrix'));
    expect(index.tutorialFor('.spray'), index.tutorialFor('.funnel'));
    expect(index.tutorialFor('.spray'), index.tutorialFor('.cycle'));
    expect(index.tutorialFor('.bucket'), index.tutorialFor('.decode'));
  });

  group('routing tutorials (#500) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Every tutorial is mounted while open (#528); so is this copy.
    void open(String slug) {
      inst = gateway.createInstance(mainOutputs: 1);
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
    void click(int id) => gateway.sendBang(inst, id, 0);
    // Typing a number into a box sends it on.
    void type(int id, num v) => v is int
        ? gateway.sendInt(inst, id, 0, v)
        : gateway.sendFloat(inst, id, 0, v.toDouble());
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));

    test('route and routepass: stripped, matched by value, the rest', () {
      open('route-routepass');
      final note = at('.l', 60, 360);
      final ctl = at('.l', 170, 360);
      final fives = at('.i', 280, 410);
      final halves = at('.i', 390, 410);
      final rest = at('.i', 500, 360);
      click(msg('100'));
      expect(value(note), '60 100', reason: 'the word taken off');
      expect(value(at('.l', 60, 560)), 'note 60 100', reason: 'routepass');
      click(msg('64'));
      expect(value(ctl), '7 64');
      expect(value(at('.l', 200, 560)), 'ctl 7 64');
      click(msg('5'));
      expect(value(fives), '1', reason: 'nothing left: a bang');
      click(msg('5.0'));
      expect(value(fives), '2', reason: '5.0 is the number 5');
      click(msg('0.5'));
      expect(value(halves), '1');
      gateway.sendFloat(inst, at('.route', 60, 280), 0, 0.50001);
      expect(value(halves), '1', reason: 'exact: 0.50001 is not 0.5');
      click(msg('7'));
      expect(value(rest), '7', reason: 'unmatched, out the right');
      expect(value(at('.i', 340, 560)), '7', reason: 'routepass: the right');
      expect((value(note), value(fives)), ('60 100', '2'));
    });

    test('sel: C E G named, the rest passed on, words', () {
      open('sel');
      final name = at('.l', 60, 400);
      final other = at('.i', 400, 290);
      for (final (n, c) in [('60', 'C'), ('64', 'E'), ('67', 'G')]) {
        click(msg(n));
        expect(value(name), c, reason: n);
      }
      click(msg('61'));
      expect((value(name), value(other)), ('G', '61'));
      type(at('.i', 500, 160), 72);
      expect(value(other), '72', reason: 'the typed note passes on');
      type(at('.i', 500, 160), 60);
      expect((value(name), value(other)), ('C', '72'));
      gateway.sendFloat(inst, at('.sel', 60, 230), 0, 64.5);
      expect(value(name), 'C', reason: '64.5 is not 64');
      expect(value(other), '64', reason: 'it passed on (the box truncates)');
      final toggle = at('.t', 60, 680);
      click(msg('start'));
      expect(value(toggle), 'on');
      click(msg('stop'));
      expect(value(toggle), 'off');
      click(msg('pause'));
      expect((value(toggle), value(at('.l', 280, 620))), ('off', 'pause'));
    });

    test('gate and switch: closed at first, chosen from 1, 0 closes', () {
      open('gate-switch');
      final data = at('.i', 500, 160);
      final outs = [
        for (final x in [60.0, 170.0, 280.0]) at('.i', x, 290),
      ];
      List<String> shown() => [for (final o in outs) value(o)];
      type(data, 5);
      expect(shown(), ['0', '0', '0'], reason: 'starts closed');
      click(msg('2'));
      expect(shown(), ['0', '0', '0'], reason: 'choosing sends nothing');
      type(data, 6);
      expect(shown(), ['0', '6', '0']);
      click(msg('3'));
      type(data, 7);
      expect(shown(), ['0', '6', '7']);
      click(msg('1'));
      type(data, 8);
      expect(shown(), ['8', '6', '7']);
      click(msg('0'));
      type(data, 9);
      expect(shown(), ['8', '6', '7'], reason: '0 closes');
      gateway.sendInt(inst, at('.gate', 60, 230), 0, 2);
      gateway.sendInt(inst, at('.gate', 60, 230), 0, 4);
      type(data, 10);
      expect(shown(), ['8', '6', '7'], reason: 'no outlet 4: closed');
      final out = at('.i', 60, 550);
      final choose = at('.i', 60, 420);
      click(msg('10'));
      expect(value(out), '0', reason: 'switch starts closed');
      type(choose, 2);
      click(msg('10'));
      click(msg('30'));
      expect(value(out), '0', reason: 'only inlet 2 passes');
      click(msg('20'));
      expect(value(out), '20');
      type(choose, 3);
      click(msg('30'));
      expect(value(out), '30');
      type(choose, 0);
      click(msg('20'));
      expect(value(out), '30', reason: '0 closes');
    });

    test('router and matrix: a patchbay from the grid, scaled gains', () {
      open('router-matrix');
      final grid = at('.matrixctrl', 60, 160);
      final out0 = at('.i', 60, 340);
      final out1 = at('.i', 170, 340);
      gateway.sendList(inst, grid, 0, '0 0 1');
      expect(value(at('.l', 170, 220)), '0 0 1.', reason: 'a decimal (#522)');
      click(msg('10'));
      expect((value(out0), value(out1)), ('10', '0'));
      gateway.sendList(inst, grid, 0, '0 1 1');
      click(msg('10'));
      expect((value(out0), value(out1)), ('10', '10'), reason: 'both');
      click(msg('20'));
      expect((value(out0), value(out1)), ('10', '10'), reason: 'unconnected');
      gateway.sendList(inst, grid, 0, '1 1 1');
      click(msg('20'));
      expect((value(out0), value(out1)), ('10', '20'), reason: 'shared out1');
      gateway.sendList(inst, grid, 0, '0 1 0');
      click(msg('10'));
      click(msg('20'));
      expect((value(out0), value(out1)), ('10', '20'));
      gateway.sendList(inst, grid, 0, '0 0 0');
      click(msg('clear'));
      click(msg('10'));
      gateway.sendList(inst, grid, 0, '0 1 1');
      click(msg('clear'));
      click(msg('10'));
      expect((value(out0), value(out1)), ('10', '20'), reason: 'cleared');
      final left = at('.f', 60, 610);
      final right = at('.f', 170, 610);
      click(msg('8'));
      expect((number(left), number(right)), (0, 0), reason: 'unconnected');
      type(at('.f', 60, 440), 1);
      click(msg('8'));
      expect((number(left), number(right)), (8, 0), reason: 'gain 1');
      type(at('.f', 200, 440), 0.5);
      click(msg('8'));
      expect((number(left), number(right)), (8, 4), reason: 'gain 0.5');
      type(at('.f', 60, 440), 0);
      type(at('.f', 200, 440), 2);
      click(msg('8'));
      expect((number(left), number(right)), (8, 16), reason: 'left cut');
    });

    test('split: inclusive limits, a three-way velocity split', () {
      open('split');
      final soft = at('.f', 60, 290);
      final medium = at('.f', 200, 350);
      final loud = at('.f', 340, 350);
      List<double> shown() => [number(soft), number(medium), number(loud)];
      click(msg('30'));
      expect(shown(), [30, 0, 0]);
      click(msg('63'));
      expect(shown(), [63, 0, 0], reason: 'the limit is inside');
      click(msg('64'));
      expect(shown(), [63, 64, 0]);
      click(msg('110'));
      expect(shown(), [63, 64, 110]);
      type(at('.i', 500, 160), -5);
      expect(shown(), [63, 64, -5], reason: 'outside both');
      type(at('.i', 500, 160), 100);
      expect(shown(), [63, 100, -5]);
      // Limits from the inlets, the wrong way round.
      final split = at('.split', 60, 230);
      gateway.sendInt(inst, split, 1, 20);
      gateway.sendInt(inst, split, 2, 10);
      click(msg('30'));
      expect(shown(), [63, 100, 30], reason: '30 is out of 10 to 20 now');
      gateway.sendInt(inst, split, 0, 15);
      expect(shown(), [15, 100, 30], reason: 'the lower is the low limit');
    });

    test('spray funnel cycle: by index, tagged, round the outlets', () {
      open('spray-funnel-cycle');
      final index = at('.i', 60, 160);
      final outs = [
        for (final x in [60.0, 150.0, 240.0]) at('.i', x, 320),
      ];
      List<String> shown(List<int> ids) => [for (final o in ids) value(o)];
      type(index, 0);
      expect(shown(outs), ['60', '64', '0']);
      type(index, 1);
      expect(shown(outs), ['60', '60', '64']);
      type(index, 2);
      expect(shown(outs), ['60', '60', '60'], reason: '64 dropped');
      type(index, 0);
      type(index, -1);
      expect(shown(outs), ['60', '64', '60'], reason: 'repeated across');
      final tagged = at('.l', 200, 530);
      final streams = [
        for (final x in [60.0, 150.0, 240.0]) at('.i', x, 590),
      ];
      for (final (k, x, v) in [(0, 60.0, 5), (1, 150.0, 6), (2, 240.0, 7)]) {
        type(at('.i', x, 410), v);
        expect(value(tagged), '$k $v');
      }
      expect(shown(streams), ['5', '6', '7'], reason: 'one cord, 3 streams');
      final dealt = [
        for (final x in [60.0, 150.0, 240.0]) at('.i', x, 780),
      ];
      click(msg('60'));
      click(msg('64'));
      click(msg('67'));
      expect(shown(dealt), ['60', '64', '67']);
      click(msg('64'));
      expect(shown(dealt), ['64', '64', '67'], reason: 'back to outlet 0');
      click(msg('60'));
      click(msg('60'));
      expect(shown(dealt), ['64', '60', '60'], reason: 'whatever the value');
    });

    test('bucket decode: one step behind, echo, roll, clear, one-hot', () {
      open('bucket-decode');
      final input = at('.i', 60, 160);
      final behind = [
        for (final x in [60.0, 150.0, 240.0]) at('.i', x, 280),
      ];
      final echo = [
        for (final x in [340.0, 430.0, 520.0]) at('.i', x, 280),
      ];
      List<String> shown(List<int> ids) => [for (final o in ids) value(o)];
      type(input, 1);
      expect(
        [...shown(behind), ...shown(echo)],
        ['0', '0', '0', '1', '0', '0'],
      );
      type(input, 2);
      expect(
        [...shown(behind), ...shown(echo)],
        ['1', '0', '0', '2', '1', '0'],
      );
      type(input, 3);
      expect(
        [...shown(behind), ...shown(echo)],
        ['2', '1', '0', '3', '2', '1'],
      );
      click(at('.b', 170, 160));
      expect(
        [...shown(behind), ...shown(echo)],
        ['3', '2', '1', '3', '2', '1'],
      );
      click(msg('roll'));
      expect(shown(echo), ['1', '3', '2'], reason: 'rotated, nothing lost');
      click(msg('clear'));
      expect(shown(echo), ['1', '3', '2'], reason: 'clear sends nothing');
      click(at('.b', 170, 160));
      expect(
        [...shown(behind), ...shown(echo)],
        ['0', '0', '0', '0', '0', '0'],
      );
      final select = at('.i', 60, 420);
      final bank = [
        for (final x in [60.0, 110.0, 160.0, 210.0]) at('.t', x, 540),
      ];
      type(select, 2);
      expect(shown(bank), ['off', 'off', 'on', 'off']);
      type(select, 0);
      expect(shown(bank), ['on', 'off', 'off', 'off']);
      type(select, 7);
      expect(shown(bank), ['on', 'off', 'off', 'off'], reason: 'ignored');
      type(select, 3);
      final allOn = at('.t', 200, 420);
      final mute = at('.t', 260, 420);
      gateway.sendInt(inst, allOn, 0, 1);
      expect(shown(bank), ['on', 'on', 'on', 'on']);
      gateway.sendInt(inst, mute, 0, 1);
      expect(shown(bank), ['off', 'off', 'off', 'off']);
      gateway.sendInt(inst, mute, 0, 0);
      gateway.sendInt(inst, allOn, 0, 0);
      expect(shown(bank), ['off', 'off', 'off', 'on'], reason: 'back to 3');
    });
  });

  test('every randomness type has a tutorial (#501)', () {
    for (final type in ['.random', '.drunk', '.urn', '.prob', '.decide']) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  // Randomness is checked by range and distribution, and exactly only where a
  // seed makes it replayable, so none of these can flake.
  group('randomness tutorials (#501) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Every tutorial is mounted while open (#528); so is this copy.
    void open(String slug) {
      inst = gateway.createInstance(mainOutputs: 1);
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
    void click(int id) => gateway.sendBang(inst, id, 0);
    // Typing a number into a box sends it on.
    void type(int id, int v) => gateway.sendInt(inst, id, 0, v);
    String value(int id) => gateway.guiValue(inst, id);
    int integer(int id) => int.parse(value(id));

    // Clicks [button] [n] times and reads the box [out] after each click.
    List<int> clicks(int button, int out, int n) {
      final read = <int>[];
      for (var i = 0; i < n; i++) {
        click(button);
        read.add(integer(out));
      }
      return read;
    }

    // How often each value turned up in [xs].
    Map<int, int> tally(Iterable<int> xs) {
      final counts = <int, int>{};
      for (final x in xs) {
        counts[x] = (counts[x] ?? 0) + 1;
      }
      return counts;
    }

    // The loudest master peak over [blocks] blocks.
    double loudness(int blocks) {
      var peak = 0.0;
      for (var i = 0; i < blocks; i++) {
        render(1);
        final p = Channel.master.peakLinearPost();
        if (p > peak) peak = p;
      }
      return peak;
    }

    test('random: 0 to N-1 evenly, a die, the range inlet, no seed', () {
      open('random');
      final out = at('.i', 60, 290);
      final button = at('.b', 60, 160);
      final six = clicks(button, out, 1200);
      // 200 of each expected; 120 or 280 is more than six deviations out.
      expect(tally(six).keys.toSet(), {0, 1, 2, 3, 4, 5});
      for (final c in tally(six).values) {
        expect(c, inInclusiveRange(120, 280));
      }
      expect(integer(at('.i', 170, 340)), integer(out) + 1, reason: 'a die');
      var repeats = 0;
      for (var i = 1; i < six.length; i++) {
        if (six[i] == six[i - 1]) repeats++;
      }
      expect(repeats, greaterThan(100), reason: 'twice in a row happens');
      final before = value(out);
      click(msg('2'));
      expect(value(out), before, reason: 'setting the range sends nothing');
      expect(tally(clicks(button, out, 400)).keys.toSet(), {0, 1});
      click(msg('100'));
      final hundred = clicks(button, out, 2000);
      expect(hundred.reduce(math.min), greaterThanOrEqualTo(0));
      expect(hundred.reduce(math.max), lessThanOrEqualTo(99));
      expect(tally(hundred).length, greaterThan(90), reason: '0 to 99');
      final random = at('.random', 60, 230);
      gateway.sendFloat(inst, random, 1, 2.9);
      expect(tally(clicks(button, out, 200)).keys.toSet(), {0, 1});
      for (final r in [1, 0]) {
        gateway.sendInt(inst, random, 1, r);
        expect(tally(clicks(button, out, 50)).keys, [0], reason: 'range $r');
      }
      // Note 4: no seed on this engine (yse-soundengine#1236). When the
      // engine gains one this fails, and the notes need rewriting.
      final params = gateway
          .objectTypes()
          .singleWhere((d) => d.type == '.random')
          .params;
      expect([for (final p in params) p.name], ['range']);
    });

    test('drunk: small steps, clipped edges, step size, the seed', () {
      open('drunk');
      final pos = at('.i', 60, 350);
      final button = at('.b', 170, 160);
      List<int> walk(int n) => clicks(button, pos, n);
      // Checks every step of [steps], from [start], against [ok].
      void steps(int start, List<int> steps, bool Function(int, int) ok) {
        var prev = start;
        for (final p in steps) {
          expect(p, inInclusiveRange(0, 24));
          expect(ok(prev, p), isTrue, reason: '$prev to $p');
          prev = p;
        }
      }

      expect(value(pos), '0', reason: 'nothing sent yet');
      final first = walk(400);
      steps(0, first, (a, b) => (b - a).abs() <= 2);
      expect(tally(first).length, greaterThan(10), reason: 'it wanders');
      click(msg('12'));
      expect(integer(pos), 12, reason: 'moved there and sent');
      click(msg('8'));
      final leaps = walk(400);
      steps(12, leaps, (a, b) => (b - a).abs() <= 7);
      var big = 0;
      for (var i = 1; i < leaps.length; i++) {
        if ((leaps[i] - leaps[i - 1]).abs() > 2) big++;
      }
      expect(big, greaterThan(50), reason: 'leaps of up to 7');
      click(msg('-2'));
      click(msg('12'));
      // Never a step of 0, except where an edge clips the step away.
      steps(
        12,
        walk(400),
        (a, b) => (b - a).abs() == 1 || a == b && {0, 24}.contains(a),
      );
      click(msg('3'));
      final seed = at('.i', 390, 160);
      type(seed, 5);
      click(msg('12'));
      final a = walk(30);
      type(seed, 5);
      click(msg('12'));
      expect(walk(30), a, reason: 'seed 5 and 12 again: the same steps');
      type(seed, 6);
      click(msg('12'));
      expect(walk(30), isNot(a), reason: 'another seed, another walk');
    });

    test('drunk: seed 7 replays the same walk every time it opens', () {
      List<int> firstSteps() {
        open('drunk');
        final steps = clicks(at('.b', 170, 160), at('.i', 60, 350), 40);
        gateway.disposeInstance(inst);
        return steps;
      }

      final a = firstSteps();
      expect(firstSteps(), a);
      open('drunk'); // for the tearDown
    });

    test('drunk: the toggle plays the walk on master', () {
      open('drunk');
      expect(loudness(100), 0, reason: 'silent until the toggle');
      final toggle = at('.t', 60, 160);
      gateway.sendInt(inst, toggle, 0, 1);
      expect(loudness(200), greaterThan(0.05), reason: 'a sine on master');
      gateway.sendInt(inst, toggle, 0, 0);
      loudness(20);
      expect(loudness(100), 0, reason: 'off again');
    });

    test('urn: every number once, the empty bang, clear, auto-refill', () {
      open('urn');
      final dealt = at('.i', 60, 350);
      final empties = at('.i', 200, 400);
      final button = at('.b', 60, 160);
      final clear = at('.m', 170, 160);
      List<int> deal(int n) => clicks(button, dealt, n);
      const all = {0, 1, 2, 3, 4, 5};
      final round = deal(6);
      expect(round.toSet(), all, reason: 'each once');
      expect(value(empties), '0');
      click(button);
      expect(integer(dealt), round.last, reason: 'nothing new');
      expect(integer(empties), 1, reason: 'the right outlet');
      click(button);
      expect(integer(empties), 2, reason: 'every bang says so');
      click(clear);
      final orders = <String>{};
      for (var r = 0; r < 10; r++) {
        final again = deal(6);
        expect(again.toSet(), all, reason: 'all back');
        orders.add(again.join());
        click(clear);
      }
      expect(orders.length, greaterThan(1), reason: 'a new order');
      click(msg('3'));
      expect(deal(3).toSet(), {0, 1, 2}, reason: 'limit 3, refilled');
      click(msg('6'));
      // The toggle opens the gate: the empty bang reaches clear.
      final toggle = at('.t', 340, 290);
      gateway.sendInt(inst, toggle, 0, 1);
      final forever = deal(70);
      final counted = integer(empties);
      // Every seventh bang meets the empty urn, which refills it.
      for (var r = 0; r < 10; r++) {
        final chunk = forever.sublist(r * 7, r * 7 + 6);
        expect(chunk.toSet(), all, reason: 'round $r');
      }
      expect(counted, greaterThanOrEqualTo(10 + 2), reason: 'counted');
      gateway.sendInt(inst, toggle, 0, 0);
      click(clear);
      // A seed reshuffles the rest; what was dealt stays dealt.
      final two = deal(2);
      type(at('.i', 280, 160), 9);
      expect({...two, ...deal(4)}, all, reason: 'no repeats');
    });

    test('urn: seed 3 deals the same first round every time it opens', () {
      List<int> firstRound() {
        open('urn');
        final round = clicks(at('.b', 60, 160), at('.i', 60, 350), 6);
        gateway.disposeInstance(inst);
        return round;
      }

      final a = firstRound();
      expect(firstRound(), a);
      open('urn');
    });

    test('prob: loaded transitions, weights, dump, add, dead end', () {
      open('prob');
      final state = at('.i', 60, 410);
      final stuck = at('.i', 170, 460);
      final prob = at('.prob', 60, 350);
      final button = at('.b', 60, 160);
      expect(value(state), '0');
      final pairs = <(int, int)>[];
      var from = 0;
      for (final to in clicks(button, state, 3000)) {
        pairs.add((from, to));
        from = to;
      }
      expect(pairs.toSet(), {(0, 1), (0, 2), (1, 0), (1, 2), (2, 0)});
      double share((int, int) p) =>
          pairs.where((q) => q == p).length /
          pairs.where((q) => q.$1 == p.$1).length;
      expect(share((0, 1)), closeTo(0.75, 0.06), reason: '3 out of 4');
      expect(share((1, 0)), closeTo(0.5, 0.07), reason: 'alike');
      expect(share((2, 0)), 1, reason: 'always back to 0');
      final dump = at('.l', 300, 410);
      click(msg('dump'));
      expect(value(dump), '2 0 1', reason: 'the last one');
      // 0 2 4: the right boxes first, the left one sends.
      type(at('.i', 280, 560), 4);
      type(at('.i', 170, 560), 2);
      type(at('.i', 60, 560), 0);
      expect(value(at('.l', 60, 680)), '0 2 4');
      final next = <int>[];
      for (var i = 0; i < 1400; i++) {
        type(prob, 0);
        click(button);
        next.add(integer(state));
      }
      expect(
        next.where((n) => n == 2).length / next.length,
        closeTo(4 / 7, 0.06),
        reason: 'from 0 now 3 to 4 for state 2',
      );
      // A weight of 0 switches it off.
      gateway.sendList(inst, prob, 0, '0 2 0');
      for (var i = 0; i < 100; i++) {
        type(prob, 0);
        click(button);
        expect(integer(state), 1, reason: 'only 1 is left from 0');
      }
      // Dead end: 3 sets the state without sending; the bang reports it.
      final shown = value(state);
      click(msg('3'));
      expect(value(state), shown, reason: 'nothing sent');
      expect(value(stuck), '0');
      click(button);
      expect((value(state), integer(stuck)), (shown, 1), reason: 'stuck');
      click(button);
      expect(integer(state), 1, reason: 'back at 0, which goes to 1 now');
      // The seed: the same seed and start, the same chain.
      gateway.sendList(inst, prob, 0, '0 2 1');
      final seed = at('.i', 500, 160);
      List<int> chain() {
        type(prob, 0);
        return clicks(button, state, 30);
      }

      type(seed, 11);
      final a = chain();
      type(seed, 11);
      expect(chain(), a);
      click(msg('clear'));
      click(button);
      expect(integer(stuck), 2, reason: 'cleared: no way out of anything');
    });

    test('prob: seed 5 replays the same chain every time it opens', () {
      List<int> chain() {
        open('prob');
        final c = clicks(at('.b', 60, 160), at('.i', 60, 410), 40);
        gateway.disposeInstance(inst);
        return c;
      }

      final a = chain();
      expect(chain(), a);
      open('prob');
    });

    test('decide: 0 or 1, either way through the gate, the seed', () {
      open('decide');
      final flip = at('.i', 340, 350);
      final left = at('.i', 60, 630);
      final right = at('.i', 200, 630);
      final button = at('.b', 170, 160);
      final flips = clicks(button, flip, 1000);
      expect(flips.toSet(), {0, 1});
      final ones = flips.where((f) => f == 1).length;
      expect(ones, inInclusiveRange(400, 600), reason: 'a fair coin');
      expect(
        (integer(left), integer(right)),
        (1000 - ones, ones),
        reason: '0 goes left, 1 right, every bang counted once',
      );
      var longest = 1;
      var run = 1;
      for (var i = 1; i < flips.length; i++) {
        run = flips[i] == flips[i - 1] ? run + 1 : 1;
        longest = math.max(longest, run);
      }
      expect(longest, greaterThanOrEqualTo(4), reason: 'runs happen');
      final seed = at('.i', 280, 160);
      type(seed, 7);
      final a = clicks(button, flip, 40);
      type(seed, 7);
      expect(clicks(button, flip, 40), a, reason: 'seed 7 replays');
      // An int flips too, its value ignored.
      final decide = at('.decide', 200, 350);
      final counted = integer(left) + integer(right);
      gateway.sendInt(inst, decide, 0, 42);
      expect(value(flip), anyOf('0', '1'));
      expect(integer(left) + integer(right), counted, reason: 'no bang');
    });

    test('decide: seed 7 flips the same way every time it opens', () {
      List<int> flips() {
        open('decide');
        final f = clicks(at('.b', 170, 160), at('.i', 340, 350), 40);
        gateway.disposeInstance(inst);
        return f;
      }

      final a = flips();
      expect(flips(), a);
      open('decide');
    });

    test('decide: the toggle flips five times a second', () {
      open('decide');
      final toggle = at('.t', 60, 160);
      // metro keeps wall-clock time: bound the count by the time it ran.
      final clock = Stopwatch()..start();
      gateway.sendInt(inst, toggle, 0, 1);
      while (clock.elapsedMilliseconds < 1100) {
        render(4);
        sleep(const Duration(milliseconds: 5));
      }
      gateway.sendInt(inst, toggle, 0, 0);
      final ran = clock.elapsedMilliseconds;
      final n = integer(at('.i', 60, 630)) + integer(at('.i', 200, 630));
      expect(n, greaterThanOrEqualTo(3), reason: 'a tick at once, then more');
      expect(n, lessThanOrEqualTo(ran ~/ 200 + 1), reason: 'every 200 ms');
    });
  });

  test('every list type has a tutorial (#502)', () {
    for (final type in [
      '.pack', '.pak', '.unpack', '.iter', '.join', '.unjoin', '.append', //
      '.prepend', '.zl', '.listfunnel', '.substitute',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.pack'), index.tutorialFor('.pak'));
    expect(index.tutorialFor('.join'), index.tutorialFor('.unjoin'));
    expect(index.tutorialFor('.append'), index.tutorialFor('.prepend'));
    expect(index.tutorialFor('.listfunnel'), index.tutorialFor('.substitute'));
  });

  group('list tutorials (#502) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Every tutorial is mounted while open (#528); so is this copy.
    void open(String slug) {
      inst = gateway.createInstance(mainOutputs: 1);
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
    void click(int id) => gateway.sendBang(inst, id, 0);
    // Typing a number into a box sends it on.
    void type(int id, num v) => v is int
        ? gateway.sendInt(inst, id, 0, v)
        : gateway.sendFloat(inst, id, 0, v.toDouble());
    String value(int id) => gateway.guiValue(inst, id);
    double number(int id) => double.parse(value(id));

    test('pack and pak: typed elements, cold inlets, pak sends from all', () {
      open('pack-pak');
      final out = at('.l', 60, 290);
      type(at('.i', 170, 160), 3);
      click(msg('bar'));
      expect(value(out), '', reason: 'the right inlets only store');
      type(at('.f', 60, 160), 1.7);
      expect(value(out), '1 3. bar', reason: 'int cut, float made, word kept');
      type(at('.f', 60, 160), 4);
      expect(value(out), '4 3. bar');
      click(at('.b', 390, 160));
      expect(value(out), '4 3. bar', reason: 'a bang sends as it stands');
      // A word at an int or float element is refused.
      gateway.sendMessage(inst, at('.pack', 60, 230), 1, 'word');
      click(at('.b', 390, 160));
      expect(value(out), '4 3. bar');
      final pk = at('.i', 60, 700);
      final pa = at('.i', 240, 700);
      type(at('.i', 240, 420), 5);
      expect((value(at('.l', 60, 540)), value(pk)), ('', '0'));
      expect((value(at('.l', 240, 540)), value(pa)), ('0 5', '1'));
      type(at('.i', 60, 420), 2);
      expect((value(at('.l', 60, 540)), value(pk)), ('2 5', '1'));
      expect((value(at('.l', 240, 540)), value(pa)), ('2 5', '2'));
      // pak takes a bang at any inlet.
      gateway.sendBang(inst, at('.pak', 240, 480), 1);
      expect(value(pa), '3');
    });

    test('unpack: right to left, typed outlets, only those reached', () {
      open('unpack');
      final o0 = at('.i', 60, 340);
      final o1 = at('.f', 170, 340);
      final o2 = at('.l', 280, 340);
      click(msg('foo'));
      expect((value(o0), number(o1), value(o2)), ('1', 2.0, 'foo'));
      click(msg('6'));
      expect((value(o0), number(o1), value(o2)), ('5', 6.0, 'foo'));
      // Items past the last outlet are dropped; a word at a number outlet
      // is refused and that outlet sends what it had.
      gateway.sendList(inst, at('.unpack', 60, 280), 0, 'bar 7 baz qux');
      expect((value(o0), number(o1), value(o2)), ('5', 7.0, 'baz'));
      click(at('.b', 340, 160));
      expect((value(o0), number(o1), value(o2)), ('5', 7.0, 'baz'));
      click(msg('3'));
      expect(number(at('.f', 60, 690)), 7, reason: '10 - 3, right first');
    });

    test('iter: one item at a time, the bang repeats, a number is one', () {
      open('iter');
      final last = at('.i', 60, 340);
      final count = at('.i', 180, 440);
      final up = at('.f', 300, 390);
      click(at('.b', 280, 160));
      expect(value(count), '0', reason: 'nothing to repeat yet');
      click(msg('67'));
      expect((value(last), value(count), number(up)), ('67', '3', 79.0));
      click(at('.b', 280, 160));
      expect(value(count), '6');
      click(msg('5'));
      expect((value(last), value(count), number(up)), ('5', '7', 17.0));
      gateway.sendList(inst, at('.+', 300, 340), 0, '60 64 67');
      expect(number(up), 17, reason: '+ ignores a list (note 2)');
    });

    test('join and unjoin: whole pieces, groups, the rest', () {
      open('join-unjoin');
      final join = at('.l', 60, 340);
      final pack = at('.l', 200, 340);
      click(msg('4'));
      expect((value(join), value(pack)), ('', ''), reason: 'right is cold');
      click(msg('2'));
      expect((value(join), value(pack)), ('1 2 3 4', '1 2'));
      click(at('.b', 320, 160));
      expect((value(join), value(pack)), ('1 2 3 4', '1 2'));
      // join 3 -1, from the note: every inlet sends.
      final j3 = gateway.createObject(inst, '.join', args: '3 -1');
      final j3l = gateway.createObject(inst, '.l');
      gateway.connect(
        inst,
        fromHandleId: j3,
        outlet: 0,
        toHandleId: j3l,
        inlet: 0,
      );
      gateway.sendInt(inst, j3, 2, 5);
      expect(value(j3l), '0 0 5');
      final g0 = at('.l', 60, 630);
      final g1 = at('.l', 170, 630);
      final rest = at('.l', 280, 690);
      click(msg('5'));
      expect((value(g0), value(g1), value(rest)), ('1 2', '3 4', 'rest 5'));
      click(msg('8'));
      expect((value(g0), value(g1), value(rest)), ('6 7', '3 4', 'rest 8'));
    });

    test('append and prepend: before, after, replaced, set', () {
      open('append-prepend');
      final pre = at('.l', 60, 290);
      final app = at('.l', 240, 350);
      type(at('.i', 60, 160), 60);
      expect((value(pre), value(app)), ('note 60', 'note 60 100'));
      click(msg('ctl'));
      expect(value(pre), 'note 60', reason: 'the right inlet sends nothing');
      type(at('.i', 60, 160), 61);
      expect((value(pre), value(app)), ('ctl 61', 'ctl 61 100'));
      click(msg('1'));
      type(at('.i', 60, 160), 62);
      expect(value(app), 'ctl 62 1');
      final packed = at('.l', 60, 640);
      final count = at('.i', 200, 740);
      type(at('.i', 60, 460), 5);
      expect((value(packed), value(count)), ('', '0'), reason: 'set: kept');
      click(at('.b', 200, 460));
      expect((value(packed), value(count)), ('5 0', '1'));
      // The title note: set at the left inlet is put in front like any word.
      gateway.sendMessage(inst, at('.prepend', 60, 230), 0, 'set ctl');
      expect(value(pre), 'ctl set ctl');
      // Note 4: a message box takes a list that arrives as its whole text.
      final m = gateway.createObject(inst, '.m', args: 'x');
      gateway.sendMessage(inst, m, 0, 'set 9');
      expect(value(m), 'set 9');
    });

    test('zl: len, rev, nth, rot, slice, sort, group, stream', () {
      open('zl');
      final left = at('.l', 60, 380);
      final leftN = at('.i', 200, 380);
      final right = at('.l', 330, 380);
      final btn = at('.b', 400, 160);
      click(msg('1'));
      expect(value(leftN), '4', reason: 'len of 5 3 8 1');
      click(msg('rev'));
      expect(value(left), '', reason: 'a mode switch sends nothing');
      click(btn);
      expect(value(left), '1 8 3 5');
      type(at('.i', 480, 260), 2);
      click(msg('nth'));
      click(btn);
      expect((value(leftN), value(right)), ('3', '5 8 1'));
      click(msg('rot'));
      click(btn);
      expect(value(left), '8 1 5 3');
      click(msg('slice'));
      click(btn);
      expect((value(left), value(right)), ('5 3', '8 1'));
      click(msg('sort'));
      click(btn);
      expect(value(left), '1 3 5 8');
      type(at('.i', 480, 260), -1);
      click(btn);
      expect((value(left), value(right)), ('8 5 3 1', '3 1 2 4'));
      click(msg('len'));
      click(btn);
      expect(value(leftN), '4');
      final input = at('.i', 60, 500);
      final group = at('.l', 60, 620);
      final stream = at('.l', 240, 620);
      final missing = at('.i', 400, 620);
      type(input, 1);
      type(input, 2);
      expect((value(group), value(stream), value(missing)), ('', '', '1'));
      type(input, 3);
      expect(
        (value(group), value(stream), value(missing)),
        ('1 2 3', '1 2 3', '0'),
      );
      type(input, 4);
      expect((value(group), value(stream)), ('1 2 3', '2 3 4'));
      type(input, 5);
      type(input, 6);
      expect((value(group), value(stream)), ('4 5 6', '4 5 6'));
    });

    test('listfunnel and substitute: index pairs, spray, replace', () {
      open('listfunnel-substitute');
      click(msg('67'));
      expect(value(at('.l', 60, 330)), '2 67', reason: 'the last pair');
      expect(
        [
          for (final x in [200.0, 300.0, 400.0]) value(at('.i', x, 390)),
        ],
        ['60', '64', '67'],
      );
      final lf = gateway.createObject(inst, '.listfunnel', args: '1');
      final lfl = gateway.createObject(inst, '.l');
      gateway.connect(
        inst,
        fromHandleId: lf,
        outlet: 0,
        toHandleId: lfl,
        inlet: 0,
      );
      gateway.sendList(inst, lf, 0, '60 64');
      expect(value(lfl), '2 64', reason: 'listfunnel 1 starts at 1');
      final left = at('.l', 60, 680);
      final right = at('.l', 200, 680);
      final first = at('.l', 330, 680);
      click(msg('60'));
      expect(
        (value(left), value(right), value(first)),
        ('72 64 72', '', '72 64 60'),
      );
      click(msg('64'));
      expect((value(left), value(right)), ('72 64 72', '62 64'));
      type(at('.i', 330, 500), 64);
      click(msg('60'));
      expect(value(left), '60 72 60', reason: 'now 64 is the match');
      gateway.sendInt(inst, at('.substitute', 60, 620), 2, 0);
      click(msg('60'));
      expect(value(left), '60 0 60', reason: 'the right inlet: replacement');
    });
  });

  test('every string type has a tutorial (#503)', () {
    for (final type in [
      '.sprintf', '.regexp', '.tosymbol', '.fromsymbol', '.atoi', '.itoa', //
      '.combine', '.spell', '.tolower', '.toupper',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.tosymbol'), index.tutorialFor('.fromsymbol'));
    expect(index.tutorialFor('.atoi'), index.tutorialFor('.itoa'));
    expect(index.tutorialFor('.tolower'), index.tutorialFor('.toupper'));
  });

  group('string tutorials (#503) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Every tutorial is mounted while open (#528); so is this copy.
    void open(String slug) {
      inst = gateway.createInstance(mainOutputs: 1);
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
    void click(int id) => gateway.sendBang(inst, id, 0);
    // Typing a number into a box sends it on.
    void type(int id, num v) => v is int
        ? gateway.sendInt(inst, id, 0, v)
        : gateway.sendFloat(inst, id, 0, v.toDouble());
    // Typing into a text field and pressing Enter stores and sends the text.
    void enter(int field, String text) =>
        gateway.sendList(inst, field, 0, text);
    String value(int id) => gateway.guiValue(inst, id);
    // A fresh object wired to a fresh list box, to check what a note says
    // about a case the patch does not wire up.
    (int, int) probe(String t, String args, [int outlet = 0]) {
      final o = gateway.createObject(inst, t, args: args);
      final l = gateway.createObject(inst, '.l');
      gateway.connect(
        inst,
        fromHandleId: o,
        outlet: outlet,
        toHandleId: l,
        inlet: 0,
      );
      return (o, l);
    }

    test('sprintf: a unit, two inlets, width, precision, as text', () {
      open('sprintf');
      final freq = at('.l', 60, 320);
      type(at('.i', 60, 200), 440);
      expect(value(freq), '440 Hz');
      type(at('.sprintf', 60, 260), 440.7);
      expect(value(freq), '440 Hz', reason: 'a float is cut to an int');
      final note = at('.l', 300, 320);
      click(msg('90'));
      expect(value(note), '', reason: 'the right inlet only stores');
      click(msg('60'));
      expect(value(note), 'note 60 90');
      type(at('.i', 60, 420), 7);
      expect(value(at('.l', 60, 540)), '007.wav');
      type(at('.f', 300, 420), 0.5);
      expect(value(at('.l', 300, 540)), 'gain 0.50');
      // Note 2: a %d never set writes 0.
      final (fresh, freshOut) = probe('.sprintf', 'note %d %d');
      gateway.sendInt(inst, fresh, 0, 60);
      expect(value(freshOut), 'note 60 0');
      // Note 4: a list fills from the left; a bang formats again.
      final sp = at('.sprintf', 300, 260);
      gateway.sendList(inst, sp, 0, '61 90');
      expect(value(note), 'note 61 90');
      gateway.sendInt(inst, sp, 1, 80);
      click(sp);
      expect(value(note), 'note 61 80');
      // The title note: %x and %g are copied through; symout is dropped.
      final (other, otherOut) = probe('.sprintf', '%x|%g');
      gateway.sendList(inst, other, 0, '255 1.5');
      expect(value(otherOut), '%x|%g');
      final (sym, symOut) = probe('.sprintf', 'symout freq %d');
      gateway.sendInt(inst, sym, 0, 3);
      expect(value(symOut), 'freq 3');
    });

    test('regexp: matches, groups, substitution, no match', () {
      open('regexp');
      final sub = at('.l', 60, 420);
      final groups = at('.l', 170, 420);
      final match = at('.l', 280, 420);
      final none = at('.l', 390, 420);
      final count = at('.i', 500, 540);
      click(at('.b', 60, 220));
      expect(
        (value(sub), value(groups), value(match), value(none), value(count)),
        ('c#4 e#5 g', 'e 5', 'e5', '', '2'),
      );
      click(msg('hat'));
      expect(
        (value(sub), value(match), value(none), value(count)),
        ('c#4 e#5 g', 'e5', 'hat', '2'),
        reason: 'no match: only the right outlet',
      );
      enter(at('.textedit', 60, 270), 'a1 b2 x');
      expect((value(sub), value(count)), ('a#1 b#2 x', '4'));
      // Note 3: %0 inserts the whole match.
      final (whole, wholeOut) = probe('.regexp', '[a-g][0-9] <%0>');
      gateway.sendList(inst, whole, 0, 'c4 d');
      expect(value(wholeOut), '<c4> d');
      // The title note: re is a message to match, not a command; \s is a
      // space; \b is not supported, so everything leaves unmatched.
      final (re, reOut) = probe('.regexp', 'a', 3);
      gateway.sendMessage(inst, re, 0, 're b');
      expect(value(reOut), 're b');
      final (space, spaceOut) = probe('.regexp', r'c\s4', 2);
      gateway.sendList(inst, space, 0, 'c 4');
      expect(value(spaceOut), 'c 4');
      final (wb, wbOut) = probe('.regexp', r'\bc', 3);
      gateway.sendList(inst, wb, 0, 'c');
      expect(value(wbOut), 'c');
    });

    test('tosymbol and fromsymbol: join, split, separator, parse', () {
      open('tosymbol-fromsymbol');
      final sym = at('.l', 60, 390);
      final back = at('.l', 220, 450);
      click(at('.b', 60, 220));
      expect((value(sym), value(back)), ('osc/3/amp', 'osc 3 amp'));
      click(msg('-'));
      expect(value(sym), 'osc/3/amp', reason: 'the separator sends nothing');
      click(at('.b', 60, 220));
      expect((value(sym), value(back)), ('osc-3-amp', 'osc-3-amp'));
      final field = at('.textedit', 60, 540);
      final list = at('.l', 60, 660);
      final item = at('.i', 220, 720);
      click(field);
      expect((value(list), value(item)), ('60 64 67', '67'));
      enter(field, '72');
      expect((value(list), value(item)), ('60 64 67', '72'));
      // The title note: tosymbol's symbol leaves as a list of one item.
      final (one, oneOut) = probe('.tosymbol', '/');
      gateway.sendList(inst, one, 0, 'a b');
      expect(value(oneOut), 'a/b');
    });

    test('atoi and itoa: codes, back to text, append, bang, UTF-8', () {
      open('atoi-itoa');
      final codes = at('.l', 60, 320);
      final text = at('.l', 220, 440);
      final field = at('.textedit', 60, 200);
      click(field);
      expect((value(codes), value(text)), ('104 105', 'hi'));
      enter(field, 'a b');
      expect((value(codes), value(text)), ('97 32 98', 'a b'));
      enter(field, 'hi');
      type(at('.i', 340, 260), 33);
      expect(value(text), 'hi', reason: 'the middle inlet sends nothing');
      click(at('.b', 460, 260));
      expect(value(text), 'hi!');
      // Note 3: one code at a time builds a word.
      enter(field, 'x');
      gateway.sendInt(inst, at('.itoa', 220, 380), 2, 72);
      for (final c in [97, 32, 72]) {
        type(at('.i', 340, 260), c);
      }
      click(at('.b', 460, 260));
      expect(value(text), 'Ha H');
      // The title note: UTF-8, and itoa's text is always a list.
      enter(field, 'é');
      expect((value(codes), value(text)), ('233', 'é'));
      final (n, nOut) = probe('.itoa', '');
      gateway.sendList(inst, n, 0, '52 50');
      expect(value(nOut), '42');
    });

    test('combine: a file name, cold and hot inlets, triggers -1', () {
      open('combine');
      final name = at('.l', 60, 330);
      click(at('.b', 170, 200));
      expect(value(name), 'kick-1.wav');
      type(at('.i', 240, 200), 2);
      expect(value(name), 'kick-1.wav', reason: 'the third inlet only stores');
      click(msg('hat'));
      expect(value(name), 'hat-2.wav');
      type(at('.i', 200, 420), 4);
      expect(value(at('.l', 60, 540)), 'bus/4');
      // The title note: triggers 2 makes only the third inlet send.
      final (t2, t2Out) = probe('.combine', 'triggers 2 a b c');
      gateway.sendMessage(inst, t2, 0, 'x');
      expect(value(t2Out), '');
      gateway.sendMessage(inst, t2, 2, 'z');
      expect(value(t2Out), 'xbz');
    });

    test('spell: codes, a space, iter, padding after the text', () {
      open('spell');
      final codes = at('.l', 60, 320);
      final field = at('.textedit', 60, 200);
      click(field);
      expect((value(codes), value(at('.i', 220, 380))), ('104 105', '105'));
      enter(field, 'a b');
      expect(value(codes), '97 32 98');
      type(at('.i', 60, 460), 7);
      expect(value(at('.l', 60, 580)), '55 48 48');
      // The title note: a number digit by digit; no bang; 32 by default.
      final spell = at('.spell', 60, 260);
      gateway.sendInt(inst, spell, 0, 123);
      expect(value(codes), '49 50 51');
      click(spell);
      expect(value(codes), '49 50 51', reason: 'spell takes no bang');
      final (pad, padOut) = probe('.spell', '3');
      gateway.sendInt(inst, pad, 0, 7);
      expect(value(padOut), '55 32 32');
    });

    test('tolower and toupper: case, the rest kept, route ignores case', () {
      open('tolower-toupper');
      final upper = at('.l', 60, 300);
      final lower = at('.l', 200, 300);
      final field = at('.textedit', 60, 180);
      click(field);
      expect((value(upper), value(lower)), ('HELLO', 'hello'));
      enter(field, 'Grüße 42');
      expect((value(upper), value(lower)), ('GRüßE 42', 'grüße 42'));
      final plays = at('.i', 60, 650);
      final stops = at('.i', 170, 650);
      final rest = at('.l', 280, 590);
      click(msg('PLAY'));
      click(msg('Stop'));
      expect((value(plays), value(stops)), ('1', '1'));
      final typed = at('.textedit', 280, 400);
      enter(typed, 'pLaY');
      expect(value(plays), '2');
      enter(typed, 'Pause');
      expect((value(plays), value(stops), value(rest)), ('2', '1', 'pause'));
      // The title note: a number passes through as a number.
      final (up, _) = probe('.toupper', '');
      final n = gateway.createObject(inst, '.i');
      gateway.connect(
        inst,
        fromHandleId: up,
        outlet: 0,
        toHandleId: n,
        inlet: 0,
      );
      gateway.sendInt(inst, up, 0, 5);
      expect(value(n), '5');
    });
  });

  test('every I/O, messaging and value type has a tutorial (#504)', () {
    for (final type in ['.s', '.r', '.forward', '.value', '.print']) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.s'), index.tutorialFor('.r'));
  });

  group('I/O, messaging and value tutorials (#504) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;
    final others = <int>[];

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    void mount(int id) {
      gateway.mountAsSource(id);
      for (var i = 0; i < 5000 && !gateway.isSourceReady(id); i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(id), isTrue, reason: 'mounted');
      render(20);
    }

    // Every tutorial is mounted while open (#528); so is this copy. [name]
    // opens it the way a project copy opens: named, on the engine bus.
    void open(String slug, {String name = ''}) {
      inst = gateway.createInstance(name: name);
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
      mount(inst);
    }

    tearDown(() {
      gateway.disposeInstance(inst);
      for (final o in others) {
        gateway.disposeInstance(o);
      }
      others.clear();
      render(20);
    });

    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    int msg(String text) => graph.objects
        .singleWhere((o) => o.type == '.m' && o.args == text)
        .handleId;
    // A send reaches its receive on the next rendered block.
    String value(int id) {
      render(3);
      return gateway.guiValue(inst, id);
    }

    void click(int id) => gateway.sendBang(inst, id, 0);
    void type(int id, num v) => v is int
        ? gateway.sendInt(inst, id, 0, v)
        : gateway.sendFloat(inst, id, 0, v.toDouble());
    // A fresh object in [i] wired to a fresh list box.
    (int, int) probe(int i, String t, String args, [String box = '.l']) {
      final o = gateway.createObject(i, t, args: args);
      final l = gateway.createObject(i, box);
      gateway.connect(i, fromHandleId: o, outlet: 0, toHandleId: l, inlet: 0);
      return (o, l);
    }

    // A second, separate patch, mounted.
    int another({String name = ''}) {
      final o = gateway.createInstance(name: name);
      others.add(o);
      mount(o);
      return o;
    }

    test('s and r: a number, a bang, a list, local names, the bus', () async {
      open('s-r', name: 'tutorials.s_r');
      final pitch = at('.i', 330, 220);
      final hits = at('.i', 330, 420);
      type(at('.i', 60, 160), 64);
      expect(value(pitch), '64');
      click(msg('72'));
      expect(value(pitch), '72');
      click(at('.b', 60, 300));
      final first = value(hits);
      click(at('.b', 60, 300));
      expect(
        int.parse(value(hits)),
        int.parse(first) + 1,
        reason: 'the counter counts the clicks',
      );
      // The title note: a list goes through too.
      final (_, list) = probe(inst, '.r', 'notes');
      final sendNotes = gateway.createObject(inst, '.s', args: 'notes');
      gateway.sendList(inst, sendNotes, 0, '60 100');
      expect(value(list), '60 100');
      // A name belongs to its patch: an r in another patch hears nothing.
      final other = another();
      final (_, otherPitch) = probe(other, '.r', 'pitch', '.i');
      type(at('.i', 60, 160), 65);
      expect(value(pitch), '65');
      expect(gateway.guiValue(other, otherPitch), '0');
      // Note 3: s publishes on patcher.<patch>.<name>, and the Code surface's
      // patch.tutorials.s_r.send('pitch', 67) publishes a float there.
      final heard = <BusValue>[];
      final sub = Bus.subscribe('patcher.tutorials.s_r.pitch')
          .listen((f) => heard.add(f.value));
      type(at('.i', 60, 160), 66);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(heard, [const BusInt(66)]);
      expect(value(pitch), '66');
      Bus.publish('patcher.tutorials.s_r.pitch', const BusFloat(67));
      expect(value(pitch), '67');
    });

    test(
      's and r: only one r of a name hears an s (yse-soundengine #1239)',
      () {
        // The title note's engine gap. When this fails, the engine delivers to
        // every r: drop the caveat from the tutorial and this test.
        open('s-r');
        final boxes = [
          for (var i = 0; i < 3; i++) probe(inst, '.r', 'pitch', '.i').$2,
        ];
        type(at('.i', 60, 160), 61);
        final got = [
          for (final b in [at('.i', 330, 220), ...boxes]) value(b),
        ];
        expect(got.where((v) => v == '61'), hasLength(1), reason: '$got');
      },
    );

    test('forward: no name, a name, another, nowhere, a number', () {
      open('forward');
      final number = at('.i', 60, 160);
      final left = at('.i', 60, 400);
      final right = at('.i', 200, 400);
      type(number, 5);
      expect((value(left), value(right)), ('0', '0'), reason: 'no name yet');
      click(msg('left'));
      type(number, 7);
      expect((value(left), value(right)), ('7', '0'));
      click(msg('right'));
      type(number, 8);
      expect((value(left), value(right)), ('7', '8'));
      click(msg('nowhere'));
      type(number, 9);
      expect((value(left), value(right)), ('7', '8'), reason: 'lost');
      // Note 3: a number is a name too.
      final fwd = at('.forward', 60, 240);
      final (_, two) = probe(inst, '.r', '2', '.i');
      gateway.sendInt(inst, fwd, 1, 2);
      type(number, 10);
      expect(value(two), '10');
      // The title note: send left on the left inlet is passed on as it is.
      final (_, words) = probe(inst, '.r', 'words');
      gateway.sendMessage(inst, fwd, 1, 'words');
      gateway.sendMessage(inst, fwd, 0, 'send left');
      expect(value(words), 'send left');
      expect(value(left), '7');
    });

    test('value: a start value, stored silently, set and read anywhere', () {
      open('value');
      final out = at('.f', 360, 280);
      final read = at('.b', 360, 160);
      click(read);
      expect(double.parse(value(out)), 0.5);
      // Each value gain sends only on a bang: wire a box to the left one to
      // see that storing sends nothing.
      final leftValue = at('.value', 60, 220);
      final watch = gateway.createObject(inst, '.f');
      gateway.connect(
        inst,
        fromHandleId: leftValue,
        outlet: 0,
        toHandleId: watch,
        inlet: 0,
      );
      type(at('.f', 60, 160), 0.8);
      expect(double.parse(value(out)), 0.5, reason: 'only stored');
      expect(double.parse(value(watch)), 0, reason: 'stores, sends nothing');
      click(read);
      expect(double.parse(value(out)), closeTo(0.8, 1e-6));
      click(msg('0.25'));
      click(read);
      expect(double.parse(value(out)), 0.25);
      // The title note: a list is stored too.
      gateway.sendList(inst, leftValue, 0, '1 2');
      final (reader, list) = probe(inst, '.value', 'gain');
      click(reader);
      expect(value(list), '1 2');
      // A name is shared only inside its patch.
      final other = another();
      final (theirs, theirOut) = probe(other, '.value', 'gain 3', '.i');
      gateway.sendBang(other, theirs, 0);
      render(3);
      expect(gateway.guiValue(other, theirOut), '3', reason: 'its own');
      click(read);
      expect(value(list), '1 2', reason: 'this patch keeps its own');
    });

    test('print: a named line, the default name, the per-tick cap', () async {
      final lines = <String>[];
      final sub = Log.instance.messages.listen(lines.add);
      addTearDown(sub.cancel);
      open('print');
      type(at('.i', 60, 160), 60);
      click(msg('hello'));
      click(at('.b', 310, 160));
      render(3);
      click(at('.b', 60, 320));
      render(3);
      for (var i = 0; i < 50 && !lines.any((l) => l.contains('dropped')); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final printed = [
        for (final l in lines)
          if (l.contains(': ')) l.substring(l.indexOf(RegExp(r'\w+: '))),
      ];
      expect(printed, [
        'pitch: 60',
        'print: hello',
        'print: bang',
        'flood: 1',
        'flood: 2',
        'flood: rate limit reached (2 per tick); further messages dropped',
      ]);
      expect(
        lines.first,
        startsWith('(App Message)'),
        reason: "the engine's tag in front",
      );
    });
  });

  test('every data store and sequencer type has a tutorial (#505)', () {
    for (final type in [
      '.coll', '.table', '.funbuff', '.bag', '.capture', //
      '.textfile', '.seq', '.qlist', '.mtr',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  group(
    'data store and sequencer tutorials (#505) do what their notes say',
    () {
      late int inst;
      late PatcherGraphSnapshot graph;
      final others = <int>[];

      void render(int blocks) {
        for (var i = 0; i < blocks; i++) {
          System.instance
            ..renderOffline(1)
            ..update();
        }
      }

      void mount(int id) {
        gateway.mountAsSource(id);
        for (var i = 0; i < 5000 && !gateway.isSourceReady(id); i++) {
          render(1);
          sleep(const Duration(milliseconds: 1));
        }
        expect(gateway.isSourceReady(id), isTrue, reason: 'mounted');
        render(20);
      }

      // Every tutorial is mounted while open (#528).
      void open(String slug) {
        inst = gateway.createInstance(mainOutputs: 1);
        gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
        graph = gateway.enumerate(inst);
        mount(inst);
      }

      tearDown(() {
        gateway.disposeInstance(inst);
        for (final o in others) {
          gateway.disposeInstance(o);
        }
        others.clear();
        render(20);
      });

      int at(String type, double x, double y) => graph.objects
          .firstWhere(
            (o) => o.type == type && o.position == Offset(x, y),
            orElse: () => throw StateError('no $type at ($x, $y)'),
          )
          .handleId;
      int msg(String text) => graph.objects
          .singleWhere((o) => o.type == '.m' && o.args == text)
          .handleId;
      String value(int id) => gateway.guiValue(inst, id);
      void click(int id) => gateway.sendBang(inst, id, 0);
      void type(int id, num v) => v is int
          ? gateway.sendInt(inst, id, 0, v)
          : gateway.sendFloat(inst, id, 0, v.toDouble());
      // A fresh object in [i] wired to a fresh display box.
      (int, int) probe(int i, String t, String args, [String box = '.l']) {
        final o = gateway.createObject(i, t, args: args);
        final l = gateway.createObject(i, box);
        gateway.connect(i, fromHandleId: o, outlet: 0, toHandleId: l, inlet: 0);
        return (o, l);
      }

      // A file read or write finishes on a worker thread and is delivered on a
      // later block: render with real pauses until [done] holds.
      void renderUntil(bool Function() done) {
        for (var i = 0; i < 500 && !done(); i++) {
          render(2);
          sleep(const Duration(milliseconds: 2));
        }
      }

      // Runs [body] with the process's working directory set to a fresh temp
      // folder and hands it the folder where a relative file name lands
      // ([engineFileDir]: that temp folder on Linux, the executable's folder
      // on Windows, #541), cleared of [names] before and after.
      void inTempDir(List<String> names, void Function(Directory dir) body) {
        final temp = Directory.systemTemp.createTempSync('phi_505_');
        final old = Directory.current;
        Directory.current = temp;
        final dir = engineFileDir();
        void clear() {
          for (final n in names) {
            final f = File('${dir.path}${Platform.pathSeparator}$n');
            if (f.existsSync()) f.deleteSync();
          }
        }

        clear();
        try {
          body(dir);
        } finally {
          clear();
          Directory.current = old;
          temp.deleteSync(recursive: true);
        }
      }

      test('coll: recall, next and dump, a shared name, a file', () {
        open('coll');
        inTempDir(['cues.txt'], (dir) {
          final data = at('.l', 60, 320);
          final address = at('.l', 250, 380);
          final recall = at('.i', 60, 200);
          type(recall, 2);
          expect(value(data), '62 65 69');
          click(msg('intro'));
          expect(value(data), '0 0 0');
          // Note 2: next walks the stored order and wraps; the address first.
          final walked = <String>[];
          for (var i = 0; i < 5; i++) {
            click(msg('next'));
            walked.add('${value(address)} = ${value(data)}');
          }
          expect(walked, [
            'address 1 = 60 64 67',
            'address 2 = 62 65 69',
            'address 3 = 64 67 71',
            'address intro = 0 0 0',
            'address 1 = 60 64 67',
          ]);
          final (dumpDone, dumps) = probe(inst, '.counter', '', '.i');
          gateway.connect(
            inst,
            fromHandleId: at('.coll', 60, 260),
            outlet: 2,
            toHandleId: dumpDone,
            inlet: 0,
          );
          click(msg('dump'));
          expect(value(data), '0 0 0', reason: 'intro is the last entry');
          expect(value(dumps), '1', reason: 'the third outlet banged');
          // Note 3: the middle coll shares the collection.
          type(at('.i', 60, 460), 79);
          type(recall, 4);
          expect(value(data), '72 76 79');
          // Title note: a one-number entry leaves as a number.
          final (reader, single) = probe(inst, '.coll', 'cues', '.i');
          gateway.sendList(inst, at('.coll', 60, 580), 0, '5 42');
          gateway.sendInt(inst, reader, 0, 5);
          expect(value(single), '42');
          // Each coll walks with its own pointer: the middle one starts at 1.
          final mid = at('.coll', 60, 580);
          final midData = gateway.createObject(inst, '.l');
          gateway.connect(
            inst,
            fromHandleId: mid,
            outlet: 0,
            toHandleId: midData,
            inlet: 0,
          );
          gateway.sendMessage(inst, mid, 0, 'next');
          expect(value(midData), '60 64 67');
          // Note 4: write, clear, read back.
          final files = at('.coll', 60, 780);
          final (loaded, reads) = probe(inst, '.counter', '', '.i');
          gateway.connect(
            inst,
            fromHandleId: files,
            outlet: 3,
            toHandleId: loaded,
            inlet: 0,
          );
          click(at('.m', 60, 660));
          final file = File('${dir.path}${Platform.pathSeparator}cues.txt');
          renderUntil(file.existsSync);
          expect(file.existsSync(), isTrue, reason: whereIs('cues.txt'));
          expect(file.readAsStringSync(), contains('2, 62 65 69;'));
          expect(file.readAsStringSync(), contains('intro, 0 0 0;'));
          click(msg('clear'));
          gateway.sendList(inst, data, 0, 'none');
          type(recall, 2);
          expect(value(data), 'none', reason: 'cleared: nothing is sent');
          click(at('.m', 300, 660));
          renderUntil(() => value(reads) == '1');
          expect(value(reads), '1', reason: 'the fourth outlet banged');
          type(recall, 2);
          expect(value(data), '62 65 69');
        });
      });

      test('table: a step sequence, a changed step, a weighted dice', () {
        open('table');
        final address = at('.i', 60, 400);
        final out = at('.i', 60, 520);
        const steps = [60, 62, 64, 65, 67, 69, 71, 72];
        for (var a = 0; a < 8; a++) {
          type(address, a);
          expect(value(out), '${steps[a]}', reason: 'step $a');
        }
        // Note 1: the metro steps the counter through % 8.
        final toggle = at('.t', 60, 200);
        gateway.sendInt(inst, toggle, 0, 1);
        gateway.sendInt(inst, toggle, 0, 0);
        final step = int.parse(value(address));
        expect(step, inInclusiveRange(0, 7), reason: 'the first tick at once');
        expect(value(out), '${steps[step]}');
        // Note 2: a value waits on the right inlet for the next address.
        type(address, 3);
        expect(value(out), '65');
        gateway.sendInt(inst, at('.i', 200, 400), 0, 72);
        gateway.sendList(inst, out, 0, '0');
        type(address, 3);
        expect(value(out), '0', reason: 'stored, nothing sent');
        type(address, 3);
        expect(value(out), '72');
        // Note 3: weights 1 2 0 5.
        final dice = at('.b', 60, 620);
        final picked = at('.i', 60, 730);
        final counts = List.filled(4, 0);
        for (var i = 0; i < 1600; i++) {
          click(dice);
          counts[int.parse(value(picked))]++;
        }
        expect(counts[2], 0, reason: 'weight 0 never comes up');
        expect(counts[3], inInclusiveRange(800, 1200), reason: '$counts');
        expect(counts[1], inInclusiveRange(250, 550), reason: '$counts');
        expect(counts[0], inInclusiveRange(100, 330), reason: '$counts');
        // quantile picks by a number: the half-way point of 8 falls in 3.
        final (q, qOut) = probe(inst, '.table', '4', '.i');
        gateway.sendMessage(inst, q, 0, 'set 0 1 2 0 5');
        gateway.sendMessage(inst, q, 0, 'fquantile 0.5');
        expect(value(qOut), '3');
        gateway.sendMessage(inst, q, 0, 'fquantile 0.2');
        expect(value(qOut), '1');
        // Title note: a second table of the same name does not share.
        final named = gateway.createObject(inst, '.table', args: 'steps 4');
        final (twin, twinOut) = probe(inst, '.table', 'steps 4', '.i');
        gateway.sendList(inst, named, 0, '1 9');
        gateway.sendInt(inst, twin, 0, 1);
        expect(value(twinOut), '0');
      });

      test('funbuff: a staircase, interp, a stored pair, next and goto', () {
        open('funbuff');
        final x = at('.i', 60, 220);
        final y = at('.f', 60, 400);
        final dx = at('.i', 180, 400);
        type(x, 150);
        expect(double.parse(value(y)), 50);
        type(x, 400);
        expect(double.parse(value(y)), 20);
        type(x, -5);
        expect(double.parse(value(y)), 20, reason: 'below 0: nothing sent');
        // Note 2.
        type(at('.f', 260, 220), 200.0);
        expect(double.parse(value(y)), 35);
        type(at('.f', 260, 220), 500.0);
        expect(double.parse(value(y)), 20);
        type(at('.f', 260, 220), -50.0);
        expect(double.parse(value(y)), 10);
        // Note 3.
        type(at('.i', 160, 220), 99);
        gateway.sendFloat(inst, y, 0, 0);
        type(x, 200);
        expect(double.parse(value(y)), 0, reason: 'stored, nothing sent');
        type(x, 250);
        expect(double.parse(value(y)), 99);
        // Note 4.
        final (endCount, ends) = probe(inst, '.counter', '', '.i');
        gateway.connect(
          inst,
          fromHandleId: at('.funbuff', 60, 340),
          outlet: 2,
          toHandleId: endCount,
          inlet: 0,
        );
        final walked = <String>[];
        for (var i = 0; i < 4; i++) {
          click(msg('next'));
          walked.add('${value(dx)} ${double.parse(value(y))}');
        }
        expect(walked, ['0 10.0', '100 50.0', '100 99.0', '100 20.0']);
        expect(value(ends), '0');
        click(msg('next'));
        expect(value(ends), '1', reason: 'past the last pair');
        click(msg('0'));
        click(msg('next'));
        expect((value(dx), double.parse(value(y))), ('0', 10.0));
      });

      test('bag: toggles add and remove, a bang lists them newest first', () {
        open('bag');
        final held = at('.l', 380, 400);
        final show = at('.b', 380, 200);
        click(show);
        expect(value(held), 'held');
        gateway.sendInt(inst, at('.t', 60, 200), 0, 1);
        gateway.sendInt(inst, at('.t', 160, 200), 0, 1);
        click(show);
        expect(value(held), 'held 64 60');
        gateway.sendInt(inst, at('.t', 60, 200), 0, 0);
        click(show);
        expect(value(held), 'held 64');
        // Title note: at most once, unless the bag has an argument.
        final bag = at('.bag', 60, 340);
        gateway.sendList(inst, bag, 0, '64 1');
        click(show);
        expect(value(held), 'held 64');
        final (dup, dupCount) = probe(inst, '.bag', 'dup', '.i');
        gateway.sendList(inst, dup, 0, '64 1');
        gateway.sendInt(inst, dup, 0, 64);
        gateway.sendMessage(inst, dup, 0, 'length');
        expect(value(dupCount), '2');
        click(msg('clear'));
        click(show);
        expect(value(held), 'held');
      });

      test('capture: a ring of four, dump, count, clear', () {
        open('capture');
        final add = at('.b', 60, 200);
        final past = at('.l', 300, 500);
        final count = at('.i', 160, 440);
        for (var i = 0; i < 6; i++) {
          click(add);
        }
        expect(value(at('.i', 60, 320)), '6');
        click(at('.b', 240, 200));
        expect(value(past), 'past 3 4 5 6');
        click(msg('count'));
        expect(value(count), '6');
        click(msg('count'));
        expect(value(count), '0');
        // Title note: a list is one item per element.
        final capture = at('.capture', 60, 380);
        gateway.sendList(inst, capture, 0, '7 8');
        click(at('.b', 240, 200));
        expect(value(past), 'past 5 6 7 8');
        click(msg('clear'));
        click(at('.b', 240, 200));
        expect(value(past), 'past');
        click(msg('count'));
        expect(value(count), '2', reason: 'clear does not reset the count');
      });

      test('textfile: lines with cr, line n, query, a file', () {
        open('textfile');
        inTempDir(['lines.txt'], (dir) {
          final number = at('.i', 60, 200);
          final count = at('.i', 200, 510);
          final shown = at('.l', 60, 570);
          for (final n in [60, 64, 67]) {
            type(number, n);
          }
          click(msg('cr'));
          click(msg('intro'));
          click(msg('cr'));
          click(msg('query'));
          expect(value(count), '2');
          final lineBox = at('.i', 440, 200);
          type(lineBox, 1);
          expect(value(shown), '60 64 67');
          type(lineBox, 2);
          expect(value(shown), 'intro');
          // The title note: dump sends every line.
          final (zl, dumped) = probe(inst, '.zl', 'group');
          gateway.connect(
            inst,
            fromHandleId: at('.textfile', 60, 450),
            outlet: 0,
            toHandleId: zl,
            inlet: 0,
          );
          gateway.sendMessage(inst, at('.textfile', 60, 450), 0, 'dump');
          gateway.sendBang(inst, zl, 0);
          expect(value(dumped), '60 64 67 intro');
          // Note 3.
          final (loaded, reads) = probe(inst, '.counter', '', '.i');
          gateway.connect(
            inst,
            fromHandleId: at('.textfile', 60, 450),
            outlet: 2,
            toHandleId: loaded,
            inlet: 0,
          );
          click(at('.m', 200, 270));
          final file = File('${dir.path}${Platform.pathSeparator}lines.txt');
          renderUntil(file.existsSync);
          expect(file.existsSync(), isTrue, reason: whereIs('lines.txt'));
          expect(file.readAsLinesSync(), ['60 64 67', 'intro']);
          click(msg('clear'));
          click(msg('query'));
          expect(value(count), '0');
          click(at('.m', 330, 330));
          renderUntil(() => value(reads) == '1');
          expect(value(reads), '1', reason: 'the right outlet banged');
          click(msg('query'));
          expect(value(count), '2');
          type(lineBox, 1);
          expect(value(shown), '60 64 67');
        });
      });

      test('seq: record, play back, start -1 on the domain clock', () {
        open('seq');
        final note = at('.l', 360, 570);
        final keys = at('.kslider', 60, 200);
        final played = at('.kslider', 60, 570);
        final (endCount, ends) = probe(inst, '.counter', '', '.i');
        gateway.connect(
          inst,
          fromHandleId: at('.seq', 60, 450),
          outlet: 1,
          toHandleId: endCount,
          inlet: 0,
        );
        // A key press: velocity, then pitch.
        void key(int pitch, int velocity) =>
            gateway.sendList(inst, keys, 0, '$pitch $velocity');
        click(msg('record'));
        render(10);
        key(60, 100);
        render(40);
        key(60, 0);
        key(64, 100);
        render(40);
        key(64, 0);
        click(msg('stop'));
        // The blocks at which each new note reached the list box.
        List<(int, String)> watch(void Function() go, int blocks) {
          final seen = <(int, String)>[];
          var last = value(note);
          go();
          for (var b = 0; b < blocks; b++) {
            render(1);
            final now = value(note);
            if (now != last) seen.add((b, now));
            last = now;
          }
          return seen;
        }

        final asRecorded = watch(() => click(msg('start')), 150);
        expect(asRecorded.map((e) => e.$2), ['60 100', '64 100', '64 0']);
        // 40 blocks apart, as recorded.
        expect(asRecorded[1].$1 - asRecorded[0].$1, inInclusiveRange(38, 42));
        expect(value(ends), '1');
        expect(value(played), isNot(contains('100')), reason: 'all released');
        // Note 3: start -1 on seqclock at 120 BPM, about as recorded.
        final onClock = watch(() => click(msg('-1')), 200);
        expect(onClock.map((e) => e.$2), ['60 100', '64 100', '64 0']);
        expect(onClock[1].$1 - onClock[0].$1, inInclusiveRange(32, 48));
        // Note 4: at 60 BPM, half speed; a plain start ignores the clock.
        click(msg('60'));
        final slow = watch(() => click(msg('-1')), 300);
        expect(slow[1].$1 - slow[0].$1, inInclusiveRange(72, 88));
        click(msg('240'));
        final fast = watch(() => click(msg('-1')), 150);
        expect(fast[1].$1 - fast[0].$1, inInclusiveRange(14, 26));
        click(msg('60'));
        final plain = watch(() => click(msg('start')), 150);
        expect(plain[1].$1 - plain[0].$1, inInclusiveRange(38, 42));
        final doubled = watch(
          () => gateway.sendMessage(inst, at('.seq', 60, 450), 0, 'start 2048'),
          150,
        );
        expect(doubled[1].$1 - doubled[0].$1, inInclusiveRange(18, 22));
        click(msg('120'));
      });

      test('qlist: a timed score to r names, next, tempo', () {
        open('qlist');
        final pitch = at('.i', 60, 540);
        final level = at('.f', 200, 540);
        final wait = at('.i', 60, 400);
        final (endCount, ends) = probe(inst, '.counter', '', '.i');
        gateway.connect(
          inst,
          fromHandleId: at('.qlist', 60, 340),
          outlet: 1,
          toHandleId: endCount,
          inlet: 0,
        );
        // The blocks at which pitch changed, while playback runs to its end.
        List<(int, String, String)> play(String endsAt) {
          final seen = <(int, String, String)>[];
          var last = value(pitch);
          for (var b = 0; b < 1000 && value(ends) != endsAt; b++) {
            render(1);
            final now = value(pitch);
            if (now != last) seen.add((b, now, value(level)));
            last = now;
          }
          return seen;
        }

        click(at('.b', 60, 220));
        final score = play('1');
        expect(score.map((e) => (e.$2, double.parse(e.$3))), [
          ('60', 0.5),
          ('64', 0.5),
          ('67', 0.2),
        ]);
        expect(value(wait), '500');
        // 500 ms apart: 187.5 blocks of 128 at 48 kHz.
        final gap = score[1].$1 - score[0].$1;
        expect(gap, inInclusiveRange(180, 195));
        // Note 2: next steps by hand, without waiting.
        // A word line reaches its r on the next rendered block.
        void step() {
          click(msg('next'));
          render(3);
        }

        click(msg('rewind'));
        step();
        expect((value(pitch), value(wait)), ('60', '500'));
        step();
        expect(value(pitch), '64');
        step();
        expect(value(pitch), '67');
        expect(value(ends), '2', reason: 'next ran past the last line');
        // stop halts playback where it is.
        click(at('.b', 60, 220));
        render(10);
        click(msg('stop'));
        render(400);
        expect(value(pitch), '60');
        // Note 3: tempo 2 halves the waits.
        type(at('.f', 430, 220), 2.0);
        click(at('.b', 60, 220));
        final fast = play('3');
        expect(
          fast[1].$1 - fast[0].$1,
          inInclusiveRange(gap ~/ 2 - 3, gap ~/ 2 + 3),
        );
        // Title note: only r objects in this patch hear it.
        final other = gateway.createInstance(mainOutputs: 1);
        others.add(other);
        mount(other);
        final (_, theirs) = probe(other, '.r', 'pitch', '.i');
        click(msg('rewind'));
        click(msg('next'));
        render(3);
        expect(gateway.guiValue(other, theirs), '0');
      });

      test('qlist: only one r of a name hears a word line '
          '(yse-soundengine #1239)', () {
        // The title note's engine gap. When this fails, the engine delivers to
        // every r: drop the caveat from the tutorial and this test.
        open('qlist');
        final boxes = [
          for (var i = 0; i < 3; i++) probe(inst, '.r', 'pitch', '.i').$2,
        ];
        click(msg('next'));
        render(3);
        final got = [
          for (final b in [at('.i', 60, 540), ...boxes]) value(b),
        ];
        expect(got.where((v) => v == '60'), hasLength(1), reason: '$got');
      });

      test('mtr: two tracks recorded, played together and one alone', () {
        open('mtr');
        final in1 = at('.i', 300, 280);
        final in2 = at('.i', 420, 280);
        final out1 = at('.i', 60, 400);
        final out2 = at('.i', 160, 400);
        click(msg('record'));
        render(10);
        type(in1, 1);
        type(in2, 10);
        render(50);
        type(in1, 2);
        render(50);
        type(in1, 3);
        type(in2, 30);
        click(msg('stop'));
        expect(
          (value(out1), value(out2)),
          ('0', '0'),
          reason: 'recording only',
        );
        List<(int, String, String)> watch(int blocks) {
          final seen = <(int, String, String)>[];
          var last = (value(out1), value(out2));
          for (var b = 0; b < blocks; b++) {
            render(1);
            final now = (value(out1), value(out2));
            if (now != last) seen.add((b, now.$1, now.$2));
            last = now;
          }
          return seen;
        }

        click(at('.m', 165, 220));
        final both = watch(150);
        expect(both.map((e) => (e.$2, e.$3)), [
          ('1', '10'),
          ('2', '10'),
          ('3', '30'),
        ]);
        expect(both[1].$1 - both[0].$1, 50, reason: 'the recorded rhythm');
        // Note 2: stop halts both.
        type(out1, 0);
        type(out2, 0);
        click(at('.m', 165, 220));
        render(20);
        click(msg('stop'));
        expect((value(out1), value(out2)), ('1', '10'));
        expect(watch(150), isEmpty, reason: 'stopped');
        // Note 3: play into track 2 plays it alone.
        type(out1, 0);
        type(out2, 0);
        click(at('.m', 420, 220));
        final alone = watch(150);
        expect(alone.map((e) => (e.$2, e.$3)), [('0', '10'), ('0', '30')]);
      });
    },
  );

  test('every dictionary type has a tutorial (#506)', () {
    for (final type in [
      '.dict', '.dict.pack', '.dict.unpack', '.dict.route', //
      '.dict.compare', '.dict.iter', '.dict.slice', '.dict.strip',
      '.dict.join', '.dict.group', '.dict.serialize', '.dict.deserialize',
      '.dict.print',
    ]) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  group('dictionary tutorials (#506) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Every tutorial is mounted while open (#528).
    void open(String slug) {
      inst = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: 'mounted');
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
    String value(int id) {
      render(3);
      return gateway.guiValue(inst, id);
    }

    void click(int id) => gateway.sendBang(inst, id, 0);
    void type(int id, num v) => v is int
        ? gateway.sendInt(inst, id, 0, v)
        : gateway.sendFloat(inst, id, 0, v.toDouble());
    // A fresh object wired to a fresh list box.
    (int, int) probe(String t, String args, {int outlet = 0}) {
      final o = gateway.createObject(inst, t, args: args);
      final l = gateway.createObject(inst, '.l');
      gateway.connect(
        inst,
        fromHandleId: o,
        outlet: outlet,
        toHandleId: l,
        inlet: 0,
      );
      return (o, l);
    }

    // What dict.serialize makes of the dictionary [name], right now.
    String json(String name) {
      final (s, l) = probe('.dict.serialize', name);
      click(s);
      return value(l);
    }

    // dict.deserialize parses on a worker thread and lands on a later block:
    // render with real pauses until [done] holds.
    void renderUntil(bool Function() done) {
      for (var i = 0; i < 500 && !done(); i++) {
        render(2);
        sleep(const Duration(milliseconds: 2));
      }
      expect(done(), isTrue, reason: 'the background work finished');
    }

    test('dict: get, set, a miss, size, keys, delete, clear, the reference, '
        'a shared name', () {
      open('dict');
      final data = at('.l', 60, 520);
      final freq = at('.m', 60, 220);
      final chord = at('.m', 170, 220);
      click(freq);
      expect(value(data), 'got 440');
      click(chord);
      expect(value(data), 'got 0 4 7');
      click(at('.m', 280, 220));
      expect(value(data), 'missing');
      // Note 2: the number box sets freq through prepend.
      type(at('.i', 400, 220), 330);
      click(freq);
      expect(value(data), 'got 330');
      // Note 3, and the title note's load order (yse-soundengine#1243).
      click(at('.m', 200, 340));
      expect(value(data), 'got 3');
      click(at('.m', 310, 340));
      expect(value(data), 'got chord freq gain');
      click(at('.m', 530, 220));
      click(chord);
      expect(value(data), 'missing', reason: 'deleted');
      // Note 4: the reference.
      click(at('.b', 530, 340));
      expect(value(at('.l', 320, 520)), 'dictionary synth');
      // Note 5: the lower dict shares the dictionary.
      click(at('.m', 60, 600));
      expect(value(at('.i', 60, 780)), '330');
      click(at('.m', 420, 340));
      click(at('.m', 200, 340));
      expect(value(data), 'got 0', reason: 'clear removes every entry');
      // Title note: keys nest with ::, and the order a dictionary was written
      // in is lost when it is saved and loaded again (#1243).
      final top = at('.dict', 60, 400);
      gateway.sendList(inst, top, 0, 'set voice::1::freq 440');
      gateway.sendList(inst, top, 0, 'set amp 1');
      expect(json('synth'), '{"voice":{"1":{"freq":440}},"amp":1}');
      final saved = gateway.dumpJson(inst);
      final copy = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(copy, saved);
      final reloaded = gateway
          .enumerate(copy)
          .objects
          .firstWhere((o) => o.type == '.dict')
          .handleId;
      final keys = gateway.createObject(copy, '.l');
      final got = gateway.createObject(copy, '.prepend', args: 'got');
      gateway
        ..connect(
          copy,
          fromHandleId: reloaded,
          outlet: 0,
          toHandleId: got,
          inlet: 0,
        )
        ..connect(
          copy,
          fromHandleId: got,
          outlet: 0,
          toHandleId: keys,
          inlet: 0,
        )
        ..sendList(copy, reloaded, 0, 'getkeys');
      render(3);
      expect(
        gateway.guiValue(copy, keys),
        'got amp voice',
        reason: 'yse-soundengine#1243: a reload sorts the keys',
      );
      gateway.disposeInstance(copy);
    });

    test('dict.pack and dict.unpack: cold then hot, right to left', () {
      open('dict-pack-unpack');
      final ref = at('.l', 300, 340);
      final both = at('.l', 60, 580);
      type(at('.f', 240, 220), 0.5);
      expect(value(ref), '', reason: 'the right inlet only stores');
      type(at('.i', 60, 220), 440);
      expect(value(ref), 'dictionary voice');
      expect(json('voice'), '{"freq":440,"gain":0.5}');
      expect(value(at('.i', 60, 460)), '440');
      expect(double.parse(value(at('.f', 240, 460))), 0.5);
      expect(value(both), '440 0.5', reason: 'right to left: one list');
      // Note 3.
      type(at('.f', 240, 220), 0.8);
      type(at('.i', 60, 220), 220);
      expect(value(both), '220 0.8');
      // A key that never got a value is written empty and unpacks to nothing.
      final (fresh, freshRef) = probe('.dict.pack', 'blank freq gain');
      final (empty, emptyOut) = probe('.dict.unpack', 'blank gain');
      gateway.connect(
        inst,
        fromHandleId: fresh,
        outlet: 0,
        toHandleId: empty,
        inlet: 0,
      );
      type(fresh, 1);
      expect(value(freshRef), 'dictionary blank');
      expect(json('blank'), '{"freq":1,"gain":""}');
      expect(value(emptyOut), '', reason: 'nothing for an empty value');
    });

    test(
      'dict.route and dict.compare: first key, none, a verdict and paths',
      () {
        open('dict-route-compare');
        final routed = at('.l', 60, 580);
        final button = at('.b', 180, 340);
        final clear = at('.m', 60, 340);
        type(at('.i', 60, 220), 60);
        click(button);
        expect(value(routed), 'note');
        click(clear);
        type(at('.i', 220, 220), 7);
        click(button);
        expect(value(routed), 'cc');
        click(clear);
        click(button);
        expect(value(routed), 'none');
        type(at('.i', 220, 220), 7);
        type(at('.i', 60, 220), 60);
        click(button);
        expect(value(routed), 'note', reason: 'the first key argument wins');
        // Title note: a key matches an entry under it.
        gateway.sendList(inst, at('.dict', 60, 400), 0, 'clear');
        gateway.sendList(inst, at('.dict', 60, 400), 0, 'set cc::1 7');
        click(button);
        expect(value(routed), 'cc');
        // Note 3.
        final equal = at('.i', 380, 460);
        final paths = at('.l', 470, 460);
        final compare = at('.b', 540, 280);
        click(compare);
        expect((value(equal), value(paths)), ('0', 'tempo'));
        type(at('.i', 380, 220), 100);
        gateway.sendList(inst, paths, 0, 'unchanged');
        click(compare);
        expect((value(equal), value(paths)), ('1', 'unchanged'));
        // Title note: values compared as text.
        gateway.sendFloat(inst, at('.prepend', 380, 280), 0, 100);
        click(compare);
        expect(value(equal), '0', reason: '100 and 100. differ');
      },
    );

    test('dict.iter, dict.slice and dict.strip: pairs, a slice, a strip', () {
      open('dict-iter-slice-strip');
      final pairs = at('.l', 60, 460);
      click(at('.b', 60, 220));
      expect(
        value(pairs),
        'name lead voice::1::freq 440 voice::1::gain 0.5 voice::2::freq 220',
      );
      // Note 2.
      click(at('.b', 60, 540));
      expect(value(at('.l', 60, 720)), '{"freq":440,"gain":0.5}');
      expect(
        value(at('.l', 300, 720)),
        '{"name":"lead","voice":{"2":{"freq":220}}}',
      );
      // Note 3: strip edits synth in place and its reference runs iter.
      click(at('.b', 300, 220));
      expect(value(pairs), 'name lead voice::1::freq 440 voice::1::gain 0.5');
      click(at('.b', 60, 540));
      expect(value(at('.l', 300, 720)), '{"name":"lead"}');
      // Title note: the reference runs iter too.
      gateway.sendList(inst, pairs, 0, 'before');
      gateway.sendList(inst, at('.dict.iter', 60, 340), 0, 'dictionary synth');
      expect(value(pairs), startsWith('name lead'));
    });

    test('dict.join and dict.group: an override and groups by value', () {
      open('dict-join-group');
      final out = at('.l', 60, 520);
      click(at('.b', 60, 220));
      expect(value(out), '{"freq":440,"gain":0.8,"wave":"sine","cutoff":1200}');
      type(at('.f', 240, 220), 0.3);
      click(at('.b', 60, 220));
      expect(value(out), '{"freq":440,"gain":0.3,"wave":"sine","cutoff":1200}');
      expect(json('base'), '{"freq":440,"gain":0.5,"wave":"sine"}');
      expect(json('preset'), '{"cutoff":1200,"gain":0.3}');
      // Note 3.
      click(at('.b', 60, 600));
      expect(
        value(at('.l', 60, 780)),
        '{"synth":{"bass":"synth","lead":"synth"},'
        '"drums":{"kick":"drums","snare":"drums"}}',
      );
      // Title note: with a key, records group by the value at that key.
      final notes = gateway.createObject(inst, '.dict', args: 'notes');
      for (final m in [
        'set n1::inst bass', 'set n1::pitch 40', //
        'set n2::inst lead', 'set n3::inst bass',
      ]) {
        gateway.sendList(inst, notes, 0, m);
      }
      click(
        gateway.createObject(inst, '.dict.group', args: 'notes byinst inst'),
      );
      expect(
        json('byinst'),
        '{"bass":{"n1":{"inst":"bass","pitch":40},"n3":{"inst":"bass"}},'
        '"lead":{"n2":{"inst":"lead"}}}',
      );
    });

    test('dict.serialize, dict.deserialize and dict.print: JSON both ways, '
        'the log, a file', () async {
      final lines = <String>[];
      final sub = Log.instance.messages.listen(lines.add);
      addTearDown(sub.cancel);
      open('dict-serialize');
      final bpm = at('.i', 60, 640);
      click(at('.b', 60, 220));
      expect(
        value(at('.l', 60, 400)),
        '{"bpm":120,"chord":[0,4,7],"title":"intro"}',
      );
      renderUntil(() => value(bpm) == '120');
      expect(json('copy'), '{"bpm":120,"chord":[0,4,7],"title":"intro"}');
      // Note 3: the typed JSON replaces copy.
      click(at('.m', 260, 460));
      renderUntil(() => value(bpm) == '90');
      expect(json('copy'), '{"bpm":90,"title":"outro"}');
      // The title note: deserialized keys come in alphabetical order (#1243).
      final des = at('.dict.deserialize', 60, 520);
      gateway.sendList(inst, des, 0, '{"title":"x","bpm":60}');
      renderUntil(() => value(bpm) == '60');
      expect(json('copy'), '{"bpm":60,"title":"x"}');
      for (var i = 0; i < 50 && !lines.any((l) => l.contains('"x"')); i++) {
        render(2);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final printed = [
        for (final l in lines)
          if (l.contains('copy: ')) l.substring(l.indexOf('copy: ')),
      ];
      expect(printed, containsAllInOrder(['copy: {', 'copy:   "bpm": 90,']));
      expect(printed.last, 'copy: }');
      // The title note: write and read a file.
      final dir = Directory.systemTemp.createTempSync('phi_506_');
      final old = Directory.current;
      Directory.current = dir;
      try {
        gateway.sendList(
          inst,
          at('.dict.serialize', 60, 340),
          0,
          'write song.json',
        );
        final file = File('${dir.path}/song.json');
        renderUntil(file.existsSync);
        renderUntil(() => file.readAsStringSync().contains('intro'));
        gateway.sendList(inst, des, 0, 'read song.json');
        renderUntil(() => value(bpm) == '120');
      } finally {
        Directory.current = old;
        dir.deleteSync(recursive: true);
      }
    });
  });

  test('every array type has a tutorial (#507)', () {
    final arrays = [
      for (final t in engineTypes)
        if (t == '.array' || t.startsWith('.array.')) t,
    ];
    expect(arrays, hasLength(57));
    for (final type in arrays) {
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  group('array tutorials (#507) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Every tutorial is mounted while open (#528).
    void mount() {
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: 'mounted');
      render(20);
    }

    void open(String slug) {
      inst = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(inst, jsonEncode(load(slug).payload.dump));
      mount();
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
    String value(int id) {
      render(3);
      return gateway.guiValue(inst, id);
    }

    double number(int id) => double.parse(value(id));
    void click(int id) => gateway.sendBang(inst, id, 0);
    void type(int id, num v) => v is int
        ? gateway.sendInt(inst, id, 0, v)
        : gateway.sendFloat(inst, id, 0, v.toDouble());
    void mark(int id) => gateway.sendList(inst, id, 0, 'before');
    // A fresh object wired from [outlet] to a fresh list box.
    (int, int) probe(String t, String args, {int outlet = 0}) {
      final o = gateway.createObject(inst, t, args: args);
      final l = gateway.createObject(inst, '.l');
      gateway.connect(
        inst,
        fromHandleId: o,
        outlet: outlet,
        toHandleId: l,
        inlet: 0,
      );
      return (o, l);
    }

    // A fresh object whose bang outlet [outlet] makes a list box say hit.
    (int, int) bangs(String t, String args, int outlet) {
      final o = gateway.createObject(inst, t, args: args);
      final m = gateway.createObject(inst, '.m', args: 'hit');
      final l = gateway.createObject(inst, '.l');
      gateway
        ..connect(
          inst,
          fromHandleId: o,
          outlet: outlet,
          toHandleId: m,
          inlet: 0,
        )
        ..connect(inst, fromHandleId: m, outlet: 0, toHandleId: l, inlet: 0);
      return (o, l);
    }

    // The array [name] right now, as text.
    String contents(String name) {
      final (s, l) = probe('.array.tostring', name);
      click(s);
      return value(l);
    }

    // A fresh array [name] holding [list].
    void fill(String name, String list) {
      final a = gateway.createObject(inst, '.array', args: name);
      gateway
        ..sendList(inst, a, 0, 'clear')
        ..sendList(inst, a, 0, 'append $list');
    }

    // array.deserialize parses on the engine's background pool and lands on a
    // later block: render with real pauses until [done] holds.
    void renderUntil(bool Function() done) {
      for (var i = 0; i < 500 && !done(); i++) {
        render(2);
        sleep(const Duration(milliseconds: 2));
      }
      expect(done(), isTrue, reason: 'the background work finished');
    }

    test('array: get, size, a miss, append, the reference, at, index, '
        'indexof, indexmap, saved contents', () {
      open('array');
      final data = at('.l', 60, 460);
      final getvalue = at('.m', 60, 220);
      click(getvalue);
      expect(value(data), 'got 60 64 67 72');
      click(at('.m', 170, 220));
      expect(value(data), 'got 4');
      final get = at('.i', 280, 220);
      type(get, 2);
      expect(value(data), 'got 67');
      type(get, 9);
      expect(value(data), 'missing');
      // Note 2.
      type(at('.i', 400, 220), 76);
      click(getvalue);
      expect(value(data), 'got 60 64 67 72 76');
      click(at('.b', 520, 220));
      expect(value(at('.l', 300, 460)), 'array notes');
      expect(value(at('.i', 480, 460)), '5');
      // Note 3, and the title note: nothing wraps, a negative is refused.
      final pos = at('.i', 60, 560);
      final fetched = at('.l', 60, 740);
      type(pos, 1);
      expect(value(fetched), 'at 64');
      mark(fetched);
      click(at('.array.at', 60, 620));
      expect(value(fetched), 'at 64', reason: 'a bang fetches again');
      type(pos, 9);
      expect(value(fetched), 'miss');
      mark(fetched);
      gateway.sendInt(inst, at('.array.at', 60, 620), 0, -1);
      expect(value(fetched), 'before', reason: 'refused, not wrapped');
      // Note 4.
      final find = at('.i', 300, 560);
      final found = at('.l', 300, 740);
      final indexof = at('.i', 540, 680);
      type(find, 67);
      expect(value(found), 'index 2');
      expect(value(indexof), '2');
      type(find, 61);
      expect(value(found), 'none');
      expect(value(indexof), '-1');
      mark(found);
      gateway.sendFloat(inst, at('.array.index', 300, 620), 0, 67);
      expect(value(found), 'none', reason: 'the float 67. is not the int 67');
      // Note 5.
      click(at('.b', 60, 820));
      expect(value(at('.l', 300, 880)), 'array notes');
      click(getvalue);
      expect(value(data), 'got 72 67 64 60');
      // The title note: the contents are saved with the patch.
      final saved = gateway.dumpJson(inst);
      gateway.disposeInstance(inst);
      render(20);
      inst = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(inst, saved);
      mount();
      click(at('.m', 60, 220));
      expect(value(at('.l', 60, 460)), 'got 72 67 64 60');
      // The title note: with another object of the name placed first, the
      // saved contents do not load (yse-soundengine#1245).
      final first = gateway.createInstance(mainOutputs: 1);
      gateway.createObject(first, '.array.length', args: 'late');
      final late = gateway.createObject(first, '.array', args: 'late');
      gateway.sendList(first, late, 0, 'append 1 2');
      final unloaded = gateway.dumpJson(first);
      gateway.disposeInstance(first);
      render(20);
      final again = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(again, unloaded);
      final reloaded = gateway
          .enumerate(again)
          .objects
          .firstWhere((o) => o.type == '.array')
          .handleId;
      final size = gateway.createObject(again, '.prepend', args: 'size');
      final out = gateway.createObject(again, '.l');
      gateway
        ..connect(
          again,
          fromHandleId: reloaded,
          outlet: 0,
          toHandleId: size,
          inlet: 0,
        )
        ..connect(
          again,
          fromHandleId: size,
          outlet: 0,
          toHandleId: out,
          inlet: 0,
        )
        ..sendList(again, reloaded, 0, 'getsize');
      render(3);
      expect(
        gateway.guiValue(again, out),
        'size 0',
        reason: 'yse-soundengine#1245: the binder created the store first',
      );
      gateway.disposeInstance(again);
    });

    test('array.push, pop, shift, unshift, insert, remove, replace, fill', () {
      open('array-edit');
      final now = at('.l', 60, 460);
      final took = at('.l', 420, 400);
      type(at('.i', 60, 220), 66);
      expect(value(now), 'now 60 62 64 66');
      type(at('.i', 240, 220), 58);
      expect(value(now), 'now 58 60 62 64 66');
      // Note 2.
      final pop = at('.b', 420, 220);
      click(pop);
      expect((value(took), value(now)), ('took 66', 'now 58 60 62 64'));
      click(at('.b', 580, 220));
      expect((value(took), value(now)), ('took 58', 'now 60 62 64'));
      // Note 3.
      final insValue = at('.i', 60, 540);
      final insPos = at('.i', 180, 540);
      type(insPos, 1);
      type(insValue, 61);
      expect(value(now), 'now 60 61 62 64');
      type(insPos, 9);
      type(insValue, 5);
      expect(contents('queue'), '60 61 62 64', reason: 'past the end');
      final remove = at('.i', 420, 540);
      type(remove, 0);
      expect((value(took), value(now)), ('took 60', 'now 61 62 64'));
      type(remove, 9);
      expect(value(took), 'miss');
      // Note 4.
      final replace = at('.b', 60, 680);
      final count = at('.i', 60, 800);
      click(replace);
      expect((value(count), value(now)), ('1', 'now 61 62 99'));
      click(replace);
      expect(value(count), '0');
      click(at('.b', 420, 680));
      expect(value(now), 'now 0 0 0 0');
      // Note 2: an empty queue bangs the right outlet.
      for (var i = 0; i < 4; i++) {
        click(pop);
      }
      expect(value(took), 'took 0');
      click(pop);
      expect((value(took), value(now)), ('empty', 'empty'));
    });

    test('array.slice, subarray, split, wrap, concat, flatten, join, group, '
        'thin', () {
      open('array-slice-combine');
      click(at('.b', 60, 300));
      expect(value(at('.l', 60, 480)), 'slice 62 64 65');
      click(at('.b', 260, 300));
      expect(value(at('.l', 260, 480)), 'sub 67 65 64 62');
      click(at('.b', 480, 300));
      expect(value(at('.l', 480, 480)), 'head 60 62 64');
      expect(value(at('.l', 480, 540)), 'tail 65 67 69 71');
      // Right first: one list box on both outlets ends on the head.
      final (split, last) = probe('.array.split', 'scale 3');
      gateway.connect(
        inst,
        fromHandleId: split,
        outlet: 1,
        toHandleId: last,
        inlet: 0,
      );
      click(split);
      expect(value(last), '60 62 64');
      // Note 2.
      final wrap = at('.i', 60, 620);
      final wrapped = at('.i', 60, 740);
      for (final (pos, want) in [(7, '60'), (9, '64'), (-1, '71')]) {
        type(wrap, pos);
        expect(value(wrapped), want, reason: 'wrap $pos');
      }
      click(at('.b', 220, 620));
      expect(value(at('.l', 220, 740)), '60 62 64 65 67 69 71 36 43');
      click(at('.b', 500, 620));
      expect(value(at('.l', 500, 740)), '36 43 c4 e4 g4 36 43');
      // Note 3.
      click(at('.b', 60, 800));
      expect(value(at('.l', 60, 920)), 'c4-e4-g4');
      click(at('.b', 220, 800));
      expect(value(at('.l', 220, 980)), '| 60 60 60 | 64 64 | 67');
      // Note 4.
      click(at('.b', 500, 800));
      expect(value(at('.i', 660, 920)), '3');
      expect(value(at('.l', 500, 980)), '0 0.8 3');
      // The title note: only thin changed its array; an empty result bangs.
      expect(contents('scale'), '60 62 64 65 67 69 71');
      expect(contents('hits'), '60 64 60 67 64 60');
      final (empty, hit) = bangs('.array.slice', 'scale 9', 1);
      click(empty);
      expect(value(hit), 'hit');
    });

    test('array.map, filter, reduce, foreach, every, some, expr, iter, '
        'stream, tuplewise', () {
      open('array-functional');
      final expr = at('.l', 300, 400);
      final classes = at('.l', 420, 460);
      final semis = at('.l', 400, 520);
      final sum = at('.i', 300, 580);
      final every = at('.i', 300, 640);
      final some = at('.i', 300, 700);
      final pairs = at('.l', 340, 760);
      click(at('.b', 60, 220));
      expect(value(expr), '72 76 79');
      expect(contents('chord'), '60 64 67', reason: 'expr changes nothing');
      expect(value(classes), '0 4 7');
      expect(value(semis), '0 4 7');
      expect(value(sum), '191');
      expect(value(every), '1');
      expect(value(some), '0');
      expect(value(pairs), '72 64 55');
      // Note 3.
      click(at('.b', 300, 220));
      expect(contents('chord'), '67 71 74');
      expect(value(expr), '79 83 86');
      expect(value(classes), '7 11 2');
      expect(value(semis), '7 11 14');
      expect(value(sum), '212');
      expect(value(every), '1');
      expect(value(some), '1');
      expect(value(pairs), '79 71 62');
      // Note 4.
      click(at('.b', 560, 220));
      expect(value(at('.l', 560, 400)), '60 72 65');
      expect(contents('mel'), '60 72 65');
      // Note 5.
      final feed = at('.i', 580, 520);
      final missing = at('.i', 740, 640);
      final window = at('.l', 580, 700);
      for (final (v, short) in [(1, '3'), (2, '2'), (3, '1')]) {
        type(feed, v);
        expect(value(missing), short);
        expect(value(window), '', reason: 'no reference before it is full');
      }
      type(feed, 4);
      expect((value(missing), value(window)), ('0', '1 2 3 4'));
      type(feed, 5);
      expect(value(window), '2 3 4 5');
      // The title note: $i2 is the position.
      final (pos, positions) = probe('.array.expr', r'chord $i2 + 0');
      click(pos);
      expect(value(positions), '0 1 2');
    });

    test('array.sort, reverse, rotate, shuffle, scramble, random', () {
      const velOf = {64: 90, 60: 100, 67: 70, 62: 110, 65: 80};
      void expectPaired() {
        final notes = contents('row').split(' ').map(int.parse).toList();
        expect(notes.toSet(), velOf.keys.toSet(), reason: 'a reorder');
        expect(contents('vel'), [for (final n in notes) velOf[n]].join(' '));
      }

      open('array-order-random');
      final row = at('.l', 60, 480);
      final vel = at('.l', 300, 480);
      final order = at('.l', 560, 360);
      // Note 3: seed 5 shuffles the same way every time the tutorial opens.
      click(at('.b', 600, 220));
      final shuffled = value(row);
      final shuffleOrder = value(order);
      expectPaired();
      gateway.disposeInstance(inst);
      render(20);
      open('array-order-random');
      click(at('.b', 600, 220));
      expect((value(row), value(order)), (shuffled, shuffleOrder));
      gateway.disposeInstance(inst);
      render(20);
      open('array-order-random');
      // Note 1.
      click(at('.b', 60, 220));
      expect(value(row), '60 62 64 65 67');
      expect(value(order), '1 3 0 4 2');
      expect(value(vel), '100 110 90 80 70');
      click(at('.m', 120, 220));
      expect(value(row), '67 65 64 62 60');
      expect(value(vel), '70 80 90 110 100');
      // Note 3: scramble sends its order too.
      click(at('.b', 60, 560));
      expectPaired();
      // Note 2.
      click(at('.b', 60, 220));
      click(at('.b', 260, 220));
      expect(value(row), '67 65 64 62 60');
      final rotate = at('.i', 420, 220);
      type(rotate, 1);
      expect(value(row), '60 67 65 64 62');
      type(rotate, -1);
      type(rotate, -1);
      expect(value(row), '65 64 62 60 67');
      expect(value(vel), '100 110 90 80 70', reason: 'no order: vel stays');
      // Note 4.
      final pick = at('.i', 300, 680);
      final before = contents('row');
      for (var i = 0; i < 10; i++) {
        click(at('.b', 300, 560));
        expect(velOf.keys.map((n) => '$n'), contains(value(pick)));
      }
      expect(contents('row'), before, reason: 'random changes nothing');
      final (a, la) = probe('.array.random', 'row 7');
      final (b, lb) = probe('.array.random', 'row 7');
      final pa = gateway.createObject(inst, '.prepend', args: 'x');
      final pb = gateway.createObject(inst, '.prepend', args: 'x');
      gateway
        ..connect(inst, fromHandleId: a, outlet: 0, toHandleId: pa, inlet: 0)
        ..connect(inst, fromHandleId: pa, outlet: 0, toHandleId: la, inlet: 0)
        ..connect(inst, fromHandleId: b, outlet: 0, toHandleId: pb, inlet: 0)
        ..connect(inst, fromHandleId: pb, outlet: 0, toHandleId: lb, inlet: 0);
      for (var i = 0; i < 6; i++) {
        click(a);
        click(b);
        expect(value(la), value(lb), reason: 'a seed repeats the picks');
      }
      // The note: numbers before words, equal elements keep their order.
      fill('mix', 'b 7. a 3 7');
      click(gateway.createObject(inst, '.array.sort', args: 'mix'));
      expect(contents('mix'), '3 7. 7 a b');
    });

    test('array.max, min, mode, mean, median, stddev', () {
      open('array-stats');
      final all = at('.b', 60, 220);
      final mode = at('.i', 380, 460);
      final mean = at('.f', 60, 580);
      click(all);
      expect(value(at('.i', 60, 460)), '127');
      expect(value(at('.i', 220, 460)), '40');
      expect(value(mode), '64');
      expect(number(mean), closeTo(80.83, 0.005));
      expect(number(at('.f', 220, 580)), 77);
      expect(number(at('.f', 380, 580)), closeTo(28.33, 0.005));
      // Note 3.
      final push = at('.i', 200, 220);
      type(push, 127);
      expect(value(mode), '64', reason: 'a tie goes to the first');
      type(push, 127);
      expect(value(mode), '127');
      expect(number(mean), closeTo(92.375, 0.001));
      click(at('.m', 360, 220));
      click(all);
      expect(value(at('.l', 560, 640)), 'empty');
      // The title note: words are skipped, except by mode.
      fill('words', 'a a 3');
      final (max, maxOut) = probe('.array.max', 'words');
      final (top, topOut) = probe('.array.mode', 'words');
      final maxBox = gateway.createObject(inst, '.i');
      gateway.connect(
        inst,
        fromHandleId: max,
        outlet: 0,
        toHandleId: maxBox,
        inlet: 0,
      );
      click(max);
      click(top);
      expect((value(maxBox), value(topOut)), ('3', 'a'));
      expect(value(maxOut), '', reason: 'a bare int');
    });

    test('array.sect, union, unique, sub, compare, change, routepass', () {
      open('array-sets-compare');
      for (final (x, want) in [
        (60.0, '60 64'),
        (240.0, '60 64 67 57'),
        (440.0, '60 62 64'),
        (600.0, '64 60 62'),
      ]) {
        click(at('.b', x, 220));
        expect(value(at('.l', x, 340)), want, reason: 'at $x');
      }
      // Note 2.
      final check = at('.b', 60, 480);
      final equal = at('.i', 60, 680);
      final changed = at('.i', 280, 680);
      final routed = at('.l', 600, 760);
      click(check);
      expect(
        (value(equal), value(changed), value(routed)),
        ('1', '1', 'fifth'),
      );
      click(check);
      expect(value(changed), '0');
      // Note 3.
      type(at('.i', 200, 480), 70);
      expect(contents('chord'), '60 64 67 70');
      expect(
        (value(equal), value(changed), value(routed)),
        ('0', '1', 'seventh'),
      );
      click(at('.m', 380, 480));
      click(check);
      expect(value(routed), 'neither');
      // The title note: spelling and order.
      fill('ints', '60 64');
      fill('back', '64 60');
      fill('floats', '60. 64');
      final (cmp, _) = probe('.array.compare', 'ints back');
      final verdict = gateway.createObject(inst, '.i');
      gateway.connect(
        inst,
        fromHandleId: cmp,
        outlet: 0,
        toHandleId: verdict,
        inlet: 0,
      );
      gateway.sendInt(inst, verdict, 0, 5);
      click(cmp);
      expect(value(verdict), '0', reason: '60 64 is not 64 60');
      final (union, both) = probe('.array.union', 'ints floats');
      click(union);
      expect(value(both), '60 64 60.', reason: '60 and 60. differ');
    });

    test('array.tolist, tostring, tosymbol, deserialize, regexp', () {
      open('array-convert');
      click(at('.b', 60, 220));
      expect(value(at('.l', 60, 400)), 'kick 1 .wav');
      expect(value(at('.l', 260, 400)), 'kick 1 .wav');
      expect(value(at('.l', 480, 400)), 'kick1.wav');
      // tolist keeps 1 a number: array.index finds the int 1.
      final (find, _) = probe('.array.index', 'sample');
      final where = gateway.createObject(inst, '.i');
      gateway.connect(
        inst,
        fromHandleId: find,
        outlet: 0,
        toHandleId: where,
        inlet: 0,
      );
      type(find, 1);
      expect(value(where), '1');
      // Note 2.
      click(at('.b', 60, 480));
      expect(value(at('.i', 60, 660)), '7');
      expect(value(at('.l', 240, 660)), '7');
      // Note 3.
      final shown = at('.l', 440, 660);
      click(at('.m', 440, 480));
      renderUntil(() => value(shown) == '60 62.5 kick');
      expect(contents('loaded'), '60 62.5 kick');
      final (kind, _) = probe('.array.index', 'loaded');
      gateway.connect(
        inst,
        fromHandleId: kind,
        outlet: 0,
        toHandleId: where,
        inlet: 0,
      );
      type(kind, 62.5);
      expect(value(where), '1', reason: 'the float 62.5');
      type(kind, 60);
      expect(value(where), '0', reason: 'the int 60');
      mark(shown);
      click(at('.m', 620, 480));
      for (var i = 0; i < 20; i++) {
        render(2);
        sleep(const Duration(milliseconds: 2));
      }
      expect(value(shown), 'before', reason: 'no reference is sent');
      expect(contents('loaded'), '60 62.5 kick');
      // Note 4.
      click(at('.b', 60, 740));
      expect(value(at('.l', 60, 860)), 'c4 c5');
      click(at('.b', 300, 740));
      expect(value(at('.l', 300, 860)), 'e4 snare');
      final (none, hit) = bangs('.array.regexp', 'names x', 1);
      click(none);
      expect(value(hit), 'hit');
    });
  });

  test('every MIDI input type has a tutorial (#508)', () {
    for (final type in midiInputTypes) {
      expect(engineTypes, contains(type), reason: type);
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  // The MIDI input objects listen to a real input port, and the engine has no
  // call that injects a message into one. So these tests play MIDI the way a
  // keyboard does, through a loopback port (see MidiLoopback); on a machine
  // without one (Windows, CI runners) the keyboard steps are skipped.
  group('MIDI input tutorials (#508) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;
    MidiLoopback? loop;

    setUpAll(() => loop = MidiLoopback.open());
    tearDownAll(() => loop?.close());

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Every tutorial is mounted while open (#528), and a MIDI input object
    // only drains its port in a mounted patch's audio blocks. The tutorials
    // listen on port 0; on a machine whose loopback is another port, the
    // copy opened here listens there instead.
    void open(String slug) {
      final dump = load(slug).payload.dump;
      final port = loop?.inputPort ?? 0;
      for (final o in dump.values.cast<Map<String, Object?>>()) {
        if (!midiInputTypes.contains(o['type'])) continue;
        if (o['type'] == '.midiparse') continue;
        final args = (o['parms']! as String).split(' ');
        o['parms'] = ['$port', ...args.skip(1)].join(' ');
      }
      inst = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(inst, jsonEncode(dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: 'mounted');
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
    int msg(String text) => graph.objects
        .singleWhere((o) => o.type == '.m' && o.args == text)
        .handleId;
    String value(int id) {
      render(3);
      return gateway.guiValue(inst, id);
    }

    void click(int id) => gateway.sendBang(inst, id, 0);

    // The loudest master peak over [blocks] blocks.
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

    // Whether this machine can play MIDI into a patch; marks the test
    // skipped when it cannot.
    bool keyboard() {
      if (loop != null) return true;
      markTestSkipped('no MIDI loopback port on this machine');
      return false;
    }

    // Plays [bytes] into the loopback, then renders with real pauses until
    // the box [id] shows [expected]: a message reaches the patch in
    // wall-clock time, on a block after it arrived.
    void play(List<int> bytes, int id, String expected) {
      loop!.send(bytes);
      for (var i = 0; i < 2000 && gateway.guiValue(inst, id) != expected; i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.guiValue(inst, id), expected, reason: '$bytes');
    }

    test('midiin-midiparse: bytes by hand, running status', () {
      open('midiin-midiparse');
      final note = at('.l', 60, 510);
      final channel = at('.i', 360, 580);
      // Note 2.
      for (final m in ['144', '60', '100']) {
        click(msg(m));
      }
      expect(value(note), '60 100');
      expect(value(channel), '1');
      // Note 3.
      click(msg('60'));
      click(msg('0'));
      expect(value(note), '60 0', reason: 'running status: a release');
    });

    test('midiin-midiparse: a port, raw and parsed', () {
      if (!keyboard()) return;
      open('midiin-midiparse');
      final byte = at('.i', 60, 290);
      final framed = at('.l', 300, 290);
      final note = at('.l', 60, 510);
      // Note 1.
      play([144, 60, 100], framed, '144 60 100');
      expect(value(byte), '100', reason: 'the last byte');
      expect(value(note), '60 100');
      play([128, 60, 40], framed, '128 60 40');
      expect(value(note), '60 0', reason: 'a note-off reports velocity 0');
      play([144, 62, 0], framed, '144 62 0');
      expect(value(note), '62 0');
      // Note 4: every outlet.
      play([176, 1, 64], at('.l', 320, 510), '1 64');
      play([192, 4], at('.i', 60, 580), '5');
      play([208, 90], at('.i', 160, 580), '90');
      play([224, 0, 80], at('.i', 260, 580), '80');
      play([161, 60, 70], at('.l', 190, 510), '60 70');
      expect(value(at('.i', 360, 580)), '2');
      final raw = at('.l', 460, 580);
      play([240, 67, 16, 1, 2, 247], raw, '240 67 16 1 2 247');
      expect(value(framed), '240 67 16 1 2 247');
      play([248], raw, '248');
    });

    test('notein: a saw from the keyboard, channel 10, release velocity', () {
      if (!keyboard()) return;
      open('notein');
      final pitch = at('.i', 60, 310);
      final velocity = at('.i', 160, 310);
      final channel = at('.i', 260, 310);
      final release = at('.i', 260, 750);
      expect(loudness(), 0, reason: 'silent until a key is played');
      // Note 1.
      play([144, 60, 100], pitch, '60');
      expect((value(velocity), value(channel)), ('100', '1'));
      expect(loudness(), greaterThan(0.05), reason: 'the saw sounds');
      play([128, 60, 33], velocity, '0');
      loudness(20);
      expect(loudness(), lessThan(1e-3), reason: 'the release silences it');
      // Note 3.
      expect(value(release), '33');
      expect(value(at('.i', 160, 750)), '0');
      play([144, 62, 90], at('.i', 60, 750), '62');
      expect(value(release), '0', reason: 'a note-on has none');
      play([144, 62, 0], velocity, '0');
      expect(value(release), '0', reason: 'nor a note-on with velocity 0');
      // Note 2.
      final drum = at('.i', 380, 310);
      final drumChannel = at('.i', 480, 310);
      play([153, 36, 90], drum, '36');
      expect(value(drumChannel), '10');
      expect(value(channel), '10', reason: 'notein 0 hears every channel');
      play([145, 64, 90], pitch, '64');
      expect(value(drum), '36', reason: 'channel 2 passes notein 0 10 by');
      play([129, 64, 0], velocity, '0');
    });

    test('ctlin: every controller, two filters into scale, 14 bits', () {
      if (!keyboard()) return;
      open('ctlin');
      final v = at('.i', 60, 310);
      final cutoff = at('.f', 60, 510);
      final level = at('.f', 240, 510);
      final fine = at('.i', 60, 770);
      // Note 1.
      play([177, 74, 20], v, '20');
      expect(value(at('.i', 160, 310)), '74');
      expect(value(at('.i', 260, 310)), '2');
      // Note 2.
      play([176, 1, 64], v, '64');
      expect(double.parse(value(cutoff)), closeTo(200 + 64 / 127 * 3800, 0.01));
      expect(loudness(), 0, reason: 'silent until the volume moves');
      play([176, 7, 127], v, '127');
      expect(double.parse(value(level)), closeTo(0.2, 1e-6));
      expect(loudness(), greaterThan(0.05));
      play([176, 74, 10], v, '10');
      expect(
        double.parse(value(cutoff)),
        closeTo(200 + 64 / 127 * 3800, 0.01),
        reason: 'ctlin 0 0 1 hears controller 1 only',
      );
      // Note 3.
      expect(value(fine), '8192', reason: 'coarse 64 alone');
      play([176, 33, 100], fine, '8292');
      play([176, 7, 0], v, '0');
      expect(value(fine), '8292', reason: 'controller 7 is not its pair');
      loudness(20);
      expect(loudness(), lessThan(1e-3));
    });

    test('bendin-touchin: 7 and 14 bits, two bytes, pressure', () {
      if (!keyboard()) return;
      open('bendin-touchin');
      final bend = at('.i', 60, 290);
      final wide = at('.i', 300, 290);
      final semitones = at('.f', 300, 410);
      final msb = at('.i', 60, 430);
      final lsb = at('.i', 160, 430);
      // Notes 1 and 2.
      play([225, 0, 64], wide, '8192');
      expect((value(bend), value(at('.i', 160, 290))), ('64', '2'));
      expect(value(at('.i', 400, 290)), '2');
      expect(double.parse(value(semitones)), 0);
      expect((value(msb), value(lsb)), ('64', '0'));
      play([224, 127, 127], wide, '16383');
      expect(value(bend), '127');
      expect(double.parse(value(semitones)), closeTo(2, 0.001));
      expect((value(msb), value(lsb)), ('127', '127'));
      play([224, 5, 32], wide, '4101');
      expect((value(bend), value(msb), value(lsb)), ('32', '32', '5'));
      // Note 3.
      play([209, 77], at('.i', 60, 570), '77');
      expect(value(at('.i', 160, 570)), '2');
      play([160, 60, 55], at('.i', 400, 570), '55');
      expect(value(at('.i', 300, 570)), '60');
      expect(value(at('.i', 500, 570)), '1');
    });

    test('pgmin-rtin-sysexin: presets, SysEx, clock', () {
      if (!keyboard()) return;
      open('pgmin-rtin-sysexin');
      final program = at('.i', 60, 290);
      final tempo = at('.i', 160, 470);
      final cutoff = at('.i', 260, 470);
      final recalled = at('.i', 60, 470);
      // Note 1.
      play([192, 1], recalled, '1');
      expect((value(tempo), value(cutoff)), ('120', '1600'));
      expect(value(program), '2');
      expect(value(at('.i', 160, 290)), '1');
      play([193, 3], recalled, '3');
      expect((value(tempo), value(cutoff)), ('174', '6400'));
      expect(value(at('.i', 160, 290)), '2');
      play([192, 4], program, '5');
      // A recall is handed to the engine's timer thread: give one time to
      // land, measured in wall-clock time.
      for (var i = 0; i < 100; i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect((value(tempo), value(cutoff)), ('174', '6400'));
      expect(value(recalled), '3', reason: 'slot 4 does not exist');
      play([192, 0], recalled, '0');
      expect((value(tempo), value(cutoff)), ('90', '800'));
      // Note 2.
      final dump = at('.l', 360, 470);
      play([240, 67, 16, 1, 2, 247], dump, '240 67 16 1 2 247');
      play([240, 125, 1, 247], dump, '240 125 1 247');
      // Note 3.
      final status = at('.i', 60, 620);
      final running = at('.t', 390, 740);
      final ticks = at('.i', 160, 740);
      final beats = at('.i', 160, 860);
      play([250], status, '250');
      expect(value(running), 'on');
      for (var i = 0; i < 47; i++) {
        loop!.send([248]);
      }
      play([248], ticks, '48');
      expect(value(beats), '2');
      play([252], status, '252');
      expect(value(running), 'off');
      // Note 4.
      play([251], status, '251');
      expect(value(running), 'off');
      play([248], ticks, '49');
      play([250], status, '250');
      play([248], ticks, '1');
    });

    test('rpnin-nrpnin: coarse and fine, parameter numbers', () {
      if (!keyboard()) return;
      open('rpnin-nrpnin');
      final rv = at('.i', 60, 270);
      final coarse = at('.i', 60, 390);
      final fine = at('.i', 160, 390);
      // Notes 1 and 2.
      loop!
        ..send([176, 101, 0])
        ..send([176, 100, 0]);
      play([176, 6, 12], rv, '1536');
      expect((value(coarse), value(fine)), ('12', '0'));
      expect(value(at('.i', 160, 270)), '0');
      expect(value(at('.i', 260, 270)), '1');
      play([176, 38, 50], rv, '1586');
      expect((value(coarse), value(fine)), ('12', '50'));
      // Note 3.
      final nv = at('.i', 60, 530);
      loop!
        ..send([177, 99, 1])
        ..send([177, 98, 8]);
      play([177, 6, 64], nv, '8192');
      expect(value(at('.i', 160, 530)), '136');
      expect(value(at('.i', 260, 530)), '2');
      expect(value(rv), '1586', reason: 'an NRPN is not an RPN');
    });

    test('midiinfo: inputs, outputs, refresh', () {
      open('midiinfo');
      final count = at('.i', 300, 370);
      final last = at('.l', 60, 430);
      final system = System.instance;
      String lastOf(int n, String Function(int) name) {
        final full = '${n - 1} ${name(n - 1)}';
        return full.length > 66 ? full.substring(0, 66) : full;
      }

      // Note 1.
      click(at('.b', 60, 230));
      final inputs = system.midiInDeviceCount;
      expect(value(count), '$inputs');
      if (inputs > 0) {
        expect(value(last), lastOf(inputs, system.midiInDeviceName));
      }
      // Note 2.
      click(msg('output'));
      expect(value(count), '$inputs', reason: 'output only switches');
      click(at('.b', 60, 230));
      final outputs = system.midiOutDeviceCount;
      expect(value(count), '$outputs');
      if (outputs > 0) {
        expect(value(last), lastOf(outputs, system.midiOutDeviceName));
      }
      click(msg('input'));
      click(at('.b', 60, 230));
      expect(value(count), '$inputs');
      // Note 3.
      gateway.sendList(inst, last, 0, 'before');
      click(msg('refresh'));
      for (
        var i = 0;
        i < 2000 && gateway.guiValue(inst, last) == 'before';
        i++
      ) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      if (inputs > 0) {
        expect(value(last), lastOf(inputs, system.midiInDeviceName));
      }
    });
  });

  test('every MIDI output type has a tutorial (#509)', () {
    for (final type in midiOutputTypes) {
      expect(engineTypes, contains(type), reason: type);
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
  });

  // The MIDI output tutorials send through a .midiout on port 0 and watch what
  // comes back on input port 0 with .xmidiin. Here both are pointed at the
  // loopback (see MidiLoopback), and a MidiCapture on its input reads every
  // byte the tutorial put on the wire. On a machine without one (Windows, CI
  // runners) only what the patch shows without a port is checked.
  group('MIDI output tutorials (#509) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;
    MidiLoopback? loop;
    MidiCapture? wire;

    setUpAll(() {
      loop = MidiLoopback.open();
      wire = loop?.capture();
    });
    tearDownAll(() async {
      await wire?.close();
      loop?.close();
    });

    void render(int blocks) {
      for (var i = 0; i < blocks; i++) {
        System.instance
          ..renderOffline(1)
          ..update();
      }
    }

    // Renders with real pauses: a .midiout opens its port on a background
    // thread, a message reaches the wire from the sender thread, and what
    // comes back is posted to this isolate's event loop.
    Future<void> pause([int ms = 20]) async {
      for (var i = 0; i < ms; i++) {
        render(1);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    // Opens [slug] mounted, its .midiout and .xmidiin on the loopback, and
    // waits for the port its loadbang asked for.
    Future<void> open(String slug) async {
      final dump = load(slug).payload.dump;
      for (final o in dump.values.cast<Map<String, Object?>>()) {
        if (o['type'] == '.midiout') o['parms'] = '${loop?.outputPort ?? 0}';
        if (o['type'] == '.xmidiin') o['parms'] = '${loop?.inputPort ?? 0}';
      }
      inst = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(inst, jsonEncode(dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        render(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: 'mounted');
      await pause(100);
      expect(wire?.messages ?? [], isEmpty, reason: 'allnotesoff is lost');
    }

    tearDown(() async {
      gateway.disposeInstance(inst);
      await pause();
      wire?.clear();
    });

    int at(String type, double x, double y) => graph.objects
        .firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        )
        .handleId;
    String value(int id) {
      render(3);
      return gateway.guiValue(inst, id);
    }

    void click(String type, double x, double y) =>
        gateway.sendBang(inst, at(type, x, y), 0);
    void m(double x, double y) => click('.m', x, y);

    // Waits for [expected] on the wire, checks it arrived exactly, and that
    // the tutorial's own monitor (.xmidiin into the list box at [box]) shows
    // the last message. Nothing is checked without a loopback.
    Future<void> sent(
      List<List<int>> expected, {
      int? box,
      bool ordered = true,
    }) async {
      final w = wire;
      if (w == null) return;
      for (var i = 0; i < 2000 && w.messages.length < expected.length; i++) {
        await pause(1);
      }
      await pause(5);
      expect(w.messages, ordered ? expected : unorderedEquals(expected));
      if (box != null) expect(value(box), expected.last.join(' '));
      w.clear();
    }

    test('noteon-noteoff: notes, a velocity of 0, channel 10, release '
        'velocity', () async {
      await open('noteon-noteoff');
      final back = at('.l', 60, 960);
      // Note 1.
      m(60, 230);
      expect(value(at('.i', 60, 290)), '100');
      m(60, 350);
      await sent([
        [144, 60, 100],
      ], box: back);
      m(170, 350);
      await sent([
        [144, 64, 100],
      ]);
      m(170, 230);
      m(60, 350);
      m(170, 350);
      await sent([
        [144, 60, 0],
        [144, 64, 0],
      ], box: back);
      // Note 2.
      m(60, 230);
      m(60, 490);
      await sent([
        [153, 36, 100],
      ], box: back);
      m(280, 490);
      m(390, 490);
      await sent([
        [128, 60, 40],
      ], box: back);
      // Note 3.
      m(60, 630);
      m(390, 630);
      await sent([
        [144, 67, 90],
      ]);
      m(170, 630);
      m(390, 630);
      await sent([
        [128, 67, 64],
      ]);
      m(280, 630);
      m(390, 630);
      await sent([
        [128, 67, 20],
      ], box: back);
      // Note 4: the box loadbang fed sends again by hand.
      m(300, 810);
      await sent([
        for (var ch = 0; ch < 16; ch++) [176 + ch, 123, 0],
      ]);
    });

    test('controlchange: a dial at 7 bits, the pedal, 14 bits in two '
        'messages', () async {
      await open('controlchange');
      final back = at('.l', 60, 970);
      // Note 1.
      m(170, 230);
      expect(value(at('.i', 60, 370)), '64');
      await sent([
        [176, 1, 64],
      ], box: back);
      m(280, 230);
      m(60, 230);
      await sent([
        [176, 1, 127],
        [176, 1, 0],
      ]);
      // Note 2.
      m(390, 370);
      m(500, 370);
      await sent([
        [176, 64, 127],
        [176, 64, 0],
      ], box: back);
      // Note 3.
      m(170, 510);
      expect(value(at('.i', 60, 650)), '8192');
      await sent([
        [176, 1, 64],
        [176, 33, 0],
      ], box: back);
      m(280, 510);
      await sent([
        [176, 1, 127],
        [176, 33, 127],
      ]);
    });

    test('programchange-pressure: two-byte messages, a key pressure', () async {
      await open('programchange-pressure');
      final back = at('.l', 60, 850);
      // Note 1.
      m(170, 250);
      await sent([
        [192, 5],
      ], box: back);
      m(60, 250);
      m(280, 250);
      await sent([
        [192, 0],
        [192, 40],
      ]);
      // Note 2.
      m(60, 390);
      m(170, 390);
      m(280, 390);
      await sent([
        [208, 30],
        [208, 90],
        [208, 0],
      ], box: back);
      // Note 3.
      m(60, 530);
      m(280, 530);
      await sent([
        [160, 60, 70],
      ], box: back);
      m(170, 530);
      m(280, 530);
      await sent([
        [160, 60, 0],
      ]);
    });

    test('bendout: 7 bits as the coarse byte, 14 from a dial, two '
        'bytes', () async {
      await open('bendout');
      final back = at('.l', 60, 990);
      // Note 1.
      m(280, 250);
      await sent([
        [224, 0, 127],
      ], box: back);
      m(60, 250);
      m(170, 250);
      await sent([
        [224, 0, 0],
        [224, 0, 64],
      ]);
      // Note 2.
      m(170, 390);
      expect(value(at('.i', 60, 530)), '8192');
      await sent([
        [224, 0, 64],
      ]);
      m(280, 390);
      m(60, 390);
      await sent([
        [224, 127, 127],
        [224, 0, 0],
      ]);
      // Note 3.
      m(60, 670);
      m(170, 670);
      await sent([
        [224, 100, 64],
      ], box: back);
    });

    test('rpnout-nrpnout: the bend range, the null parameter, an '
        'NRPN', () async {
      final lines = <String>[];
      final sub = Log.instance.messages.listen(lines.add);
      addTearDown(sub.cancel);
      await open('rpnout-nrpnout');
      final back = at('.l', 60, 790);
      // Note 1.
      m(60, 230);
      m(170, 230);
      final range = [
        [176, 101, 0],
        [176, 100, 0],
        [176, 6, 12],
        [176, 38, 0],
      ];
      await sent(range, box: back);
      if (wire != null) {
        // print back writes all four to the log.
        await pause(50);
        for (final b in range) {
          expect(lines, contains(endsWith('back: ${b.join(' ')}')));
        }
      }
      m(280, 230);
      await sent([
        [176, 101, 0],
        [176, 100, 0],
        [176, 6, 2],
        [176, 38, 0],
      ]);
      // Note 2.
      m(390, 230);
      m(280, 230);
      await sent([
        [176, 101, 127],
        [176, 100, 127],
        [176, 6, 2],
        [176, 38, 0],
      ]);
      // Note 3.
      m(60, 450);
      m(170, 450);
      await sent([
        [177, 99, 1],
        [177, 98, 8],
        [177, 6, 64],
        [177, 38, 0],
      ], box: back);
    });

    test('midiout-midiformat-sxformat: byte lists, readable messages, '
        'SysEx', () async {
      await open('midiout-midiformat-sxformat');
      final back = at('.l', 60, 1090);
      final raw = at('.l', 300, 290);
      final formatted = at('.l', 300, 490);
      final sysex = at('.l', 60, 830);
      // Note 1.
      m(60, 230);
      expect(value(raw), '144 60 100');
      m(170, 230);
      expect(value(raw), '128 60 100');
      await sent([
        [144, 60, 100],
        [128, 60, 100],
      ], box: back);
      // The title: a single number is not sent, a list is.
      final out = at('.midiout', 60, 950);
      gateway.sendInt(inst, out, 0, 248);
      gateway.sendList(inst, out, 0, '144 61 1');
      await sent([
        [144, 61, 1],
      ]);
      // Note 2.
      m(60, 370);
      expect(value(formatted), '144 60 100');
      m(170, 370);
      expect(value(formatted), '144 62 0');
      m(280, 370);
      expect(value(formatted), '176 64 0');
      m(390, 370);
      expect(value(formatted), '192 5');
      m(500, 370);
      expect(value(formatted), '192 5', reason: 'the channel only stores');
      m(60, 370);
      expect(value(formatted), '145 60 100');
      await sent([
        [144, 60, 100],
        [144, 62, 0],
        [176, 64, 0],
        [192, 5],
        [145, 60, 100],
      ], box: back);
      // Note 3.
      m(170, 570);
      m(60, 570);
      expect(value(sysex), '240 125 1 64 247');
      gateway.sendList(inst, at('.sxformat', 60, 630), 0, '3 4');
      expect(value(sysex), '240 125 3 4 247', reason: 'a list fills both');
      // Note 4.
      m(280, 570);
      m(390, 570);
      expect(value(sysex), '240 125 7 247');
      m(170, 710);
      m(60, 710);
      expect(value(sysex), '240 125 16 32 80 247');
      await sent([
        [240, 125, 1, 64, 247],
        [240, 125, 3, 4, 247],
        [240, 125, 7, 247],
        [240, 125, 16, 32, 80, 247],
      ], box: back);
    });

    test('midiflush-flush: pairs released, clear, messages released per '
        'channel', () async {
      await open('midiflush-flush');
      final back = at('.l', 60, 990);
      final pitch = at('.i', 60, 470);
      final velocity = at('.i', 160, 470);
      // Note 1.
      m(60, 230);
      m(60, 290);
      m(170, 290);
      m(280, 290);
      m(170, 230);
      m(170, 290);
      expect((value(pitch), value(velocity)), ('64', '0'));
      await sent([
        [144, 60, 100],
        [144, 64, 100],
        [144, 67, 100],
        [144, 64, 0],
      ]);
      click('.b', 60, 350);
      expect((value(pitch), value(velocity)), ('67', '0'));
      await sent([
        [144, 60, 0],
        [144, 67, 0],
      ], box: back);
      // Note 2.
      m(60, 230);
      m(60, 290);
      m(170, 350);
      click('.b', 60, 350);
      expect((value(pitch), value(velocity)), ('60', '100'));
      await sent([
        [144, 60, 100],
      ], box: back);
      // Note 3.
      m(60, 610);
      m(170, 610);
      click('.b', 300, 670);
      await sent([
        [144, 72, 100],
        [145, 48, 100],
        [128, 72, 0],
        [129, 48, 0],
      ], box: back);
      click('.b', 300, 670);
      await sent([]);
      // The title: closing the patch releases what is still sounding, flush
      // with a velocity of 0 through noteon, midiflush with a note-off.
      m(60, 230);
      m(60, 290);
      m(60, 610);
      await sent([
        [144, 60, 100],
        [144, 72, 100],
      ]);
      gateway.disposeInstance(inst);
      inst = gateway.createInstance(mainOutputs: 1);
      await sent([
        [144, 60, 0],
        [128, 72, 0],
      ], ordered: false);
    });
  });

  test('every MIDI processing type has a tutorial (#510)', () {
    for (final type in [
      '.makenote', '.stripnote', '.poly', '.sustain', '.borax', '.offer', //
      '.mpeconfig', '.mpeparse', '.mpeformat',
    ]) {
      expect(engineTypes, contains(type), reason: type);
      expect(index.hasTutorial(type), isTrue, reason: type);
    }
    expect(index.tutorialFor('.mpeconfig'), index.tutorialFor('.mpeparse'));
    expect(index.tutorialFor('.mpeconfig'), index.tutorialFor('.mpeformat'));
  });

  // The MIDI processing objects work on numbers, without a port. Their
  // tutorials play notes from message boxes and keyboards on a saw on master;
  // the MPE tutorial alone sends through a .midiout and reads input port 0,
  // which this copy points at the loopback (see MidiLoopback).
  group('MIDI processing tutorials (#510) do what their notes say', () {
    late int inst;
    late PatcherGraphSnapshot graph;
    MidiLoopback? loop;
    MidiCapture? wire;

    setUpAll(() {
      loop = MidiLoopback.open();
      wire = loop?.capture();
    });
    tearDownAll(() async {
      await wire?.close();
      loop?.close();
    });

    // One block is 128 frames at 48 kHz: about 2.67 ms of audio.
    const blockMs = 128 / 48;

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

    // [ms] milliseconds of audio time, which makenote's durations count.
    void audio(double ms) => loudness((ms / blockMs).ceil());

    // Renders with real pauses: a .midiout opens its port on a background
    // thread, and a message reaches the wire, and the patch, in wall-clock
    // time.
    Future<void> pause([int ms = 20]) async {
      for (var i = 0; i < ms; i++) {
        loudness(1);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    // Every tutorial is mounted while open (#528); so is this copy. A
    // .midiout and .midiin go to the loopback.
    void open(String slug) {
      final dump = load(slug).payload.dump;
      for (final o in dump.values.cast<Map<String, Object?>>()) {
        if (o['type'] == '.midiout') o['parms'] = '${loop?.outputPort ?? 0}';
        if (o['type'] == '.midiin') o['parms'] = '${loop?.inputPort ?? 0}';
      }
      inst = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(inst, jsonEncode(dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        loudness(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: '$slug mounted');
      loudness(20);
    }

    tearDown(() async {
      gateway.disposeInstance(inst);
      await pause();
      wire?.clear();
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
    void m(String text) => click(msg(text));
    String value(int id) => gateway.guiValue(inst, id);
    // A key of the keyboard [keys] pressed at [velocity], or let go at 0, the
    // way the canvas plays it.
    void key(int keys, int pitch, int velocity) =>
        gateway.setGuiValueAt(inst, keys, pitch, '$velocity');

    // Silence on master: a saw at velocity 1 is still louder than this.
    const silent = 1e-4;

    test('makenote: a metro line, durations, velocities, stop and '
        'clear', () {
      open('makenote');
      final pitch = at('.i', 60, 680);
      final velocity = at('.i', 170, 680);
      final toggle = at('.t', 60, 250);
      expect(loudness(), lessThan(silent), reason: 'quiet until played');
      // Note 1: the metro bangs at once; counter 1 -> 1 * 2 + 60.
      gateway.sendInt(inst, toggle, 0, 1);
      gateway.sendInt(inst, toggle, 0, 0);
      expect((value(pitch), value(velocity)), ('62', '100'));
      expect(loudness(10), greaterThan(0.01), reason: 'a saw on master');
      audio(150);
      expect(value(velocity), '100', reason: 'still sounding at 150 ms');
      audio(70);
      expect((value(pitch), value(velocity)), ('62', '0'), reason: '200 ms');
      expect(loudness(), lessThan(silent), reason: 'the release stops it');
      // Note 2: the right inlets set the notes that follow, and send nothing.
      m('50');
      m('40');
      expect((value(pitch), value(velocity)), ('62', '0'));
      m('67');
      expect((value(pitch), value(velocity)), ('67', '40'));
      audio(35);
      expect(value(velocity), '40');
      audio(25);
      expect(value(velocity), '0', reason: 'released after 50 ms');
      m('110');
      m('200');
      m('67');
      expect(value(velocity), '110');
      audio(220);
      expect(value(velocity), '0');
      // Note 3: two seconds, cut short by stop; clear forgets the release.
      m('2000');
      m('67');
      audio(1000);
      expect(value(velocity), '110', reason: 'two seconds long');
      m('stop');
      expect((value(pitch), value(velocity)), ('67', '0'), reason: 'stop');
      expect(loudness(), lessThan(silent));
      m('67');
      m('clear');
      audio(2200);
      expect(value(velocity), '110', reason: 'clear forgot the release');
      expect(loudness(), greaterThan(0.01), reason: 'the saw keeps sounding');
      m('50');
      m('67');
      audio(70);
      expect(value(velocity), '0', reason: "another note's release");
      expect(loudness(), lessThan(silent));
    });

    test('stripnote: two messages per key, one note-on, a list', () {
      open('stripnote');
      final keys = at('.kslider', 60, 250);
      final every = at('.i', 60, 550);
      final ons = at('.i', 200, 550);
      // Note 1.
      key(keys, 60, 100);
      expect((value(every), value(ons)), ('1', '1'));
      expect(loudness(10), greaterThan(0.01), reason: 'a saw on master');
      key(keys, 60, 0);
      expect((value(every), value(ons)), ('2', '1'), reason: 'one per key');
      // Note 2: the release never reaches the saw.
      expect(loudness(), greaterThan(0.01), reason: 'still sounding');
      key(keys, 64, 100);
      key(keys, 64, 0);
      expect((value(every), value(ons)), ('4', '2'));
      expect(loudness(), greaterThan(0.01));
      m('0');
      expect(loudness(), lessThan(silent), reason: '0 silences it');
      // Note 3: a list sets the velocity first.
      click(at('.b', 380, 250));
      expect(value(ons), '2', reason: 'pack 64 0 sends nothing on');
      expect(loudness(), lessThan(silent));
      click(at('.b', 500, 250));
      expect(value(ons), '3', reason: 'pack 64 90 plays');
      expect(loudness(), greaterThan(0.01));
    });

    test('poly: voices, overflow, stealing, releases and stop', () {
      open('poly');
      final voice = at('.i', 60, 440);
      final pitch = at('.i', 140, 440);
      final velocity = at('.i', 220, 440);
      final overflow = at('.l', 60, 500);
      final stealing = at('.l', 340, 500);
      (String, String, String) a() =>
          (value(voice), value(pitch), value(velocity));
      // Note 1.
      m('100');
      m('60');
      expect(a(), ('1', '60', '100'));
      expect(value(stealing), '1 60 100');
      expect(loudness(10), greaterThan(0.01), reason: 'a saw on master');
      m('64');
      expect(a(), ('2', '64', '100'));
      expect(value(stealing), '2 64 100');
      m('67');
      expect(a(), ('3', '67', '100'));
      expect(value(stealing), '3 67 100');
      expect(value(overflow), '');
      m('71');
      expect(value(overflow), '71 100', reason: 'no free voice');
      expect(a(), ('3', '67', '100'), reason: 'not tracked');
      // Note 2: poly 3 1 gave 71 the voice of 60, the oldest.
      expect(value(stealing), '1 71 100');
      expect(loudness(10), greaterThan(0.01));
      // Note 3.
      m('0');
      m('64');
      expect(a(), ('2', '64', '0'));
      expect(value(stealing), '2 64 0');
      m('71');
      expect(value(overflow), '71 0', reason: 'the release follows it');
      expect(a(), ('2', '64', '0'));
      expect(value(stealing), '1 71 0');
      expect(loudness(10), greaterThan(0.01), reason: '67 still sounds');
      m('stop');
      expect(a(), ('3', '67', '0'), reason: 'poly 3 releases 60, then 67');
      expect(value(stealing), '3 67 0');
      expect(loudness(), lessThan(silent), reason: 'every voice released');
    });

    test('poly: each voice plays its own saw', () {
      open('poly');
      m('100');
      for (final (p, v) in [('60', '1'), ('64', '2'), ('67', '3')]) {
        m(p);
        expect(value(at('.l', 340, 500)), '$v $p 100');
        expect(loudness(10), greaterThan(0.01), reason: 'voice $v');
        m('stop');
        expect(loudness(), lessThan(silent), reason: 'voice $v released');
        // Take the voices below it again, so the next note gets the next.
        m('60');
        if (v == '2') m('64');
      }
    });

    test('sustain: the pedal holds releases, lowest first, flush and '
        'clear', () async {
      open('sustain');
      final keys = at('.kslider', 60, 260);
      final pedal = at('.t', 380, 260);
      final pitch = at('.i', 60, 420);
      final velocity = at('.i', 170, 420);
      final lines = <String>[];
      final sub = Log.instance.messages.listen(lines.add);
      addTearDown(sub.cancel);
      // Note 1.
      key(keys, 60, 100);
      expect((value(pitch), value(velocity)), ('60', '100'));
      expect(loudness(10), greaterThan(0.01), reason: 'a saw on master');
      key(keys, 60, 0);
      expect(value(velocity), '0', reason: 'pedal up: the release passes');
      expect(loudness(), lessThan(silent));
      // Note 2.
      gateway.sendInt(inst, pedal, 0, 1);
      key(keys, 64, 100);
      key(keys, 64, 0);
      expect((value(pitch), value(velocity)), ('64', '100'), reason: 'held');
      expect(loudness(), greaterThan(0.01), reason: 'the saw sounds on');
      key(keys, 67, 100);
      key(keys, 67, 0);
      key(keys, 62, 100);
      key(keys, 62, 0);
      expect((value(pitch), value(velocity)), ('62', '100'));
      gateway.sendInt(inst, pedal, 0, 0);
      expect((value(pitch), value(velocity)), ('67', '0'), reason: 'last 67');
      expect(loudness(), lessThan(silent));
      const marker = 'end of sustain (#510)';
      Log.instance.sendMessage(marker);
      for (var i = 0; i < 2000 && !lines.any((l) => l.contains(marker)); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(
        [
          for (final l in lines)
            if (l.contains('sustain:')) l.substring(l.indexOf('sustain:')),
        ],
        [
          'sustain: 60 100',
          'sustain: 60 0',
          'sustain: 64 100',
          'sustain: 67 100',
          'sustain: 62 100',
          'sustain: 62 0',
          'sustain: 64 0',
          'sustain: 67 0',
        ],
        reason: 'lowest pitch first',
      );
      // Note 3.
      gateway.sendInt(inst, pedal, 0, 1);
      key(keys, 60, 100);
      key(keys, 60, 0);
      expect(value(velocity), '100');
      m('flush');
      expect((value(pitch), value(velocity)), ('60', '0'), reason: 'flush');
      key(keys, 64, 100);
      key(keys, 64, 0);
      expect(value(velocity), '100', reason: 'the pedal is still down');
      m('clear');
      expect(value(velocity), '100', reason: 'clear sends nothing');
      gateway.sendInt(inst, pedal, 0, 0);
      expect(value(velocity), '100', reason: 'nothing held any more');
      expect(loudness(), greaterThan(0.01), reason: 'the saw sounds on');
      key(keys, 65, 100);
      key(keys, 65, 0);
      expect(loudness(), lessThan(silent), reason: 'until another release');
    });

    test('borax: numbers, voices, durations, deltas and reset', () {
      open('borax');
      final keys = at('.kslider', 60, 340);
      int box(int outlet) {
        final (row, col) = (outlet ~/ 5, outlet % 5);
        return at(
          outlet == 6 || outlet == 8 ? '.f' : '.i',
          60.0 + 110 * col,
          550.0 + 60 * row,
        );
      }

      List<String> top() => [for (var i = 0; i < 5; i++) value(box(i))];
      double number(int outlet) => double.parse(value(box(outlet)));
      final clock = Stopwatch()..start();
      double now() => clock.elapsedMicroseconds / 1000;
      // Note 1.
      final pressed = now();
      key(keys, 60, 100);
      final pressedEnd = now();
      expect(top(), ['1', '1', '1', '60', '100']);
      expect(loudness(10), greaterThan(0.01), reason: 'a saw on master');
      sleep(const Duration(milliseconds: 120));
      final released = now();
      key(keys, 60, 0);
      final releasedEnd = now();
      expect(top(), ['1', '1', '0', '60', '0']);
      expect(value(box(5)), '1', reason: 'one note ended');
      expect(
        number(6),
        inInclusiveRange(released - pressedEnd - 5, releasedEnd - pressed + 5),
        reason: 'how long the key was held',
      );
      expect(value(box(7)), '0', reason: 'no delta yet');
      // Note 2.
      sleep(const Duration(milliseconds: 60));
      final second = now();
      key(keys, 64, 100);
      final secondEnd = now();
      expect(top(), ['2', '1', '1', '64', '100']);
      expect(value(box(7)), '1');
      expect(
        number(8),
        inInclusiveRange(second - pressedEnd - 5, secondEnd - pressed + 5),
        reason: 'the time since the previous press',
      );
      m('delta');
      expect(value(box(7)), '2', reason: 'delta reads it again');
      key(keys, 64, 0);
      // Note 3.
      m('60');
      m('64');
      m('67');
      expect(top(), ['5', '3', '3', '67', '100']);
      expect(
        [
          for (final p in [60, 64, 67]) gateway.guiValueAt(inst, keys, p),
        ],
        ['100', '100', '100'],
        reason: 'the keys stay down',
      );
      m('0');
      m('64');
      expect(top(), ['4', '2', '2', '64', '0'], reason: 'voice 2 ends');
      m('100');
      click(at('.b', 200, 430));
      expect(top(), [
        '5',
        '3',
        '0',
        '67',
        '0',
      ], reason: 'note-offs, voice order');
      expect(gateway.guiValueAt(inst, keys, 60), '100', reason: 'keys stay');
      key(keys, 72, 100);
      expect(top(), ['1', '1', '1', '72', '100'], reason: 'counting again');
    });

    test('offer: one-time pairs, one waiting y, a list, bang and clear', () {
      open('offer');
      final out = at('.i', 60, 490);
      // Note 1.
      m('72');
      m('60');
      expect(value(out), '0', reason: 'storing sends nothing');
      m('60');
      expect(value(out), '72');
      gateway.sendInt(inst, out, 1, 0);
      m('60');
      expect(value(out), '0', reason: 'the pair is gone');
      // Note 2.
      m('72');
      m('79');
      m('67');
      click(at('.b', 300, 320));
      // Note 3: the bang lists 79, then 76, and deletes nothing.
      click(at('.b', 60, 320));
      expect(value(out), '76');
      gateway.sendInt(inst, out, 1, 0);
      m('67');
      expect(value(out), '79', reason: '67 was paired with 79');
      gateway.sendInt(inst, out, 1, 0);
      m('clear');
      click(at('.b', 60, 320));
      expect(value(out), '0', reason: 'clear deleted 64,76');
    });

    test('mpe: a zone, two notes with their own bend, pressure and slide, '
        'read back with channel and role', () async {
      open('mpeconfig-mpeparse-mpeformat');
      await pause(100);
      expect(wire?.messages ?? [], isEmpty, reason: 'allnotesoff is lost');
      final config = at('.l', 60, 410);
      final built = at('.l', 60, 790);
      final note = at('.l', 60, 1070);
      int parsed(int i) => at('.i', 170.0 + 80 * i, 1070);
      final (bend, pressure, slide, channel, role) = (
        parsed(0),
        parsed(1),
        parsed(2),
        parsed(3),
        parsed(4),
      );
      Future<void> sent(List<List<int>> expected) async {
        final w = wire;
        if (w == null) return;
        for (var i = 0; i < 2000 && w.messages.length < expected.length; i++) {
          await pause(1);
        }
        await pause(5);
        expect(w.messages, expected);
        w.clear();
      }

      // What mpeparse shows once the last message is back.
      Future<void> back(int id, String expected) async {
        if (loop == null) return;
        for (var i = 0; i < 2000 && value(id) != expected; i++) {
          await pause(1);
        }
        expect(value(id), expected, reason: 'read back by mpeparse');
      }

      // Note 1.
      m('15');
      expect(value(config), '176 6 15');
      await sent([
        [176, 100, 6],
        [176, 101, 0],
        [176, 6, 15],
      ]);
      // Note 2.
      m('2');
      expect(value(built), '', reason: 'the channel only stores');
      click(at('.b', 60, 540));
      expect(value(built), '145 60 100');
      await sent([
        [145, 60, 100],
      ]);
      await back(note, '60 100');
      if (loop != null) expect((value(channel), value(role)), ('2', '1'));
      m('8363');
      expect(value(built), '225 43 65');
      await back(bend, '8363');
      m('90');
      expect(value(built), '209 90');
      await back(pressure, '90');
      m('30');
      expect(value(built), '177 74 30');
      await back(slide, '30');
      await sent([
        [225, 43, 65],
        [209, 90],
        [177, 74, 30],
      ]);
      m('3');
      click(at('.b', 280, 540));
      expect(value(built), '146 64 90');
      await back(note, '64 90');
      await back(channel, '3');
      m('8192');
      expect(value(built), '226 0 64');
      await back(bend, '8192');
      m('2');
      m('60');
      expect(value(built), '145 60 0', reason: 'a pitch alone releases');
      await back(note, '60 0');
      await back(channel, '2');
      await sent([
        [146, 64, 90],
        [226, 0, 64],
        [145, 60, 0],
      ]);
      // Note 1, on: 7 members leave channel 9 outside the zone, and the
      // master channel's role is 2.
      m('7');
      expect(value(config), '176 6 7');
      m('0');
      expect(value(config), '176 6 0', reason: '0 switches MPE off');
      m('7');
      await sent([
        [176, 100, 6],
        [176, 101, 0],
        [176, 6, 7],
        [176, 100, 6],
        [176, 101, 0],
        [176, 6, 0],
        [176, 100, 6],
        [176, 101, 0],
        [176, 6, 7],
      ]);
      final l = loop;
      if (l == null) return;
      l.send([152, 72, 80]);
      await back(note, '72 80');
      expect((value(channel), value(role)), ('9', '0'));
      l.send([136, 72, 0]);
      await back(note, '72 0');
      l.send([208, 50]);
      await back(pressure, '50');
      expect((value(channel), value(role)), ('1', '2'));
      l.send([149, 48, 70]);
      await back(note, '48 70');
      expect((value(channel), value(role)), ('6', '1'));
    });
  });

  test('the subpatch and its four boundary objects share one tutorial '
      '(#536)', () {
    for (final type in ['patcher', '.inlet', '.outlet', '~inlet', '~outlet']) {
      expect(index.tutorialFor(type), 'subpatch', reason: type);
    }
  });

  group('the subpatch tutorial (#536) does what its notes say', () {
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

    // Opened the way the app opens a tutorial: one main output, mounted on
    // master, measured once the sound is in the mix (#525).
    setUp(() {
      inst = gateway.createInstance(mainOutputs: 1);
      gateway.parseJson(inst, jsonEncode(load('subpatch').payload.dump));
      graph = gateway.enumerate(inst);
      gateway.mountAsSource(inst);
      for (var i = 0; i < 5000 && !gateway.isSourceReady(inst); i++) {
        loudness(1);
        sleep(const Duration(milliseconds: 1));
      }
      expect(gateway.isSourceReady(inst), isTrue, reason: 'mounted');
    });

    tearDown(() {
      gateway.disposeInstance(inst);
      loudness(20);
    });

    PatcherObjectSnapshot at(String type, double x, double y) =>
        graph.objects.firstWhere(
          (o) => o.type == type && o.position == Offset(x, y),
          orElse: () => throw StateError('no $type at ($x, $y)'),
        );
    int id(String type, double x, double y) => at(type, x, y).handleId;
    PatcherObjectSnapshot box() =>
        graph.objects.singleWhere((o) => o.type == 'patcher');
    void click(int id) => gateway.sendBang(inst, id, 0);
    // The level a mono sine reaches on master through [gain]: one channel,
    // centred, so each side 3 dB down.
    double through(double gain) => gain * math.sqrt1_2;

    test('the box: named gain, its pins the boundary objects inside', () {
      final gain = box();
      expect(gain.args, 'gain');
      expect(gain.container, isNull);
      final inside = {
        for (final o in graph.objects)
          if (o.container == gain.handleId && !PatchTypeName.isNote(o.type))
            '${o.type} ${o.args}',
      };
      expect(inside, {
        '~inlet 0',
        '.inlet 1',
        '~* 0',
        '~outlet 0',
        '.outlet 1',
      });
      expect(
        graph.objects.where(
          (o) => o.container == gain.handleId && PatchTypeName.isNote(o.type),
        ),
        hasLength(1),
        reason: 'a note inside, for the subpatch window',
      );
      // Notes 2 and 3: one numbering per side, the object sets the kind.
      expect(gain.ports.inputs, 2);
      expect(gain.ports.inputKinds, [
        PatchPortKind.audio,
        PatchPortKind.control,
      ]);
      expect(gain.ports.outputs, 2);
      expect(gain.ports.outputKinds, [
        PatchPortKind.audio,
        PatchPortKind.control,
      ]);
      // The inside: ~inlet → ~* → ~outlet, .inlet 1 to the gain and out.
      final ain = id('~inlet', 60, 60);
      final cin = id('.inlet', 200, 60);
      final mul = id('~*', 60, 140);
      final aout = id('~outlet', 60, 220);
      final cout = id('.outlet', 200, 220);
      final cords = {
        for (final c in graph.connections)
          (c.fromHandleId, c.outlet, c.toHandleId, c.inlet),
      };
      expect(
        cords,
        containsAll([
          (ain, 0, mul, 0),
          (cin, 0, mul, 1),
          (cin, 0, cout, 0),
          (mul, 0, aout, 0),
          // The parent's cords, recorded on the boundary objects.
          (id('~sine', 140, 160), 0, ain, 0),
          (id('.m', 60, 240), 0, ain, 0),
          (id('.f', 240, 220), 0, cin, 0),
          (aout, 0, id('~dac', 60, 420), 0),
          (cout, 0, id('.f', 200, 420), 0),
        ]),
      );
    });

    test('note 1: silent on open, the gain sets the level, comes back out', () {
      expect(loudness(), lessThan(1e-4), reason: '~* 0 inside');
      final shown = id('.f', 200, 420);
      click(id('.m', 350, 160)); // 0.1
      expect(loudness(200), closeTo(through(0.1), 1e-3));
      expect(double.parse(gateway.guiValue(inst, shown)), closeTo(0.1, 1e-6));
      click(id('.m', 460, 160)); // 0.2
      expect(loudness(200), closeTo(through(0.2), 1e-3));
      expect(double.parse(gateway.guiValue(inst, shown)), closeTo(0.2, 1e-6));
      // Typed into the f box.
      gateway.sendFloat(inst, id('.f', 240, 220), 0, 0.15);
      expect(loudness(200), closeTo(through(0.15), 1e-3));
      expect(double.parse(gateway.guiValue(inst, shown)), closeTo(0.15, 1e-6));
      click(id('.m', 240, 160)); // 0.
      loudness(20);
      expect(loudness(), lessThan(1e-4), reason: '0. turns it off');
      expect(double.parse(gateway.guiValue(inst, shown)), 0);
    });

    test('note 4: a message into the ~inlet is dropped; a number box cannot '
        'be wired there, a message box can', () {
      click(id('.m', 460, 160)); // 0.2
      final up = loudness(200);
      expect(up, closeTo(through(0.2), 1e-3));
      click(id('.m', 60, 240)); // 0. into the audio inlet
      loudness(20);
      expect(loudness(200), closeTo(up, 1e-4), reason: 'the sine plays on');
      // Without the sine, the message alone puts nothing on the signal.
      final sine = id('~sine', 140, 160);
      final ain = id('~inlet', 60, 60);
      gateway.disconnect(
        inst,
        fromHandleId: sine,
        outlet: 0,
        toHandleId: ain,
        inlet: 0,
      );
      loudness(20);
      click(id('.m', 60, 240));
      expect(loudness(200), lessThan(1e-4), reason: 'dropped');
      // The editor's drag-time check (PatcherController.canConnect).
      final types = {for (final d in gateway.objectTypes()) d.type: d};
      final accepts = types['~inlet']!.inlets.single.accepts;
      expect(
        patchPinsCompatible(types['.f']!.outlets.single.type, accepts),
        isFalse,
        reason: 'a number box',
      );
      expect(
        patchPinsCompatible(types['.m']!.outlets.single.type, accepts),
        isTrue,
        reason: 'a message box',
      );
    });
  });

  test('report: object types with no tutorial yet', () {
    final missing = [
      for (final t in engineTypes.toList()..sort())
        if (!index.hasTutorial(t)) t,
    ];
    // ignore: avoid_print
    print(
      'tutorials: ${index.types.length} of ${engineTypes.length} types '
      'covered; without one: ${missing.join(' ')}',
    );
  });
}
