import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/transforms/conditional_muting_transform.dart';
import 'package:phi/domain/midi/transforms/note_comparison.dart';
import 'package:phi/domain/midi/transforms/note_condition.dart';
import 'package:phi/domain/midi/transforms/note_field.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/transform_chip.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end conditional-muting editing through the real workstation (#109).
///
/// Adding a `mute · if` chip from the real `+` menu, then opening its typed
/// predicate editor from the chip context menu and adding a condition — mute
/// notes softer than a threshold — must gate the engine's own live chain: the
/// transform is re-backed by a declarative [NoteCondition], so the edit is
/// inspectable, not a lost closure. Proves the catalogue's keep-all default
/// becomes meaningful through editing alone (the issue's "done when").
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: editing the mute · if chip gates the live chain', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Navigate to the MIDI surface (the engine owns the shared chain).
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    final chain = engine.midiOrNull!.chain;
    // The demo clip's notes as the chain interprets them, before any muting.
    final baseline = chain.output.length;
    expect(baseline, greaterThan(0));

    // Add a `mute · if` chip from the `+` catalogue menu. The struct section
    // sits below the menu's fold, so scroll the row into view before tapping.
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    final muteRow = find.text('mute · if');
    await tester.ensureVisible(muteRow);
    await tester.pumpAndSettle();
    await tester.tap(muteRow);
    await tester.pumpAndSettle();

    // The catalogue default is the empty keep-all condition: it mutes nothing,
    // so the chain output is untouched.
    final added = chain.transforms.last as ConditionalMutingTransform;
    expect(added.condition, isA<NoteConditionGroup>());
    expect(chain.output, hasLength(baseline));

    // Right-click the new chip and open its typed predicate editor.
    await tester.tap(
      find.widgetWithText(TransformChip, 'mute · if'),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('edit parameters…'));
    await tester.pumpAndSettle();

    // Add a condition — the default is `velocity < 0.5`. No demo note is that
    // soft, so nothing is muted yet: the model landed but hasn't bitten.
    await tester.tap(find.text('+ add condition'));
    await tester.pumpAndSettle();
    expect(chain.output, hasLength(baseline));

    // Raise the threshold to 0.6 so the softest notes are caught and muted.
    final valueField = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(valueField, '0.6');
    await tester.pump();

    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();

    // The live chain now drops the soft notes: fewer survive, and every
    // survivor sits at or above the threshold.
    expect(chain.output.length, lessThan(baseline));
    expect(chain.output.every((n) => n.velocity >= 0.6), isTrue);

    // The edit landed as a declarative, inspectable predicate — not a closure.
    final edited = chain.transforms.last as ConditionalMutingTransform;
    final group = edited.condition as NoteConditionGroup;
    final leaf = group.conditions.single as NoteFieldCondition;
    expect(leaf.field, NoteField.velocity);
    expect(leaf.comparison, NoteComparison.lessThan);
    expect(leaf.threshold, 0.6);

    session.dispose();
    await engine.dispose();
  });
}
