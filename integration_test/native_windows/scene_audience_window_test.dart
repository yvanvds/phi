// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/flutter_scene_renderer.dart';
import 'package:phi/engine/bridge/flutter_scene_view.dart';
import 'package:phi/engine/bridge/scene_view_status.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../../test/engine/test_doubles/fake_midi_gateway.dart';
import '../../test/engine/test_doubles/fake_yse_gateway.dart';
import 'linux_window_pixels.dart';
import 'native_windows_test_binding.dart';

/// The Scene in a second **native** top-level window (issue #297) — the
/// shape of the projected audience view (vision §4).
///
/// The real [PhiApp] runs the workstation in the main window with the Scene
/// open on the production [FlutterSceneRenderer] (Flutter GPU, #455). A second
/// window over the same engine and isolate — a real `WindowController`, not
/// flutter_test's stand-in ([NativeWindowsTestBinding]) — mounts the same
/// renderer's view. It must:
/// - be a view the engine knows (frames reach a native window);
/// - draw every agent in its voice colour where the pick math puts it, at the
///   window's own size, in the Flutter layer **and**, on Linux, in the pixels
///   the window shows on the display;
/// - orbit from a drag inside the window;
/// - follow a resize of the window;
/// - keep showing the Scene while the main window moves to another surface.
void main() {
  NativeWindowsTestBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  const audienceKey = Key('audience-window-scene');
  final audienceViewport = find.descendant(
    of: find.byKey(audienceKey),
    matching: find.byKey(FlutterSceneView.viewportKey),
  );
  final mainViewport = find.descendant(
    of: find.byType(PhiApp),
    matching: find.byKey(FlutterSceneView.viewportKey),
  );

  /// Let the engine's async work (static resources, paced GPU frames, the
  /// native window mapping) land.
  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// The physical pixels per logical pixel of the view [viewport] is in.
  double pixelRatioOf(WidgetTester tester, Finder viewport) =>
      View.of(tester.element(viewport)).devicePixelRatio;

  /// The pixels of the view under [viewport], read from its layer at its
  /// view's pixel ratio.
  Future<(ByteData, int)> capture(WidgetTester tester, Finder viewport) async {
    final boundary = tester.renderObject(viewport) as RenderRepaintBoundary;
    final ratio = pixelRatioOf(tester, viewport);
    final image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: ratio),
    ))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    return (bytes, image.width);
  }

  /// The brightest of the pixels [colourAt] gives within [radius] of [at].
  Color brightestOf(
    int? Function(int x, int y) colourAt,
    Offset at, {
    int radius = 3,
  }) {
    var best = const Color(0x00000000);
    var bestSum = -1;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final c = colourAt(at.dx.round() + dx, at.dy.round() + dy);
        if (c == null) continue;
        final sum = ((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF);
        if (sum > bestSum) {
          bestSum = sum;
          best = Color(c);
        }
      }
    }
    return best;
  }

  int? Function(int, int) layerPixels((ByteData, int) frame) {
    final (bytes, width) = frame;
    final height = bytes.lengthInBytes ~/ (width * 4);
    return (x, y) {
      if (x < 0 || y < 0 || x >= width || y >= height) return null;
      final o = (y * width + x) * 4;
      return (bytes.getUint8(o + 3) << 24) |
          (bytes.getUint8(o) << 16) |
          (bytes.getUint8(o + 1) << 8) |
          bytes.getUint8(o + 2);
    };
  }

  /// Whether [actual] reads as [voice]: the same dominant hue, not grey.
  bool isVoice(Color actual, Color voice) {
    double d(double a, double b) => (a - b).abs();
    return d(actual.r, voice.r) + d(actual.g, voice.g) + d(actual.b, voice.b) <
        0.45;
  }

  const voices = [
    PhiColors.voice1,
    PhiColors.voice2,
    PhiColors.voice3,
    PhiColors.voice4,
    PhiColors.voice5,
  ];

  /// Every agent of [renderer] draws in its voice where it projects into a
  /// viewport of logical [size], in the physical pixels [colourAt] gives at
  /// [ratio].
  void expectAgentsDrawn(
    FlutterSceneRenderer renderer,
    Size size,
    double ratio,
    int? Function(int, int) colourAt,
    String where,
  ) {
    expect(renderer.agents, isNotEmpty);
    for (final SceneAgent agent in renderer.agents) {
      final at = renderer.project(agent.position, size)! * ratio;
      final voice = voices[agent.voiceIndex];
      final got = brightestOf(colourAt, at);
      expect(
        isVoice(got, voice),
        isTrue,
        reason:
            '$where: the agent at ${agent.position} should draw in $voice '
            'at $at, got $got',
      );
    }
  }

  testWidgets('scene: the 3D view draws, orbits and resizes in a second '
      'native window over the same engine', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final renderer = FlutterSceneRenderer();
    final engine = PhiEngine(
      FakeYseGateway(),
      sceneRenderer: renderer,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final audience = ValueNotifier<WindowController?>(null);

    await tester.pumpWidget(
      ValueListenableBuilder<WindowController?>(
        valueListenable: audience,
        builder: (context, window, app) => ViewAnchor(
          view: window == null
              ? null
              : Window(
                  controller: window,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: KeyedSubtree(
                      key: audienceKey,
                      child: renderer.buildView(),
                    ),
                  ),
                ),
          child: app!,
        ),
        child: PhiApp(engine: engine, session: session),
      ),
    );
    await tester.pumpAndSettle();

    // The performer opens the Scene in the main window and loads the pick
    // demo: agents on ±X, ±Y, +Z in five voices.
    await tester.tap(railFor(SurfaceId.scene));
    await tester.pump();
    await settle(tester);
    expect(
      renderer.status,
      SceneViewStatus.ready,
      reason: 'Flutter GPU is on in the runner: ${renderer.failure}',
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('scene-pick-demo-toggle')),
        matching: find.byType(PhiToggle),
      ),
    );
    await settle(tester);
    expect(renderer.agents, hasLength(5));

    // The audience window: a native top-level window over the same engine.
    // Only now, with the main window long since painted: on Linux X11 a
    // secondary window made before the main window's first GTK paint exits
    // the app (docs/design/shell-layout.md §5.6).
    //
    // And with the Scene held still until a plain frame has been drawn: on
    // Windows a new view leaves the raster thread with no GL context until the
    // next frame, and a Flutter GPU submit that lands in that gap kills the
    // app (#559).
    renderer.setVisible(false);
    final window = WindowController(
      size: const Size(960, 540),
      title: 'Phi audience view',
    );
    await settle(tester, frames: 2);
    renderer.setVisible(true);
    audience.value = window;
    await settle(tester);

    // It is a view the engine itself made, not a test stand-in, and the
    // Scene view in it reads that view (its pixel ratio among it).
    expect(
      ui.PlatformDispatcher.instance.views.map((v) => v.viewId),
      contains(window.rootView.viewId),
      reason: 'the engine knows the window view',
    );
    expect(tester.binding.platformDispatcher.views, hasLength(2));
    expect(audienceViewport, findsOneWidget);
    expect(mainViewport, findsOneWidget);
    expect(
      View.of(tester.element(audienceViewport)).viewId,
      window.rootView.viewId,
    );

    // Both views draw the one graph, each at its own size.
    var windowSize = tester.getSize(audienceViewport);
    expect(windowSize, window.contentSize);
    expect(windowSize, isNot(tester.getSize(mainViewport)));
    Future<void> expectWindowLayer(String when) async => expectAgentsDrawn(
      renderer,
      windowSize,
      pixelRatioOf(tester, audienceViewport),
      layerPixels(await capture(tester, audienceViewport)),
      'audience window layer, $when',
    );
    Future<void> expectMainLayer(String when) async => expectAgentsDrawn(
      renderer,
      tester.getSize(mainViewport),
      pixelRatioOf(tester, mainViewport),
      layerPixels(await capture(tester, mainViewport)),
      'main window layer, $when',
    );
    await expectWindowLayer('opened');
    await expectMainLayer('opened');

    // What the native window shows on the display (Linux: read back from
    // the window system).
    Future<void> expectOnScreen(String when) async {
      if (!Platform.isLinux) return;
      final handle = (window as WindowControllerLinux).windowHandle;
      final ratio = window.rootView.devicePixelRatio;
      final physical = windowSize * ratio;
      LinuxWindowPixels? shown;
      // A presented frame reaches the display a GTK paint later.
      for (var i = 0; i < 40; i++) {
        shown = LinuxWindowPixels.read(handle);
        if (shown != null &&
            Size(shown.width.toDouble(), shown.height.toDouble()) == physical &&
            renderer.agents.every(
              (a) => isVoice(
                brightestOf(
                  shown!.at,
                  renderer.project(a.position, windowSize)! * ratio,
                ),
                voices[a.voiceIndex],
              ),
            )) {
          break;
        }
        await settle(tester, frames: 2);
      }
      expect(shown, isNotNull, reason: '$when: the window is on the display');
      expect(
        Size(shown!.width.toDouble(), shown.height.toDouble()),
        physical,
        reason: '$when: the native window is the size of its view',
      );
      expectAgentsDrawn(
        renderer,
        windowSize,
        ratio,
        shown.at,
        'the display, $when',
      );
    }

    await expectOnScreen('opened');

    // A drag on empty space inside the audience window orbits the one camera:
    // the window redraws from the new pose, and so does the main window.
    final yaw = renderer.orbit.yaw;
    final view = tester.viewOf(audienceViewport);
    final origin = tester.getTopLeft(audienceViewport);
    final empty =
        origin + Offset(windowSize.width - 40, windowSize.height - 40);
    final orbit = await tester.startGesture(empty, view: view);
    await orbit.moveBy(const Offset(60, 0));
    await orbit.moveBy(const Offset(60, 0));
    await orbit.up();
    await settle(tester, frames: 4);
    expect(renderer.orbit.yaw, isNot(closeTo(yaw, 1e-6)));
    await expectWindowLayer('orbited');
    await expectMainLayer('orbited');
    await expectOnScreen('orbited');

    // Resizing the window resizes the Scene in it.
    window.setSize(const Size(1280, 720));
    for (var i = 0; i < 40; i++) {
      await settle(tester, frames: 2);
      if (tester.getSize(audienceViewport) == const Size(1280, 720)) break;
    }
    windowSize = tester.getSize(audienceViewport);
    expect(windowSize, const Size(1280, 720));
    await expectWindowLayer('resized');
    await expectOnScreen('resized');

    // The performer moves the main window to Mix. The Scene goes offstage
    // there, and the audience window still shows it.
    await tester.tap(railFor(SurfaceId.mix));
    await settle(tester);
    expect(mainViewport, findsNothing);
    expect(renderer.visible, isFalse);
    await expectWindowLayer('main window on Mix');
    await expectOnScreen('main window on Mix');

    // Close the window the orderly way: its widgets leave the tree, then the
    // native window goes.
    audience.value = null;
    await settle(tester, frames: 3);
    window.destroy();
    await settle(tester, frames: 3);
    expect(tester.binding.platformDispatcher.views, hasLength(1));

    expect(tester.takeException(), isNull);
    audience.dispose();
    session.dispose();
    await engine.dispose();
  });
}
