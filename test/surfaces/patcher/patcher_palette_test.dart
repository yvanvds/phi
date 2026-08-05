import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

void main() {
  // A realistic catalogue straight off the gateway: ~sine (oscillator/dsp),
  // .slider (gui/control), ~dac (i-o/dsp) — with the `patcher` subpatch type
  // filtered out by objectTypes(), design §10 decision 2.
  final catalogue = FakePatcherGateway().objectTypes();

  Future<PatchObjectDescriptor?> pumpPalette(
    WidgetTester tester, {
    PatchObjectDescriptor? selected,
  }) async {
    PatchObjectDescriptor? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatcherPalette(
            objectTypes: catalogue,
            selected: selected,
            onSelect: (d) => picked = d,
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('groups entries into PCategory sections', (tester) async {
    await pumpPalette(tester);

    expect(
      find.byKey(PatcherPalette.sectionKey(PatchObjectCategory.oscillator)),
      findsOneWidget,
    );
    expect(
      find.byKey(PatcherPalette.sectionKey(PatchObjectCategory.gui)),
      findsOneWidget,
    );
    expect(
      find.byKey(PatcherPalette.sectionKey(PatchObjectCategory.generic)),
      findsOneWidget,
    );
    // A category with no entries gets no header.
    expect(
      find.byKey(PatcherPalette.sectionKey(PatchObjectCategory.filter)),
      findsNothing,
    );
  });

  testWidgets('lists every catalogue entry and never the subpatch type', (
    tester,
  ) async {
    await pumpPalette(tester);

    expect(find.byKey(PatcherPalette.entryKey(Obj.dSine)), findsOneWidget);
    expect(find.byKey(PatcherPalette.entryKey(Obj.gSlider)), findsOneWidget);
    expect(find.byKey(PatcherPalette.entryKey(Obj.dDac)), findsOneWidget);
    expect(find.byKey(PatcherPalette.entryKey(Obj.patcher)), findsNothing);
  });

  testWidgets('search filters on name and description', (tester) async {
    await pumpPalette(tester);

    // Type id match.
    await tester.enterText(find.byKey(PatcherPalette.searchKey), 'sine');
    await tester.pump();
    expect(find.byKey(PatcherPalette.entryKey(Obj.dSine)), findsOneWidget);
    expect(find.byKey(PatcherPalette.entryKey(Obj.gSlider)), findsNothing);
    expect(find.byKey(PatcherPalette.entryKey(Obj.dDac)), findsNothing);

    // Description match ('horizontal slider') reaches the slider by its docs,
    // not its type id.
    await tester.enterText(find.byKey(PatcherPalette.searchKey), 'horizontal');
    await tester.pump();
    expect(find.byKey(PatcherPalette.entryKey(Obj.gSlider)), findsOneWidget);
    expect(find.byKey(PatcherPalette.entryKey(Obj.dSine)), findsNothing);

    // A query that matches nothing empties the list.
    await tester.enterText(find.byKey(PatcherPalette.searchKey), 'zzz');
    await tester.pump();
    expect(find.text('no objects match'), findsOneWidget);
  });

  testWidgets('entries read bare — no prefix, no dot (issue #380)', (
    tester,
  ) async {
    await pumpPalette(tester);

    expect(find.text('sine'), findsOneWidget);
    expect(find.text('slider'), findsOneWidget);
    expect(find.text('dac'), findsOneWidget);
    // The glyph is gone from the entry it used to lead...
    expect(find.text(Obj.dSine), findsNothing);
    expect(find.text(Obj.gSlider), findsNothing);
    // ...and so is the coloured dot that said the same thing a second time:
    // every entry is now exactly one Text and no decoration beside it.
    for (final type in [Obj.dSine, Obj.gSlider, Obj.dDac]) {
      expect(
        find.descendant(
          of: find.byKey(PatcherPalette.entryKey(type)),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('DSP objects are drawn in the cool accent, control in grey', (
    tester,
  ) async {
    await pumpPalette(tester);

    Color labelColor(String type) {
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(PatcherPalette.entryKey(type)),
          matching: find.byType(Text),
        ),
      );
      return text.style!.color!;
    }

    expect(labelColor(Obj.dSine), const Color(0xFF6FD5FF)); // PhiColors.cool
    expect(labelColor(Obj.gSlider), const Color(0xFFC1C7CD)); // PhiColors.fg1
  });

  testWidgets('the selected entry keeps its domain colour', (tester) async {
    // With the prefix and the dot gone, colour is the only thing left saying
    // DSP — brightening the selected row to `fg0` would erase it exactly when
    // the eye is on it.
    await pumpPalette(
      tester,
      selected: catalogue.firstWhere((d) => d.type == Obj.dSine),
    );

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(PatcherPalette.entryKey(Obj.dSine)),
        matching: find.byType(Text),
      ),
    );
    expect(text.style!.color, const Color(0xFF6FD5FF)); // PhiColors.cool
  });

  testWidgets('tapping an entry reports it as the selection', (tester) async {
    PatchObjectDescriptor? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatcherPalette(
            objectTypes: catalogue,
            selected: null,
            onSelect: (d) => picked = d,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(PatcherPalette.entryKey(Obj.dSine)));
    await tester.pump();

    expect(picked, isNotNull);
    expect(picked!.type, Obj.dSine);
  });
}
