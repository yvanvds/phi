import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/shell/project/dirty_indicator.dart';

void main() {
  testWidgets('shows the dot only while dirty', (tester) async {
    final dirty = ValueNotifier<bool>(false);
    addTearDown(dirty.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DirtyIndicator(isDirty: dirty)),
      ),
    );

    // Clean: no dot.
    expect(find.byTooltip('unsaved changes'), findsNothing);

    // Dirty: the dot appears.
    dirty.value = true;
    await tester.pump();
    expect(find.byTooltip('unsaved changes'), findsOneWidget);

    // Back to clean: it disappears again.
    dirty.value = false;
    await tester.pump();
    expect(find.byTooltip('unsaved changes'), findsNothing);
  });
}
