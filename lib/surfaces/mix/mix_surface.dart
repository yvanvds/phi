import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../design/widgets/button/primary_button.dart';
import '../../design/widgets/channel_strip/channel_strip.dart';
import '../../domain/project/entity_address.dart';
import '../../engine/engine.dart';
import '../../engine/state/mix_tree_node.dart';
import '../../engine/state/mixer_channel.dart';
import '../surface.dart';

/// Mix surface — a grouped rack of channel strips (design `docs/design/mix.md`
/// §7). Top-level strips and group buses flow left-to-right, a group rendering
/// as a **framed section** with its own header strip and child strips inside;
/// the master strip is pinned on the right.
///
/// The header `+` opens a menu — **add channel · add group · add return** — and
/// strips carry a drag handle: drag one into a group's section to re-parent it,
/// out onto the rack to un-group it, or onto a sibling inside a section to
/// reorder it. Every edit routes through [PhiEngine], which moves the registry
/// entity (rename = refactor) so the change persists and journals.
class MixSurface extends Surface {
  const MixSurface({required this.engine, super.key});

  final PhiEngine engine;

  /// Key on a leaf strip's drag handle, by channel name — so widget/integration
  /// tests can grab a specific strip to drag it into a group or reorder it.
  static Key dragHandleKey(String name) => Key('MixSurface.dragHandle.$name');

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      padding: const EdgeInsets.all(PhiSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(engine: engine),
          const SizedBox(height: PhiSpacing.s2),
          Expanded(
            child: ValueListenableBuilder<List<MixTreeNode>>(
              valueListenable: engine.mixTree,
              builder: (context, tree, _) =>
                  _StripRack(engine: engine, tree: tree),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.engine});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ValueListenableBuilder<List<MixerChannel>>(
          valueListenable: engine.channels,
          builder: (context, channels, _) => Text(
            'MIX · ${channels.length + 1} CHANNELS',
            style: PhiType.caption(),
          ),
        ),
        const SizedBox(width: PhiSpacing.s3),
        _AddMenuButton(engine: engine),
        const Spacer(),
        SizedBox(
          width: 140,
          child: ValueListenableBuilder<bool>(
            valueListenable: engine.testSignal,
            builder: (context, armed, _) => PrimaryButton(
              label: armed ? 'stop sine' : 'play sine',
              isArmed: armed,
              onPressed: () => engine.setTestSignal(on: !armed),
            ),
          ),
        ),
      ],
    );
  }
}

/// What the header `+` menu can add.
enum _AddChoice { channel, group, returnBus }

/// The header `+` — a small box that, on tap, opens the add menu (add channel ·
/// add group · add return, design §7). Disabled until the engine is started.
class _AddMenuButton extends StatelessWidget {
  const _AddMenuButton({required this.engine});

  final PhiEngine engine;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<_AddChoice>(
      context: context,
      position: position,
      color: PhiColors.bg2,
      items: const [
        PopupMenuItem<_AddChoice>(
          value: _AddChoice.channel,
          child: Text('add channel'),
        ),
        PopupMenuItem<_AddChoice>(
          value: _AddChoice.group,
          child: Text('add group'),
        ),
        PopupMenuItem<_AddChoice>(
          value: _AddChoice.returnBus,
          child: Text('add return'),
        ),
      ],
    );
    switch (choice) {
      case _AddChoice.channel:
        engine.addChannel();
      case _AddChoice.group:
        engine.addGroup();
      case _AddChoice.returnBus:
        engine.addReturn();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = engine.isStarted;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => _open(context) : null,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(color: PhiColors.line2),
            borderRadius: PhiRadii.all1,
          ),
          child: Text(
            '+',
            style: PhiType.monoL().copyWith(color: PhiColors.fg1),
          ),
        ),
      ),
    );
  }
}

/// The rack body: top-level nodes flow left-to-right, master pinned right. The
/// whole rack is a drop target so a strip dragged onto the open rack (outside
/// any group section) is moved back to the top level (drag-out-of-a-group).
class _StripRack extends StatelessWidget {
  const _StripRack({required this.engine, required this.tree});

  final PhiEngine engine;
  final List<MixTreeNode> tree;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_StripDrag>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) =>
          engine.moveChannelToGroup(details.data.channel, null),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(
              color: hovering ? PhiColors.line2 : PhiColors.line1,
            ),
            borderRadius: PhiRadii.all1,
          ),
          padding: const EdgeInsets.all(PhiSpacing.s2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final node in tree) ...[
                  if (node.isGroup)
                    _GroupSection(engine: engine, node: node)
                  else
                    _LeafStrip(engine: engine, node: node),
                  const SizedBox(width: PhiSpacing.s1),
                ],
                const SizedBox(width: PhiSpacing.s2),
                Container(width: 1, height: 260, color: PhiColors.line1),
                const SizedBox(width: PhiSpacing.s2),
                _MasterStrip(engine: engine),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A group bus rendered as a framed section: the group's own header strip plus
/// its child strips inside one border (design §7). The whole section is a drop
/// target — a strip dropped onto it (its header or padding) is re-parented into
/// the group.
class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.engine, required this.node});

  final PhiEngine engine;
  final MixTreeNode node;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_StripDrag>(
      // Never accept the group's own strip onto itself (leaf strips only drag,
      // but guard defensively) — a drop into its own subtree is rejected anyway.
      onWillAcceptWithDetails: (details) =>
          details.data.address != node.address,
      onAcceptWithDetails: (details) =>
          engine.moveChannelToGroup(details.data.channel, node.address),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Container(
          padding: const EdgeInsets.all(PhiSpacing.s2),
          decoration: BoxDecoration(
            color: PhiColors.bg0,
            border: Border.all(
              color: hovering ? PhiColors.lineHot : PhiColors.line2,
            ),
            borderRadius: PhiRadii.all1,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BusStrip(engine: engine, node: node),
              for (final child in node.children) ...[
                const SizedBox(width: PhiSpacing.s1),
                if (child.isGroup)
                  _GroupSection(engine: engine, node: child)
                else
                  _ChildStrip(engine: engine, node: child),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A leaf strip that also reorders: dropping another strip onto it places that
/// strip immediately before it. When the dragged strip already shares this
/// child's parent it is a reorder; otherwise it is re-parented into this group.
class _ChildStrip extends StatelessWidget {
  const _ChildStrip({required this.engine, required this.node});

  final PhiEngine engine;
  final MixTreeNode node;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_StripDrag>(
      onWillAcceptWithDetails: (details) =>
          details.data.address != node.address,
      onAcceptWithDetails: (details) {
        final dragged = details.data;
        if (dragged.address.parent == node.address.parent) {
          engine.moveChannelBefore(dragged.channel, node.channel);
        } else {
          engine.moveChannelToGroup(dragged.channel, node.address.parent);
        }
      },
      builder: (context, candidate, rejected) => _LeafStrip(
        engine: engine,
        node: node,
        highlighted: candidate.isNotEmpty,
      ),
    );
  }
}

/// A draggable leaf strip — the header carries a grip that starts a drag (the
/// fader keeps its own vertical-drag gesture). Bound to the channel so its live
/// volume / peak / mute / solo track.
class _LeafStrip extends StatelessWidget {
  const _LeafStrip({
    required this.engine,
    required this.node,
    this.highlighted = false,
  });

  final PhiEngine engine;
  final MixTreeNode node;

  /// Whether a drag is hovering over this strip as a reorder target.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: node.channel,
      builder: (context, _) => Opacity(
        opacity: highlighted ? 0.7 : 1.0,
        child: ChannelStrip(
          name: node.channel.name,
          volume: node.channel.volume,
          peak: node.channel.peak,
          muted: node.channel.muted,
          soloed: node.channel.soloed,
          voiceColor: PhiVoices.color(node.channel.voice),
          voiceGlow: PhiVoices.glow(node.channel.voice),
          dragHandle: _DragHandle(channel: node.channel, address: node.address),
          onVolumeChanged: (v) => engine.setChannelVolume(node.channel, v),
          onVolumeChangeStart: () =>
              engine.beginChannelVolumeGesture(node.channel),
          onVolumeChangeEnd: () => engine.endChannelVolumeGesture(node.channel),
          onMuteToggle: () =>
              engine.setChannelMuted(node.channel, muted: !node.channel.muted),
          onSoloToggle: () => engine.setChannelSoloed(
            node.channel,
            soloed: !node.channel.soloed,
          ),
          onRename: (name) => engine.renameChannel(node.channel, name),
          onRemove: () => engine.removeChannel(node.channel),
        ),
      ),
    );
  }
}

/// The header strip of a group bus — same controls as a leaf strip (name,
/// fader, mute/solo, meter) but with no drag handle: groups are not dragged in
/// v1 (design §7, "drag a strip"). Renaming or removing it moves/removes the
/// whole group subtree through the registry.
class _BusStrip extends StatelessWidget {
  const _BusStrip({required this.engine, required this.node});

  final PhiEngine engine;
  final MixTreeNode node;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: node.channel,
      builder: (context, _) => ChannelStrip(
        name: node.channel.name,
        volume: node.channel.volume,
        peak: node.channel.peak,
        muted: node.channel.muted,
        soloed: node.channel.soloed,
        voiceColor: PhiVoices.color(node.channel.voice),
        voiceGlow: PhiVoices.glow(node.channel.voice),
        onVolumeChanged: (v) => engine.setChannelVolume(node.channel, v),
        onVolumeChangeStart: () =>
            engine.beginChannelVolumeGesture(node.channel),
        onVolumeChangeEnd: () => engine.endChannelVolumeGesture(node.channel),
        onMuteToggle: () =>
            engine.setChannelMuted(node.channel, muted: !node.channel.muted),
        onSoloToggle: () =>
            engine.setChannelSoloed(node.channel, soloed: !node.channel.soloed),
        onRename: (name) => engine.renameChannel(node.channel, name),
        onRemove: () => engine.removeChannel(node.channel),
      ),
    );
  }
}

/// The master strip — pinned right, never renamed / removed / dragged.
class _MasterStrip extends StatelessWidget {
  const _MasterStrip({required this.engine});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    final channel = engine.masterChannel;
    return ListenableBuilder(
      listenable: channel,
      builder: (context, _) => ChannelStrip(
        name: channel.name,
        volume: channel.volume,
        peak: channel.peak,
        muted: channel.muted,
        soloed: channel.soloed,
        voiceColor: PhiVoices.color(channel.voice),
        voiceGlow: PhiVoices.glow(channel.voice),
        isMaster: true,
        onVolumeChanged: (v) => engine.setChannelVolume(channel, v),
        onVolumeChangeStart: () => engine.beginChannelVolumeGesture(channel),
        onVolumeChangeEnd: () => engine.endChannelVolumeGesture(channel),
      ),
    );
  }
}

/// The strip drag payload — the channel to re-route plus its address, so a drop
/// target can tell an in-parent reorder from a cross-group re-parent.
class _StripDrag {
  const _StripDrag(this.channel, this.address);

  final MixerChannel channel;
  final EntityAddress address;
}

/// The grip in a leaf strip's header that starts a drag. Its feedback is a
/// compact floating chip of the strip name — the whole 86px strip as feedback
/// is too heavy to drag around.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.channel, required this.address});

  final MixerChannel channel;
  final EntityAddress address;

  @override
  Widget build(BuildContext context) {
    return Draggable<_StripDrag>(
      data: _StripDrag(channel, address),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s2,
            vertical: PhiSpacing.s1,
          ),
          decoration: BoxDecoration(
            color: PhiColors.bg3,
            border: Border.all(color: PhiColors.line2),
            borderRadius: PhiRadii.all1,
          ),
          child: Text(
            channel.name,
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
          ),
        ),
      ),
      childWhenDragging: const Icon(
        Icons.drag_indicator,
        size: 14,
        color: PhiColors.line2,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Icon(
          Icons.drag_indicator,
          key: MixSurface.dragHandleKey(channel.name),
          size: 14,
          color: PhiColors.fg3,
        ),
      ),
    );
  }
}
