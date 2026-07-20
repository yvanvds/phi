import 'dart:ui';

import '../../domain/patcher/patch_port.dart';

/// Everything needed to (re)create one canvas node — captured so a delete can
/// be undone and a selection can be duplicated.
///
/// It bundles the native creation inputs ([type] + [args]) with the canvas-side
/// presentation ([title], [voice], [position], [size]) and the reified port
/// topology ([inputs] / [outputs]), so the controller can rebuild an identical
/// [PatchNode] without re-inspecting the gateway. Immutable — [offsetBy] returns
/// a copy shifted by a grid step for the duplicate gesture.
class PatchNodeSpec {
  const PatchNodeSpec({
    required this.type,
    required this.args,
    required this.title,
    required this.voice,
    required this.position,
    required this.size,
    required this.inputs,
    required this.outputs,
  });

  /// One of `package:yse`'s `Obj.*` constants.
  final String type;

  /// The creation-argument string the object was made with.
  final String args;

  /// Header title.
  final String title;

  /// Voice swatch in `[1, 6]`.
  final int voice;

  /// Top-left canvas position.
  final Offset position;

  /// On-canvas size.
  final Size size;

  final List<PatchPort> inputs;
  final List<PatchPort> outputs;

  /// A copy shifted by [delta] — the offset a duplicate lands at.
  PatchNodeSpec offsetBy(Offset delta) => PatchNodeSpec(
    type: type,
    args: args,
    title: title,
    voice: voice,
    position: position + delta,
    size: size,
    inputs: inputs,
    outputs: outputs,
  );
}
