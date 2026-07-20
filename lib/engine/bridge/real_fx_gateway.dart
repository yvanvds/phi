import '../../domain/fx/fx_definition.dart';
import 'fx_chain.dart';
import 'fx_gateway.dart';
import 'materialised_fx.dart';
import 'real_fx_chain.dart';
import 'real_materialised_fx.dart';
import 'real_materialised_synth.dart' show MixBusResolver;

/// Production [FxGateway] that materialises effects and insert chains through
/// `package:yse` (design `docs/design/racks-and-voices.md` §5).
///
/// Holds the same [MixBusResolver] seam [RealSynthGateway] does — the engine
/// supplies it (yse-internal, so it stays in the bridge) to turn a mix-bus
/// channel id into the live `Channel` an [FxChain] attaches its head to. It
/// defaults to the master bus so a bare gateway still constructs; the engine
/// wires the real resolver in issue #208. Effects carry no assets, so — unlike
/// the synth gateway — there is no asset-path seam here.
///
/// Requires `libyse.dll` discoverable at runtime — see README.md. The heavy
/// lifting lives on the [RealMaterialisedFx] handles and [RealFxChain]s each
/// call mints.
class RealFxGateway implements FxGateway {
  RealFxGateway({MixBusResolver? busResolver})
    : _busResolver = busResolver ?? _masterBus;

  static Null _masterBus(int _) => null;

  final MixBusResolver _busResolver;

  @override
  MaterialisedFx materialiseFx(FxDefinition definition) =>
      RealMaterialisedFx(definition);

  @override
  FxChain createChain({required int busChannelId}) =>
      RealFxChain(busChannelId, _busResolver);
}
