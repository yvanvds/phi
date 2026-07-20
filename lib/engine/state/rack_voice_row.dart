import '../../domain/project/entity_address.dart';
import '../../domain/voice/voice_kind.dart';

/// An immutable, read-only view of one `voice.` entity, as the racks **voices
/// pane** (issue #209) renders it.
///
/// The voices pane is a **scaffold** in this issue — rows render, but binding /
/// colour / kind editing and the audition test strip land in the voices-pane
/// issue (#211, design `docs/design/racks-and-voices.md` §8). So this carries
/// exactly what a row needs to display: the voice's [address], its [kind], the
/// `synth.` definition and `mix.` bus it points at (leaf names for display), the
/// external [channel] (external voices only), and its [colorToken] swatch.
class RackVoiceRow {
  const RackVoiceRow({
    required this.address,
    required this.kind,
    required this.output,
    required this.colorToken,
    this.synth,
    this.channel,
  });

  /// The registry address of the voice entity.
  final EntityAddress address;

  /// Whether the voice plays an internal synth or external hardware.
  final VoiceKind kind;

  /// The `synth.` definition an internal voice instantiates, or `null` for an
  /// external voice.
  final EntityAddress? synth;

  /// The MIDI channel (`1..16`) an external voice plays, or `null` for an
  /// internal voice.
  final int? channel;

  /// The `mix.` bus this voice's output routes to.
  final EntityAddress output;

  /// The voice colour — a design-token name (`voice1..voice6`, or any full
  /// palette token). The pane resolves it to a swatch.
  final String colorToken;

  /// The voice's display name — its address leaf.
  String get name => address.name;
}
