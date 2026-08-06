import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';

/// The inline object box on its own (issues #358, #382): what it completes,
/// what each key does, what it refuses, and — the part that matters most for a
/// live instrument — that a refusal never costs the gesture. The last group
/// covers the same box opened *over an existing object*, where the name it
/// starts with is that object's own.
void main() {
  PatchObjectDescriptor desc(
    String type, {
    String description = '',
    bool isDsp = false,
    List<PatchParamDescriptor> params = const [],
  }) => PatchObjectDescriptor(
    type: type,
    description: description,
    category: PatchObjectCategory.generic,
    isDsp: isDsp,
    inlets: const [],
    outlets: const [],
    params: params,
  );

  final catalogue = <PatchObjectDescriptor>[
    desc(
      '~sine',
      description: 'sine oscillator',
      isDsp: true,
      params: const [
        PatchParamDescriptor(
          name: 'frequency',
          doc: 'initial frequency',
          defaultValue: '440',
          range: '0..20000',
        ),
      ],
    ),
    desc('~saw', description: 'sawtooth oscillator', isDsp: true),
    desc('.slider', description: 'horizontal slider'),
    desc('~dac', description: 'audio output', isDsp: true),
    // The collision issue #380 has to answer for: two objects, one bare name.
    // Neither description matches any query the other tests type. Both take an
    // operand, so an edit of one has something to retype (issue #382).
    desc(
      '.*',
      description: 'multiply',
      params: const [
        PatchParamDescriptor(
          name: 'operand',
          doc: 'right-hand side',
          defaultValue: '2',
          range: '',
        ),
      ],
    ),
    desc(
      '~*',
      description: 'multiply audio',
      isDsp: true,
      params: const [
        PatchParamDescriptor(
          name: 'operand',
          doc: 'right-hand side',
          defaultValue: '2',
          range: '',
        ),
      ],
    ),
    // The annotation object (issue #436): one free-text `text` parameter.
    desc(
      '.text',
      description: 'text label',
      params: const [
        PatchParamDescriptor(
          name: 'text',
          doc: 'label text',
          defaultValue: '',
          range: 'any string',
        ),
      ],
    ),
  ];

  PatchObjectDescriptor? created;
  String? createdArgs;
  var dismissed = 0;

  setUp(() {
    created = null;
    createdArgs = null;
    dismissed = 0;
  });

  /// Pump the box — creating by default, or **editing** [editing] when one is
  /// given, seeded with the line that object prints (issue #382).
  Future<void> pumpBox(
    WidgetTester tester, {
    PatchObjectDescriptor? editing,
    String initialText = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PatchInlineObjectBox(
              objectTypes: catalogue,
              editing: editing,
              initialText: initialText,
              onCommit: (d, a) {
                created = d;
                createdArgs = a;
              },
              onDismiss: () => dismissed++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(PatchInlineObjectBox.fieldKey), text);
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  String fieldText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(PatchInlineObjectBox.fieldKey))
      .controller!
      .text;

  Finder row(String type) => find.byKey(PatchInlineObjectBox.rowKey(type));

  testWidgets('opens focused and empty, offering the whole catalogue', (
    tester,
  ) async {
    await pumpBox(tester);

    final focus = tester
        .widget<TextField>(find.byKey(PatchInlineObjectBox.fieldKey))
        .focusNode!;
    expect(focus.hasPrimaryFocus, isTrue);
    expect(fieldText(tester), isEmpty);
    for (final d in catalogue) {
      expect(row(d.type), findsOneWidget);
    }
  });

  testWidgets('completion narrows on each keystroke', (tester) async {
    await pumpBox(tester);

    await type(tester, 's');
    expect(row('~sine'), findsOneWidget);
    expect(row('~saw'), findsOneWidget);
    expect(row('.slider'), findsOneWidget);
    expect(row('~dac'), findsNothing);

    await type(tester, 'si');
    expect(row('~sine'), findsOneWidget);
    expect(row('~saw'), findsNothing);
    expect(row('.slider'), findsNothing);
  });

  testWidgets('the `~`/`.` prefix is not something anyone has to type', (
    tester,
  ) async {
    await pumpBox(tester);
    await type(tester, 'sine');

    // `sine` reaches `~sine`: the prefix is part of the id, not of the name.
    expect(row('~sine'), findsOneWidget);
  });

  testWidgets('rows read bare, in the colour that says which domain', (
    tester,
  ) async {
    await pumpBox(tester);
    await type(tester, 'si');

    Text nameOf(String type) => tester.widget<Text>(
      find.descendant(of: row(type), matching: find.byType(Text)).first,
    );

    // The name only — the `~` and the leading dot are both gone (issue #380).
    expect(nameOf('~sine').data, 'sine');
    expect(find.text('~sine'), findsNothing);
    expect(nameOf('~sine').style!.color, const Color(0xFF6FD5FF)); // cool

    await type(tester, 'slider');
    expect(nameOf('.slider').data, 'slider');
    expect(nameOf('.slider').style!.color, const Color(0xFFC1C7CD)); // fg1
  });

  testWidgets('the description is completed against too', (tester) async {
    await pumpBox(tester);
    await type(tester, 'sawtooth');

    expect(row('~saw'), findsOneWidget);
  });

  testWidgets('Tab inserts the highlighted type, ready for arguments', (
    tester,
  ) async {
    await pumpBox(tester);
    await type(tester, 'sine');

    await press(tester, LogicalKeyboardKey.tab);

    // The full id, plus the space the arguments go after — Tab must not move
    // focus out of the box.
    expect(fieldText(tester), '~sine ');
    expect(created, isNull);
    final focus = tester
        .widget<TextField>(find.byKey(PatchInlineObjectBox.fieldKey))
        .focusNode!;
    expect(focus.hasPrimaryFocus, isTrue);
  });

  testWidgets('arrows move the highlight and Tab takes what they land on', (
    tester,
  ) async {
    await pumpBox(tester);
    await type(tester, 's');
    // Prefix matches first: ~sine, ~saw, .slider.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.tab);

    expect(fieldText(tester), '~saw ');

    await press(tester, LogicalKeyboardKey.enter);
    expect(created?.type, '~saw');
  });

  testWidgets('the highlight wraps at both ends', (tester) async {
    await pumpBox(tester);
    await type(tester, 's');

    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.tab);

    // Up from the top lands on the last match, so a short list is reachable
    // either way round.
    expect(fieldText(tester), '.slider ');
  });

  testWidgets('Enter instantiates the highlighted completion with the typed '
      'arguments', (tester) async {
    await pumpBox(tester);
    await type(tester, 'sine 220');

    await press(tester, LogicalKeyboardKey.enter);

    // The acceptance gesture: no Tab needed, the name resolves on its own.
    expect(created?.type, '~sine');
    expect(createdArgs, '220');
  });

  testWidgets('Enter with no arguments creates with the documented defaults', (
    tester,
  ) async {
    await pumpBox(tester);
    await type(tester, '~sine');

    await press(tester, LogicalKeyboardKey.enter);

    expect(created?.type, '~sine');
    expect(createdArgs, '440');
  });

  testWidgets('an exact type id beats the highlight', (tester) async {
    await pumpBox(tester);
    await type(tester, '~saw');
    // Move the highlight off the exact match; the typed name still wins.
    await press(tester, LogicalKeyboardKey.arrowDown);

    await press(tester, LogicalKeyboardKey.enter);

    expect(created?.type, '~saw');
  });

  group('a bare name two objects answer to is not guessed at (issue #380)', () {
    testWidgets('Enter refuses, names both candidates, and keeps the list', (
      tester,
    ) async {
      await pumpBox(tester);
      await type(tester, '*');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created, isNull);
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsOneWidget);
      // Named by their canonical ids — those are what you would type to skip
      // this question entirely.
      expect(find.text('pick one · .* or ~*'), findsOneWidget);
      // And both are still on screen, in the two colours that tell them apart.
      expect(row('.*'), findsOneWidget);
      expect(row('~*'), findsOneWidget);
    });

    testWidgets('a second Enter takes the highlighted one', (tester) async {
      await pumpBox(tester);
      await type(tester, '*');
      await press(tester, LogicalKeyboardKey.enter);

      await press(tester, LogicalKeyboardKey.enter);

      // The choice was visible before it was taken, which is the whole point.
      expect(created?.type, '.*');
    });

    testWidgets('an arrow picks the other one', (tester) async {
      await pumpBox(tester);
      await type(tester, '*');
      await press(tester, LogicalKeyboardKey.enter);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);

      expect(created?.type, '~*');
    });

    testWidgets('the prefixed id typed in full never asks', (tester) async {
      await pumpBox(tester);
      await type(tester, '~*');

      await press(tester, LogicalKeyboardKey.enter);

      // The canonical id stays exactly what it was: type it and get it.
      expect(created?.type, '~*');
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsNothing);
    });

    testWidgets('an unambiguous bare name still resolves straight through', (
      tester,
    ) async {
      await pumpBox(tester);
      await type(tester, 'saw');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created?.type, '~saw');
    });

    testWidgets('retyping the name asks again', (tester) async {
      await pumpBox(tester);
      await type(tester, '*');
      await press(tester, LogicalKeyboardKey.enter);
      expect(created, isNull);

      // A new name is a new question — the previous refusal must not licence
      // the next Enter.
      await type(tester, '* 2');
      await press(tester, LogicalKeyboardKey.enter);

      expect(created, isNull);
      expect(find.text('pick one · .* or ~*'), findsOneWidget);
    });
  });

  testWidgets('one Enter creates one object', (tester) async {
    await pumpBox(tester);
    await type(tester, 'sine');

    // A desktop field sees Enter twice — the key event and the platform's
    // submit action. The gesture is still one object.
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PatchInlineObjectBox(
              objectTypes: catalogue,
              onCommit: (_, _) => count++,
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await type(tester, 'sine');
    await press(tester, LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(count, 1);
  });

  group('a refusal keeps the box open for correction', () {
    testWidgets('an unknown name creates nothing and says so', (tester) async {
      await pumpBox(tester);
      await type(tester, 'zzzz');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created, isNull);
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsOneWidget);
      expect(find.text('unknown object · zzzz'), findsOneWidget);
      // Still there, still holding what was typed: a typo costs a keystroke,
      // not the whole gesture.
      expect(find.byKey(PatchInlineObjectBox.fieldKey), findsOneWidget);
      expect(fieldText(tester), 'zzzz');
    });

    testWidgets('correcting the name clears the refusal and creates', (
      tester,
    ) async {
      await pumpBox(tester);
      await type(tester, 'zzzz');
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsOneWidget);

      await type(tester, 'sine');
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsNothing);

      await press(tester, LogicalKeyboardKey.enter);
      expect(created?.type, '~sine');
    });

    testWidgets('arguments the type does not document are refused', (
      tester,
    ) async {
      await pumpBox(tester);
      await type(tester, '.slider 5');

      await press(tester, LogicalKeyboardKey.enter);

      // `.slider` registers no parameters and crashes if handed any.
      expect(created, isNull);
      expect(find.text('.slider takes no arguments'), findsOneWidget);
    });

    testWidgets('an out-of-range argument is refused', (tester) async {
      await pumpBox(tester);
      await type(tester, 'sine 99999');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created, isNull);
      expect(find.text('frequency must be in 0..20000'), findsOneWidget);
    });

    testWidgets('an empty box refuses rather than guessing', (tester) async {
      await pumpBox(tester);

      await press(tester, LogicalKeyboardKey.enter);

      expect(created, isNull);
      expect(find.text('type an object name'), findsOneWidget);
    });
  });

  testWidgets('Escape dismisses without creating anything', (tester) async {
    await pumpBox(tester);
    await type(tester, 'sine 220');

    await press(tester, LogicalKeyboardKey.escape);

    expect(dismissed, 1);
    expect(created, isNull);
  });

  testWidgets('clicking a completion row inserts it', (tester) async {
    await pumpBox(tester);
    await type(tester, 's');

    await tester.tap(row('.slider'));
    await tester.pump();

    // The palette stays the pointer route, but a row that is already on screen
    // should not have to be arrowed to.
    expect(fieldText(tester), '.slider ');
    expect(created, isNull);
  });

  group('the note takes free text (issue #436)', () {
    testWidgets('every word typed after the name survives the commit', (
      tester,
    ) async {
      await pumpBox(tester);
      await type(tester, 'text warm pad from here');

      await press(tester, LogicalKeyboardKey.enter);

      // The bug half of issue #436: the content is not positional arguments,
      // so nothing after the first space may be refused or dropped.
      expect(created?.type, '.text');
      expect(createdArgs, 'warm pad from here');
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsNothing);
    });

    testWidgets('editing a note re-commits its whole line of text', (
      tester,
    ) async {
      await pumpBox(
        tester,
        editing: catalogue.firstWhere((d) => d.type == '.text'),
        initialText: 'text warm pad',
      );
      await type(tester, 'text a longer note than before');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created?.type, '.text');
      expect(createdArgs, 'a longer note than before');
    });
  });

  group('editing an existing object in place (issue #382)', () {
    PatchObjectDescriptor typed(String type) =>
        catalogue.firstWhere((d) => d.type == type);

    Future<void> pumpEditing(WidgetTester tester, String type, String line) =>
        pumpBox(tester, editing: typed(type), initialText: line);

    testWidgets('opens holding the object\'s own line, selected', (
      tester,
    ) async {
      await pumpEditing(tester, '~sine', 'sine 440');

      final field = tester.widget<TextField>(
        find.byKey(PatchInlineObjectBox.fieldKey),
      );
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      expect(fieldText(tester), 'sine 440');
      // Selected, so typing replaces it — the Max habit, and the reason an
      // argument change is one gesture rather than a select-all first.
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 8),
      );
    });

    testWidgets('Enter commits the retyped arguments against the same type', (
      tester,
    ) async {
      await pumpEditing(tester, '~sine', 'sine 440');
      await type(tester, 'sine 220');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created?.type, '~sine');
      expect(createdArgs, '220');
    });

    testWidgets('the object\'s own bare name is not the ambiguous one', (
      tester,
    ) async {
      // `*` names two objects (issue #380) — but over a `~*` it names *this*
      // one, unchanged, so editing its argument must not ask which `*` it is.
      await pumpEditing(tester, '~*', '* 2');
      await type(tester, '* 4');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created?.type, '~*');
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsNothing);
    });

    testWidgets('an out-of-range argument is refused in place, box open', (
      tester,
    ) async {
      await pumpEditing(tester, '~sine', 'sine 440');
      await type(tester, 'sine 99999');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created, isNull);
      expect(find.text('frequency must be in 0..20000'), findsOneWidget);
      // Still open, still holding the typo: a bad argument costs a keystroke,
      // not the object.
      expect(fieldText(tester), 'sine 99999');
    });

    testWidgets('committing a different type commits that type (issue #383)', (
      tester,
    ) async {
      await pumpEditing(tester, '~sine', 'sine 440');
      await type(tester, 'saw');

      await press(tester, LogicalKeyboardKey.enter);

      // The retype the box used to refuse: the name resolves against the
      // catalogue like any other, and the host is handed the *new* type to
      // replace the object with. Nothing here knows that it is a retype.
      expect(created?.type, '~saw');
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsNothing);
    });

    testWidgets('a retype\'s arguments are checked against the new type', (
      tester,
    ) async {
      // `~saw` documents no parameters at all, so the operand that was legal a
      // moment ago is not — and the check runs before anything is replaced,
      // because the engine crashes on arguments an object never declared.
      await pumpEditing(tester, '~sine', 'sine 440');
      await type(tester, 'saw 220');

      await press(tester, LogicalKeyboardKey.enter);

      expect(created, isNull);
      expect(find.text('~saw takes no arguments'), findsOneWidget);
    });

    testWidgets('arrowing onto the other candidate retypes to it', (
      tester,
    ) async {
      await pumpEditing(tester, '.*', '* 2');
      // The name is unchanged, but the highlight has been moved off this
      // object's own row — so it is a question again, and the answer is the
      // other `*` (issue #380), which is a retype.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);

      expect(created?.type, '~*');
      expect(createdArgs, '2');
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsNothing);
    });

    testWidgets('Escape leaves the object exactly as it was', (tester) async {
      await pumpEditing(tester, '~sine', 'sine 440');
      await type(tester, 'sine 220');

      await press(tester, LogicalKeyboardKey.escape);

      expect(dismissed, 1);
      expect(created, isNull);
    });
  });
}
