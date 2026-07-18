import '../../domain/project/entity_address.dart';
import 'mixer_channel.dart';

/// One node of the Mix surface's rendered tree (design `docs/design/mix.md`
/// §7): a materialised [channel] (a strip or a group bus), its registry
/// [address] (so the surface can re-parent / reorder it), whether it is a group
/// bus ([isGroup] — rendered as a framed section with its [children] inside),
/// and its direct [children] in tree order.
///
/// Returns are **not** in this tree — they sit outside it (design §4) and
/// surface through `PhiEngine.returns`. Master is implicit and pinned right, so
/// it is not a node here either. Immutable; the engine rebuilds the whole forest
/// on every channel re-sync, so a listener re-renders structural changes while
/// per-channel state (volume, peak, mute, solo) still flows through the
/// individual [MixerChannel].
class MixTreeNode {
  const MixTreeNode({
    required this.channel,
    required this.address,
    required this.isGroup,
    this.children = const [],
  });

  /// The materialised channel — the strip's or group bus's live volume / peak /
  /// mute / solo / voice.
  final MixerChannel channel;

  /// The node's registry address — the key the surface passes back to the engine
  /// to re-parent or reorder it.
  final EntityAddress address;

  /// Whether this node is a group **bus** (a framed section with a header strip
  /// and [children]) rather than a leaf strip.
  final bool isGroup;

  /// The direct children, in tree order. Empty for a leaf strip (and for an
  /// empty group bus).
  final List<MixTreeNode> children;
}
