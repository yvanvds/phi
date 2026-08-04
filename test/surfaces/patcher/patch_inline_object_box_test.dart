import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';

/// The inline object box on its own (issue #358): what it completes, what each
/// key does, what it refuses, and — the part that matters most for a live
/// instrument — that a refusal never costs the gesture.
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
  ];

  PatchObjectDescriptor? created;
  String? createdArgs;
  var dismissed = 0;

  setUp(() {
    created = null;
    createdArgs = null;
    dismissed = 0;
  });

  Future<void> pumpBox(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PatchInlineObjectBox(
              objectTypes: catalogue,
              onCreate: (d, a) {
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
              onCreate: (_, _) => count++,
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
}
