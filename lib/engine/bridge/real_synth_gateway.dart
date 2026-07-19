import 'package:yse/yse.dart';

import '../../domain/synth/synth_definition.dart';
import 'materialised_synth.dart';
import 'real_materialised_synth.dart';
import 'synth_gateway.dart';

/// Production [SynthGateway] that materialises synths through `package:yse`.
///
/// Holds two seams the engine supplies (both yse-internal, so they stay in the
/// bridge): a [MixBusResolver] that turns a mix-bus channel id into a live
/// [Channel] for the `Sound.fromSynth` binding, and an [AssetPathResolver] that
/// turns a project-relative asset ref into an absolute path for the FM / sampler
/// loaders. Both default to no-ops (master bus, identity path) so a bare gateway
/// still constructs — the engine wires the real resolvers in issue #208.
///
/// Requires `libyse.dll` discoverable at runtime — see README.md. The heavy
/// lifting lives on the [RealMaterialisedSynth] handle each call mints.
class RealSynthGateway implements SynthGateway {
  RealSynthGateway({
    MixBusResolver? busResolver,
    AssetPathResolver? resolveAsset,
  }) : _busResolver = busResolver ?? _masterBus,
       _resolveAsset = resolveAsset;

  static Channel? _masterBus(int _) => null;

  final MixBusResolver _busResolver;
  final AssetPathResolver? _resolveAsset;

  @override
  MaterialisedSynth materialiseSynth(
    SynthDefinition definition, {
    required int channel,
  }) => RealMaterialisedSynth(
    definition,
    channel: channel,
    busResolver: _busResolver,
    resolveAsset: _resolveAsset,
  );
}
