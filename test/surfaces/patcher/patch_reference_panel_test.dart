import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
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
    PatchObjectDescriptor? descriptor,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PatchReferencePanel(descriptor: descriptor)),
      ),
    );
  }

  testWidgets('empty state when nothing is selected', (tester) async {
    await pumpPanel(tester, null);

    expect(find.byKey(PatchReferencePanel.emptyKey), findsOneWidget);
  });

  testWidgets('renders a type\'s full engine metadata', (tester) async {
    await pumpPanel(tester, sine);

    // Header + description.
    expect(find.text('~sine'), findsOneWidget);
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
}
