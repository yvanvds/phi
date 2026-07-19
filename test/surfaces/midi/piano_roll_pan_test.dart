import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/clip_editor.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';
import 'package:phi/surfaces/midi/piano_roll_scrollbar.dart';
import 'package:phi/surfaces/midi/piano_roll_view.dart';

// A 400×240 area over a 4-bar 4/4 clip (16 beats) with a 16-lane pitch window,
// so the fit scale is 25 px/beat and 15 px/lane — matching the zoom tests.
const _bars = 4;
const _beatsPerBar = 4;
const _minPitch = 60;
const _maxPitch = 76;

// Zoomed 4× on both axes (100 px/beat, 60 px/lane) at the origin: only a
// quarter of the clip is on-screen, so both scrollbars have room to move.
const _zoomedView = PianoRollView(pixelsPerBeat: 100, laneHeight: 60);

MidiClip _clip(List<MidiNote> notes) => MidiClip(bars: _bars, notes: notes);

/// A parent that owns the session-local view exactly as [MidiViewport] does —
/// rebuilding the roll with each fresh view so pans and scrollbar drags are
/// visible to the next frame.
class _Harness extends StatefulWidget {
  const _Harness({required this.editor, this.initialView});

  final ClipEditor editor;
  final PianoRollView? initialView;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  PianoRollView? _view;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
  }

  PianoRollView? get view => _view;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 240,
          child: PianoRollEditor(
            editor: widget.editor,
            ghostNotes: const [],
            showGhost: false,
            bars: _bars,
            beatsPerBar: _beatsPerBar,
            minPitch: _minPitch,
            maxPitch: _maxPitch,
            view: _view,
            onViewChanged: (v) => setState(() => _view = v),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late ClipEditor editor;

  Future<_HarnessState> pump(
    WidgetTester tester, {
    PianoRollView? initialView,
  }) async {
    editor = ClipEditor(
      _clip(const []),
      minPitch: _minPitch,
      maxPitch: _maxPitch,
    );
    await tester.pumpWidget(_Harness(editor: editor, initialView: initialView));
    await tester.pump();
    return tester.state<_HarnessState>(find.byType(_Harness));
  }

  Finder scrollbar(Axis axis) =>
      find.byWidgetPredicate((w) => w is PianoRollScrollbar && w.axis == axis);

  group('scrollbars (issue #198)', () {
    testWidgets('the fitted (un-zoomed) roll shows no scrollbars', (
      tester,
    ) async {
      await pump(tester); // no view → fit-to-viewport
      expect(scrollbar(Axis.horizontal), findsNothing);
      expect(scrollbar(Axis.vertical), findsNothing);
    });

    testWidgets('the zoomed roll shows both scrollbars', (tester) async {
      await pump(tester, initialView: _zoomedView);
      expect(scrollbar(Axis.horizontal), findsOneWidget);
      expect(scrollbar(Axis.vertical), findsOneWidget);
    });

    testWidgets('dragging the horizontal thumb scrolls the view right', (
      tester,
    ) async {
      final state = await pump(tester, initialView: _zoomedView);
      expect(state.view!.scrollBeats, 0);

      // The thumb sits at the left of the bar (scroll 0); grab it and pull right.
      final bar = tester.getRect(scrollbar(Axis.horizontal));
      await tester.dragFrom(
        Offset(bar.left + 16, bar.center.dy),
        const Offset(90, 0),
      );
      await tester.pump();

      expect(state.view!.scrollBeats, greaterThan(0));
      // A horizontal drag leaves the vertical scroll untouched.
      expect(state.view!.scrollLanes, 0);
    });

    testWidgets('dragging the vertical thumb scrolls the view down', (
      tester,
    ) async {
      final state = await pump(tester, initialView: _zoomedView);
      expect(state.view!.scrollLanes, 0);

      final bar = tester.getRect(scrollbar(Axis.vertical));
      await tester.dragFrom(
        Offset(bar.center.dx, bar.top + 16),
        const Offset(0, 90),
      );
      await tester.pump();

      expect(state.view!.scrollLanes, greaterThan(0));
      expect(state.view!.scrollBeats, 0);
    });
  });

  group('middle-drag pan (issue #198)', () {
    testWidgets('a middle-drag pans the zoomed roll on both axes', (
      tester,
    ) async {
      final state = await pump(tester, initialView: _zoomedView);
      final roll = tester.getRect(find.byType(PianoRollEditor));

      // Middle-press over the body and drag up-left: the content follows the
      // pointer, so the leading-edge scroll grows on both axes.
      final gesture = await tester.startGesture(
        roll.center,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(const Offset(-60, -40));
      await gesture.up();
      await tester.pump();

      expect(state.view!.scrollBeats, greaterThan(0));
      expect(state.view!.scrollLanes, greaterThan(0));
    });

    testWidgets('a middle-drag on the un-zoomed roll is a no-op (nothing to '
        'pan)', (tester) async {
      final state = await pump(tester); // fitted: content fills the viewport

      final roll = tester.getRect(find.byType(PianoRollEditor));
      final gesture = await tester.startGesture(
        roll.center,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(const Offset(-60, -40));
      await gesture.up();
      await tester.pump();

      // The clamp pins a fitted view at the origin — no view is ever emitted.
      expect(state.view, isNull);
    });
  });
}
