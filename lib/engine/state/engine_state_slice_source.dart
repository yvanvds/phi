import '../../domain/project/entity_address.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_entity.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/state_machine/slices/clip_slice_entry.dart';
import '../../domain/state_machine/slices/mix_slice_entry.dart';
import '../../domain/state_machine/slices/tempo_slice_entry.dart';
import '../../domain/time_domains/time_domain.dart';
import 'mix_tree_node.dart';
import 'state_slice_source.dart';

/// The production [StateSliceSource] — capture-from-live over the engine's
/// real controllers (design `docs/design/state-graph.md` §4, issue #242).
///
/// Each category reads its owning controller at capture time, through
/// closures so a project swap (`bindRegistry`) needs no rewiring:
///
/// - **clips** — the MIDI subsystem's playing sessions (address + live loop
///   flag); empty without a MIDI gateway.
/// - **mix** — the materialised mix tree (leaf strips *and* group buses — a
///   `mix.` group is a bus), each with its live volume/mute. Master is
///   implicit (not a registry entity — its level rides the manifest) and
///   returns sit outside the tree, so neither is captured.
/// - **variables** — the runtime-variable registry's current values.
/// - **tempos** — the bound registry's top-level `domain.` entities and their
///   authored tempos (a transient fader bend is performance, not the domain's
///   tempo).
class EngineStateSliceSource implements StateSliceSource {
  EngineStateSliceSource({
    required List<ClipSliceEntry> Function() playingClips,
    required List<MixTreeNode> Function() mixNodes,
    required RuntimeVariableRegistry Function() variables,
    required ProjectRegistry Function() registry,
  }) : _playingClips = playingClips,
       _mixNodes = mixNodes,
       _variables = variables,
       _registry = registry;

  final List<ClipSliceEntry> Function() _playingClips;
  final List<MixTreeNode> Function() _mixNodes;
  final RuntimeVariableRegistry Function() _variables;
  final ProjectRegistry Function() _registry;

  @override
  List<ClipSliceEntry> captureClips() => _playingClips();

  @override
  List<MixSliceEntry> captureMix() {
    final entries = <MixSliceEntry>[];
    void visit(MixTreeNode node) {
      entries.add(
        MixSliceEntry(
          bus: node.address,
          volume: node.channel.volume,
          muted: node.channel.muted,
        ),
      );
      node.children.forEach(visit);
    }

    _mixNodes().forEach(visit);
    return entries;
  }

  @override
  Map<String, String> captureVariables() => {
    for (final variable in _variables().variables)
      variable.name: variable.current,
  };

  @override
  List<TempoSliceEntry> captureTempos() {
    final entries = <TempoSliceEntry>[];
    for (final node in _registry().childrenOfKind(RegistryKinds.domain)) {
      if (node is! RegistryEntity) continue;
      final payload = node.payload;
      if (payload is! TimeDomain) continue;
      entries.add(
        TempoSliceEntry(
          domain: EntityAddress(
            kind: RegistryKinds.domain,
            segments: [node.name],
          ),
          bpm: payload.tempo,
        ),
      );
    }
    return entries;
  }
}
