import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/domain/shell_layout/drop_edge.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/layout/shell_layout_controller.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/midi_surface.dart';
import 'package:phi/surfaces/midi/midi_viewport.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the workstation refactor's core promise (issue #251,
/// design §2): a surface is **single-instance dockable content** — moving it
/// between panes re-parents its element, it never rebuilds. So its state (here
/// the MIDI note selection, plus the surface's own widget subtree) survives a
/// dock move.
///
/// Drives the real [PhiApp] over fakes (no `libyse.dll`, no GL), summons MIDI
/// through the real rail, selects notes, then performs a dock move through the
/// injected [ShellLayoutController] (the interactive drag lands in a later
/// slice) and asserts the surface came through intact.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('a MIDI selection survives a dock move to a new pane', (
    tester,
  ) async {
    // A wired MIDI gateway means PhiEngine builds its player, so the shell
    // sources the shared clip editor from engine.midi — the selection we set is
    // the one the surface renders.
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final layout = ShellLayoutController(); // seed: one pane, Mix open
    addTearDown(layout.dispose);

    // The app runs maximized, where a split leaves each pane large; size the
    // test view to match so a half-width pane still fits the surfaces (narrow-
    // pane surface responsiveness is a separate, filed concern).
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      PhiApp(engine: engine, session: session, layoutController: layout),
    );
    await tester.pumpAndSettle();

    // Boot is behaviour-neutral: one pane, Mix visible, MIDI closed.
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiViewport), findsNothing);
    expect(layout.layout.paneCount, 1);

    // Summon MIDI through the real rail — it opens in the (only) active pane.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    expect(find.byType(MidiViewport), findsOneWidget);
    expect(layout.focusedSurface, 'midi');

    // Select notes in the shared editor and capture the live surface element.
    engine.midi.editor.setSelection({0, 1});
    await tester.pumpAndSettle();
    expect(engine.midi.editor.selection, {0, 1});
    final surfaceBefore = tester.element(find.byType(MidiSurface));

    // Dock move: split MIDI out of the shared pane into a fresh one beside Mix.
    // (No drag UI yet — issue #252 — so drive the layout op directly.)
    layout.split('p1', SurfaceId.midi.name, DropEdge.right);
    await tester.pumpAndSettle();

    // The tree now has two panes with MIDI relocated…
    expect(layout.layout.paneCount, 2);
    expect(layout.layout.paneIdOf('midi'), isNot('p1'));
    // …both surfaces render side by side…
    expect(find.byType(MixSurface), findsOneWidget);
    expect(find.byType(MidiViewport), findsOneWidget);

    // …the selection came through the move untouched…
    expect(engine.midi.editor.selection, {0, 1});
    // …and it is the *same* surface element — re-parented, not rebuilt. This is
    // the invariant that fails if the surface loses its GlobalKey identity.
    final surfaceAfter = tester.element(find.byType(MidiSurface));
    expect(identical(surfaceBefore, surfaceAfter), isTrue);

    session.dispose();
    await engine.dispose();
  });
}
