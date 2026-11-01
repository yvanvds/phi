import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/tokens/phi_note_swatch.dart';
import 'package:phi/domain/patcher/keyboard_layout.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/surfaces/patcher/reference/patch_keyboard_settings.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';

void main() {
  // A fully-documented fake type: description, an inlet accepting two kinds
  // with a range, a typed outlet, and a creation parameter with a default.
  const sine = PatchObjectDescriptor(
    type: '~sine',
    description: 'sine oscillator',
    category: PatchObjectCategory.oscillator,
    isDsp: true,
    inlets: [
      PatchInletDescriptor(
        label: 'freq',
        doc: 'frequency in Hz',
        range: '0..20000',
        accepts: {PatchInletAccept.buffer, PatchInletAccept.float},
      ),
    ],
    outlets: [
      PatchOutletDescriptor(
        label: 'out',
        doc: 'signal',
        range: '',
        type: PatchOutletType.buffer,
      ),
    ],
    params: [
      PatchParamDescriptor(
        name: 'frequency',
        doc: 'initial frequency',
        defaultValue: '440',
        range: '0..20000',
      ),
    ],
  );

  Future<void> pumpPanel(
    WidgetTester tester,
    PatchObjectDescriptor? descriptor, {
    String? args,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatchReferencePanel(descriptor: descriptor, args: args),
        ),
      ),
    );
  }

  testWidgets('empty state when nothing is selected', (tester) async {
    await pumpPanel(tester, null);

    expect(find.byKey(PatchReferencePanel.emptyKey), findsOneWidget);
  });

  testWidgets('renders a type\'s full engine metadata', (tester) async {
    await pumpPanel(tester, sine);

    // Header + description. The heading keeps the **canonical** id, prefix and
    // all (issue #380): this is the reference, and the prefixed id is what you
    // type when a bare name is ambiguous.
    expect(find.text('~sine'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('~sine')).style!.color,
      const Color(0xFF6FD5FF), // PhiColors.cool — the same blue as the box
    );
    expect(find.text('sine oscillator'), findsOneWidget);
    expect(find.text('dsp'), findsOneWidget);

    // Section headers.
    expect(find.text('INLETS'), findsOneWidget);
    expect(find.text('OUTLETS'), findsOneWidget);
    expect(find.text('PARAMS'), findsOneWidget);

    // Inlet — label, doc, accepted kinds (enum-canonical order), range.
    expect(find.text('[0] freq'), findsOneWidget);
    expect(find.text('frequency in Hz'), findsOneWidget);
    expect(find.textContaining('accepts buffer, float'), findsOneWidget);
    expect(find.textContaining('range 0..20000'), findsWidgets);

    // Outlet — label, doc, data type.
    expect(find.text('[0] out'), findsOneWidget);
    expect(find.text('signal'), findsOneWidget);
    expect(find.textContaining('type buffer'), findsOneWidget);

    // Param — name, doc, default.
    expect(find.text('frequency'), findsOneWidget);
    expect(find.text('initial frequency'), findsOneWidget);
    expect(find.textContaining('default 440'), findsOneWidget);
  });

  testWidgets('omits sections a type does not declare', (tester) async {
    const bare = PatchObjectDescriptor(
      type: '.b',
      description: 'bang button',
      category: PatchObjectCategory.gui,
      isDsp: false,
      inlets: [],
      outlets: [],
      params: [],
    );
    await pumpPanel(tester, bare);

    expect(find.text('bang button'), findsOneWidget);
    expect(find.text('control'), findsOneWidget);
    expect(find.text('INLETS'), findsNothing);
    expect(find.text('OUTLETS'), findsNothing);
    expect(find.text('PARAMS'), findsNothing);
  });

  // ─── the selected node's current values (issue #356) ─────────────────────
  //
  // Documenting the *type* only ever answered "what can this be set to". With a
  // canvas node selected the panel also answers "what is it set to", so
  // selection alone tells the user where the object stands.

  group('current values', () {
    testWidgets('a palette tap documents the type and shows no values', (
      tester,
    ) async {
      await pumpPanel(tester, sine);

      expect(find.textContaining('default 440'), findsOneWidget);
      expect(
        find.byKey(PatchReferencePanel.valueKey('frequency')),
        findsNothing,
      );
    });

    testWidgets("a selected node's arguments are shown against each param", (
      tester,
    ) async {
      await pumpPanel(tester, sine, args: '660');

      expect(
        find.byKey(PatchReferencePanel.valueKey('frequency')),
        findsOneWidget,
      );
      expect(find.text('= 660'), findsOneWidget);
      // The documentation is still there — the value joins it, it does not
      // replace it.
      expect(find.textContaining('default 440'), findsOneWidget);
    });

    testWidgets('values line up positionally with the documented params', (
      tester,
    ) async {
      const two = PatchObjectDescriptor(
        type: '.line',
        description: 'ramp',
        category: PatchObjectCategory.math,
        isDsp: false,
        inlets: [],
        outlets: [],
        params: [
          PatchParamDescriptor(
            name: 'target',
            doc: '',
            defaultValue: '0',
            range: '',
          ),
          PatchParamDescriptor(
            name: 'time',
            doc: '',
            defaultValue: '100',
            range: '',
          ),
        ],
      );
      await pumpPanel(tester, two, args: '1  250');

      expect(find.text('= 1'), findsOneWidget);
      expect(find.text('= 250'), findsOneWidget);
    });

    testWidgets('a param the node carries no argument for shows no value', (
      tester,
    ) async {
      const two = PatchObjectDescriptor(
        type: '.line',
        description: 'ramp',
        category: PatchObjectCategory.math,
        isDsp: false,
        inlets: [],
        outlets: [],
        params: [
          PatchParamDescriptor(
            name: 'target',
            doc: '',
            defaultValue: '0',
            range: '',
          ),
          PatchParamDescriptor(
            name: 'time',
            doc: '',
            defaultValue: '100',
            range: '',
          ),
        ],
      );
      // Only the first parameter was supplied — the second is not invented from
      // the documented default, which would claim a value the node never set.
      await pumpPanel(tester, two, args: '1');

      expect(
        find.byKey(PatchReferencePanel.valueKey('target')),
        findsOneWidget,
      );
      expect(find.byKey(PatchReferencePanel.valueKey('time')), findsNothing);
    });

    testWidgets("the note's value is its whole text, not the first word "
        '(issue #436)', (tester) async {
      const note = PatchObjectDescriptor(
        type: '.text',
        description: 'text label',
        category: PatchObjectCategory.gui,
        isDsp: false,
        inlets: [],
        outlets: [],
        params: [
          PatchParamDescriptor(
            name: 'text',
            doc: 'label text',
            defaultValue: '',
            range: 'any string',
          ),
        ],
      );
      await pumpPanel(tester, note, args: 'warm pad from here');

      // Free text is one value — splitting it positionally would document a
      // note that reads `warm` as holding one word of its four.
      expect(find.byKey(PatchReferencePanel.valueKey('text')), findsOneWidget);
      expect(find.text('= warm pad from here'), findsOneWidget);
    });
  });

  group('note colour (issue #511)', () {
    const note = PatchObjectDescriptor(
      type: '.text',
      description: 'text label',
      category: PatchObjectCategory.gui,
      isDsp: false,
      inlets: [],
      outlets: [],
      params: [
        PatchParamDescriptor(
          name: 'text',
          doc: 'label text',
          defaultValue: '',
          range: 'any string',
        ),
      ],
    );

    Future<List<String>> pumpPicker(
      WidgetTester tester,
      PatchObjectDescriptor desc, {
      String current = '',
    }) async {
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatchReferencePanel(
              descriptor: desc,
              args: 'a note',
              noteColor: current,
              onNoteColor: picked.add,
            ),
          ),
        ),
      );
      return picked;
    }

    testWidgets('a selected note offers plain plus every swatch, and a tap '
        'reports the token name', (tester) async {
      final picked = await pumpPicker(tester, note);
      expect(find.text('COLOUR'), findsOneWidget);
      expect(find.byKey(PatchReferencePanel.noteColorKey('')), findsOneWidget);
      for (final s in PhiNoteSwatch.all) {
        expect(find.byKey(PatchReferencePanel.noteColorKey(s.name)), findsOne);
      }

      await tester.tap(
        find.byKey(PatchReferencePanel.noteColorKey('note-cyan')),
      );
      await tester.tap(find.byKey(PatchReferencePanel.noteColorKey('')));
      expect(picked, ['note-cyan', '']);
    });

    testWidgets('the current colour is the ringed chip', (tester) async {
      await pumpPicker(tester, note, current: 'note-amber');
      Color ringOf(String name) {
        final box = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byKey(PatchReferencePanel.noteColorKey(name)),
                matching: find.byType(Container),
              ),
            )
            .first;
        return (box.decoration! as BoxDecoration).border!.top.color;
      }

      bool ringed(String name) => ringOf(name) == PhiColors.fg0;
      expect(ringed('note-amber'), isTrue);
      expect(ringed(''), isFalse);
    });

    testWidgets('anything but a note, and a palette tap, has no colour row', (
      tester,
    ) async {
      await pumpPicker(tester, sine);
      expect(find.text('COLOUR'), findsNothing);

      await pumpPanel(tester, note);
      expect(find.text('COLOUR'), findsNothing);
    });
  });

  group('keyboard range and velocity (issue #515)', () {
    const kslider = PatchObjectDescriptor(
      type: '.kslider',
      description: 'piano keyboard',
      category: PatchObjectCategory.gui,
      isDsp: false,
      inlets: [],
      outlets: [],
      params: [],
    );

    final ranges = <KeyboardLayout>[];
    final velocities = <int?>[];

    Future<void> pumpKeyboard(
      WidgetTester tester,
      PatchObjectDescriptor desc, {
      KeyboardLayout? range,
      int? velocity,
    }) async {
      ranges.clear();
      velocities.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatchReferencePanel(
              descriptor: desc,
              args: '',
              keyboardRange:
                  range ??
                  KeyboardLayout(
                    KeyboardLayout.defaultLow,
                    KeyboardLayout.defaultHigh,
                  ),
              keyboardVelocity: velocity,
              onKeyboardRange: ranges.add,
              onKeyboardVelocity: velocities.add,
            ),
          ),
        ),
      );
    }

    Finder step(String name) => find.byKey(PatchKeyboardSettings.stepKey(name));

    testWidgets('a selected keyboard shows its range and steps it an octave '
        'at a time', (tester) async {
      await pumpKeyboard(tester, kslider);
      expect(find.text('KEYBOARD'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(PatchKeyboardSettings.rangeKey)).data,
        'C3 – C6',
      );

      await tester.tap(step('shift.up'));
      await tester.tap(step('low.down'));
      await tester.tap(step('high.down'));
      expect(
        [for (final r in ranges) (r.low, r.high)],
        [(60, 96), (36, 84), (48, 72)],
      );
    });

    testWidgets('a step off MIDI or below an octave does nothing', (
      tester,
    ) async {
      await pumpKeyboard(tester, kslider, range: KeyboardLayout(0, 11));
      await tester.tap(step('shift.down'));
      await tester.tap(step('low.down'));
      await tester.tap(step('low.up'));
      await tester.tap(step('high.down'));
      expect(ranges, isEmpty);
      await tester.tap(step('high.up'));
      expect(ranges.single.high, 23);
    });

    testWidgets('velocity switches between depth and a fixed value', (
      tester,
    ) async {
      await pumpKeyboard(tester, kslider);
      expect(find.byKey(PatchKeyboardSettings.velocityKey), findsNothing);
      await tester.tap(step('velocity.fixed'));
      expect(velocities, [PatchKeyboardSettings.initialVelocity]);

      await pumpKeyboard(tester, kslider, velocity: 120);
      expect(find.text('120'), findsOneWidget);
      await tester.tap(step('velocity.+10'));
      await tester.tap(step('velocity.-1'));
      await tester.tap(step('velocity.depth'));
      expect(velocities, [127, 119, null]);
    });

    testWidgets('anything but a keyboard has no keyboard rows', (tester) async {
      await pumpKeyboard(tester, sine);
      expect(find.text('KEYBOARD'), findsNothing);
    });
  });
}
