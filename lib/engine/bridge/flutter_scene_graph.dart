import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm32;
import 'package:vector_math/vector_math_64.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/scene/scene_agent.dart';
import 'flutter_scene_space.dart';

/// The `flutter_scene` scene graph behind the Scene viewport.
///
/// Each agent draws as a Phi-styled glowing dot — an opaque *core* in the
/// voice's colour inside a translucent *halo* in its `voiceSoft` token — over
/// a faint ground grid on the XY plane, with a brighter translucent shell
/// around the selected agent. Nodes are pooled: an agent push moves existing
/// nodes and swaps their voice mesh, and only grows the pool, so a field
/// pushing every frame allocates nothing in steady state.
///
/// Building one needs the engine's static resources
/// (`fs.Scene.initializeStaticResources`), which in turn need Flutter GPU.
class FlutterSceneGraph {
  FlutterSceneGraph() : scene = fs.Scene() {
    // Unlit dots on the void: no tone curve, so a voice colour lands on screen
    // as authored, and a soft bloom so the cores glow.
    scene
      ..toneMapping = fs.ToneMappingMode.linear
      ..exposure = 1.0;
    scene.postProcess.bloom
      ..enabled = true
      ..threshold = bloomThreshold
      ..intensity = bloomIntensity;
    _coreMeshes = [
      for (final c in _voiceCores) fs.Mesh(_coreGeometry, _unlit(c)),
    ];
    _haloMeshes = [
      for (final c in _voiceHalos)
        fs.Mesh(_haloGeometry, _unlit(c, blend: true)),
    ];
    _selection = fs.Node(
      name: 'selection',
      mesh: fs.Mesh(_selectionGeometry, _unlit(selectionColor, blend: true)),
    )..visible = false;
    scene
      ..add(_grid())
      ..add(_selection);
  }

  /// Radius of an agent's opaque core, in scene units.
  static const double coreRadius = 0.18;

  /// Radius of an agent's translucent halo — matches the field's default pick
  /// radius, so the clickable target is the glow the performer sees.
  static const double haloRadius = 0.55;

  /// Radius of the selection shell, just outside an agent's halo.
  static const double selectionRadius = 0.74;

  /// Half the ground grid's extent, in scene units (lines every unit).
  static const int gridHalfExtent = 10;

  /// Bloom threshold and strength for the glowing cores.
  static const double bloomThreshold = 0.6;
  static const double bloomIntensity = 0.25;

  /// The selection shell's colour: bright white, translucent enough to let the
  /// picked agent show through.
  static const Color selectionColor = Color(0x59FFFFFF);

  /// The engine scene the viewport renders.
  final fs.Scene scene;

  late final List<fs.Mesh> _coreMeshes;
  late final List<fs.Mesh> _haloMeshes;
  late final fs.Node _selection;
  final List<(fs.Node, fs.Node)> _agentNodes = [];
  int _visibleAgents = 0;

  late final fs.Geometry _coreGeometry = fs.SphereGeometry(
    radius: coreRadius,
    segments: 24,
    rings: 12,
  );
  late final fs.Geometry _haloGeometry = fs.SphereGeometry(
    radius: haloRadius,
    segments: 32,
    rings: 16,
  );
  late final fs.Geometry _selectionGeometry = fs.SphereGeometry(
    radius: selectionRadius,
    segments: 32,
    rings: 16,
  );

  /// How many agents are currently drawn.
  int get agentCount => _visibleAgents;

  /// Whether the selection shell is drawn.
  bool get selectionVisible => _selection.visible;

  /// Draw [agents]: one core + halo per agent at its position in its voice
  /// colour. Agents beyond the previous count grow the node pool; nodes past
  /// the new count are hidden, not freed.
  void setAgents(List<SceneAgent> agents) {
    while (_agentNodes.length < agents.length) {
      final core = fs.Node(name: 'agent-core');
      final halo = fs.Node(name: 'agent-halo');
      scene
        ..add(core)
        ..add(halo);
      _agentNodes.add((core, halo));
    }
    for (var i = 0; i < _agentNodes.length; i++) {
      final (core, halo) = _agentNodes[i];
      if (i >= agents.length) {
        core.visible = false;
        halo.visible = false;
        continue;
      }
      final agent = agents[i];
      final voice = agent.voiceIndex.clamp(0, _coreMeshes.length - 1);
      final position = FlutterSceneSpace.toEngine(agent.position);
      core
        ..mesh = _coreMeshes[voice]
        ..position = position
        ..visible = true;
      halo
        ..mesh = _haloMeshes[voice]
        ..position = position
        ..visible = true;
    }
    _visibleAgents = agents.length;
  }

  /// Ring the agent at [worldPosition] with the selection shell, or hide the
  /// shell with `null`.
  void setSelection(Vector3? worldPosition) {
    if (worldPosition == null) {
      _selection.visible = false;
      return;
    }
    _selection
      ..position = FlutterSceneSpace.toEngine(worldPosition)
      ..visible = true;
  }

  /// Release the engine scene's GPU resources. The graph is unusable after.
  void dispose() => scene.dispose();

  /// The faint ground grid on Phi's XY plane, with the two axes through the
  /// origin drawn a little brighter so the performer can tell X from Y.
  fs.Node _grid() {
    final lines = <double>[];
    final axes = <double>[];
    const n = gridHalfExtent;
    for (var i = -n; i <= n; i++) {
      final target = i == 0 ? axes : lines;
      final t = i.toDouble();
      // A line parallel to Y at x = t, and one parallel to X at y = t.
      target
        ..addAll(_segment(Vector3(t, -n.toDouble(), 0), Vector3(t, n * 1.0, 0)))
        ..addAll(
          _segment(Vector3(-n.toDouble(), t, 0), Vector3(n * 1.0, t, 0)),
        );
    }
    return fs.Node(name: 'ground-grid')
      ..add(
        fs.Node(
          name: 'grid-lines',
          mesh: fs.Mesh(
            fs.LineSegmentsGeometry(
              fs.LineSegmentData(positions: Float32List.fromList(lines)),
              width: 0.015,
            ),
            _unlit(PhiColors.line1, blend: true),
          ),
        ),
      )
      ..add(
        fs.Node(
          name: 'grid-axes',
          mesh: fs.Mesh(
            fs.LineSegmentsGeometry(
              fs.LineSegmentData(positions: Float32List.fromList(axes)),
              width: 0.025,
            ),
            _unlit(PhiColors.line2, blend: true),
          ),
        ),
      );
  }

  static List<double> _segment(Vector3 a, Vector3 b) {
    final ea = FlutterSceneSpace.toEngine(a);
    final eb = FlutterSceneSpace.toEngine(b);
    return [ea.x, ea.y, ea.z, eb.x, eb.y, eb.z];
  }

  static fs.UnlitMaterial _unlit(Color color, {bool blend = false}) =>
      fs.UnlitMaterial()
        ..baseColorFactor = linearColor(color)
        ..alphaMode = blend ? fs.AlphaMode.blend : fs.AlphaMode.opaque;

  /// [color] (sRGB, as the design tokens are authored) as the linear RGBA the
  /// engine's materials take; alpha stays linear.
  static vm32.Vector4 linearColor(Color color) => vm32.Vector4(
    _toLinear(color.r),
    _toLinear(color.g),
    _toLinear(color.b),
    color.a,
  );

  static double _toLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static const List<Color> _voiceCores = [
    PhiColors.voice1,
    PhiColors.voice2,
    PhiColors.voice3,
    PhiColors.voice4,
    PhiColors.voice5,
    PhiColors.voice6,
  ];

  static const List<Color> _voiceHalos = [
    PhiColors.voice1Soft,
    PhiColors.voice2Soft,
    PhiColors.voice3Soft,
    PhiColors.voice4Soft,
    PhiColors.voice5Soft,
    PhiColors.voice6Soft,
  ];
}
