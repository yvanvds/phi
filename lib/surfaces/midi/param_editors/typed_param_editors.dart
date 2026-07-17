import 'package:flutter/widgets.dart';

import '../../../domain/midi/midi_transform.dart';
import '../../../domain/midi/midi_transform_chain.dart';
import '../../../domain/midi/transforms/agent_spawn_transform.dart';
import '../../../domain/midi/transforms/scale_conformance_transform.dart';
import '../../../domain/midi/transforms/spectral_mapping_transform.dart';
import '../../../domain/midi/transforms/splitting_transform.dart';
import '../../../domain/midi/transforms/velocity_to_parameter_transform.dart';
import '../../../domain/midi/transforms/voice_routing_transform.dart';
import 'agent_spawn_editor.dart';
import 'scale_tuning_editor.dart';
import 'spectral_map_editor.dart';
import 'split_voices_editor.dart';
import 'velocity_curve_editor.dart';
import 'voice_routing_editor.dart';

/// Dispatch from a transform to its dedicated typed parameter editor
/// (issue #95).
///
/// The transforms whose behaviour lives in a table, rule-list, or curve get a
/// bespoke dialog rather than the generic scalar editor, because a map,
/// rule-list, axis set, scale preset, or velocity curve doesn't fit the
/// `withParam(String, num)` seam. The chip context menu asks [hasTypedEditor]
/// whether to route here at all, then calls [buildTypedParamEditor] to build the
/// dialog.
///
/// [ScaleConformanceTransform] appears here even though its tonic is a scalar:
/// its scale/tuning preset needs a picker, and its editor folds the tonic in
/// so both live in one dialog. [VelocityToParameterTransform] joined the set
/// once its declarative [VelocityCurve] model landed (issue #108).
bool hasTypedEditor(MidiTransform transform) =>
    transform is SpectralMappingTransform ||
    transform is VoiceRoutingTransform ||
    transform is SplittingTransform ||
    transform is AgentSpawnTransform ||
    transform is ScaleConformanceTransform ||
    transform is VelocityToParameterTransform;

/// The typed editor dialog for the transform at [index], or `null` when that
/// transform has none (the caller falls back to the generic scalar editor).
Widget? buildTypedParamEditor(MidiTransformChain chain, int index) {
  final transform = chain.transforms[index];
  return switch (transform) {
    SpectralMappingTransform() => SpectralMapEditor(chain: chain, index: index),
    VoiceRoutingTransform() => VoiceRoutingEditor(chain: chain, index: index),
    SplittingTransform() => SplitVoicesEditor(chain: chain, index: index),
    AgentSpawnTransform() => AgentSpawnEditor(chain: chain, index: index),
    ScaleConformanceTransform() => ScaleTuningEditor(
      chain: chain,
      index: index,
    ),
    VelocityToParameterTransform() => VelocityCurveEditor(
      chain: chain,
      index: index,
    ),
    _ => null,
  };
}
