import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/custom_transform_registry.dart';
import 'package:phi/domain/midi/dsl_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/smf/smf_reader.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/code/code_editor_view.dart';
import 'package:re_editor/re_editor.dart';

import '../test/engine/test_doubles/fake_code_evaluator.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/midi/fake_midi_file_io.dart';

/// End-to-end custom-transform authoring through the real workstation (issue
/// #38), the registration-seam slice: the Python kernel is still a
/// `NoOpCodeEvaluator` in production, so a `FakeCodeEvaluator` stands in for
/// "running a block registers `def octave_up(notes)`". The rest is the real
/// app — real navigation between the Code and MIDI surfaces, the real chain
/// `+` menu, and the real SMF export path — proving that a transform authored
/// on one surface transforms the clip on the other.
List<DslNote> _octaveUp(List<DslNote> notes) =>
    notes.map((n) => n.copyWith(pitch: n.pitch + 12)).toList();

Map<double, int> _pitchCounts(Iterable<double> pitches) {
  final counts = <double, int>{};
  for (final p in pitches) {
    counts[p] = (counts[p] ?? 0) + 1;
  }
  return counts;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: a code-authored transform shifts the exported clip', (
    tester,
  ) async {
    final fakeIo = FakeMidiFileIo();
    final registry = CustomTransformRegistry();
    final evaluator = FakeCodeEvaluator(
      onEvaluate: (_) => registry.register(
        name: 'octave up',
        kind: MidiTransformKind.pitch,
        transform: _octaveUp,
      ),
    );
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        midiFileIo: fakeIo,
        codeEvaluator: evaluator,
        customTransformRegistry: registry,
      ),
    );
    await tester.pumpAndSettle();

    // 1. On the Code surface, run a block — the fake registers the transform.
    await tester.tap(railFor(SurfaceId.code));
    await tester.pumpAndSettle();
    Actions.invoke(
      tester.element(find.byType(CodeEditor)),
      const EvaluateBlockIntent(),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(evaluator.calls, isNotEmpty);
    expect(registry.contains('octave up'), isTrue);

    // 2. Move to MIDI and export the baseline (before adding the transform).
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    final before = const SmfReader().read(fakeIo.savedBytes!).notes;
    expect(before, isNotEmpty);

    // 3. Add the code-authored transform from the chain `+` menu.
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('octave up'));
    await tester.pumpAndSettle();

    // 4. Export again — every note is an octave higher, count-for-count.
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    final after = const SmfReader().read(fakeIo.savedBytes!).notes;

    expect(after.length, before.length);
    final beforeCounts = _pitchCounts(before.map((n) => n.pitch));
    final afterCounts = _pitchCounts(after.map((n) => n.pitch));
    for (final entry in beforeCounts.entries) {
      // Exported pitches are rounded to whole semitones; +12 is an exact shift.
      expect(afterCounts[entry.key + 12], entry.value);
    }

    session.dispose();
    await engine.dispose();
    registry.dispose();
    await evaluator.dispose();
  });
}
