import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../design/widgets/button/primary_button.dart';
import '../../design/widgets/channel_strip/channel_strip.dart';
import '../../design/widgets/dialog/confirm_dialog.dart';
import '../../design/widgets/dialog/delete_impact_dialog.dart';
import '../../design/widgets/select/phi_select.dart';
import '../../design/widgets/select/phi_select_option.dart';
import '../../domain/mix/mix_send.dart';
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

  /// Key on a strip's **add-send** picker, by channel name — the target picker
  /// that appends a new aux send when a return is chosen.
  static Key addSendKey(String name) => Key('MixSurface.addSend.$name');

  /// Key on an existing send row's **target picker**, by channel name + slot.
  static Key sendTargetKey(String name, int slot) =>
      Key('MixSurface.sendTarget.$name.$slot');

  /// Key on a send row's **level mini-fader**, by channel name + slot — the
  /// control tests drag to prove gesture-coalesced level edits (one command per
  /// drag).
  static Key sendLevelKey(String name, int slot) =>
      Key('MixSurface.sendLevel.$name.$slot');

  /// Key on a send row's **pre/post toggle**, by channel name + slot.
  static Key sendPrePostKey(String name, int slot) =>
      Key('MixSurface.sendPrePost.$name.$slot');

  /// Key on a send row's **remove** control, by channel name + slot.
  static Key sendRemoveKey(String name, int slot) =>
      Key('MixSurface.sendRemove.$name.$slot');

  /// Key on the returns section container (present only when returns exist).
  static const Key returnsSectionKey = Key('MixSurface.returnsSection');

  /// Key on a return strip's **remove** control, by return name — distinct from
  /// the leaf strips' shared remove key so a test (and the delete-impact flow)
  /// can target a specific return.
  static Key returnRemoveKey(String name) =>
      Key('MixSurface.returnRemove.$name');

  /// Key on a strip's **add-insert** picker, by channel name — the fx picker that
  /// places (or moves) an effect onto the strip's insert chain.
  static Key addInsertKey(String name) => Key('MixSurface.addInsert.$name');

  /// Key on an insert row, by channel name + fx leaf name — the drop target a
  /// reorder drag lands on (drop places the dragged insert immediately before it).
  static Key insertRowKey(String name, String fx) =>
      Key('MixSurface.insertRow.$name.$fx');

  /// Key on an insert row's **drag grip**, by channel name + fx leaf name — the
  /// grip a reorder drag starts from.
  static Key insertDragKey(String name, String fx) =>
      Key('MixSurface.insertDrag.$name.$fx');

  /// Key on an insert row's **remove** control, by channel name + slot.
  static Key insertRemoveKey(String name, int slot) =>
      Key('MixSurface.insertRemove.$name.$slot');

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
                _ReturnsSection(engine: engine),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChannelStrip(
              name: node.channel.name,
              volume: node.channel.volume,
              peak: node.channel.peak,
              muted: node.channel.muted,
              soloed: node.channel.soloed,
              voiceColor: PhiVoices.color(node.channel.voice),
              voiceGlow: PhiVoices.glow(node.channel.voice),
              dragHandle: _DragHandle(
                channel: node.channel,
                address: node.address,
              ),
              onVolumeChanged: (v) => engine.setChannelVolume(node.channel, v),
              onVolumeChangeStart: () =>
                  engine.beginChannelVolumeGesture(node.channel),
              onVolumeChangeEnd: () =>
                  engine.endChannelVolumeGesture(node.channel),
              onMuteToggle: () => engine.setChannelMuted(
                node.channel,
                muted: !node.channel.muted,
              ),
              onSoloToggle: () => engine.setChannelSoloed(
                node.channel,
                soloed: !node.channel.soloed,
              ),
              onRename: (name) => engine.renameChannel(node.channel, name),
              onRemove: () => engine.removeChannel(node.channel),
            ),
            _InsertsArea(engine: engine, channel: node.channel),
            _SendsArea(engine: engine, channel: node.channel),
          ],
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
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChannelStrip(
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
            onVolumeChangeEnd: () =>
                engine.endChannelVolumeGesture(node.channel),
            onMuteToggle: () => engine.setChannelMuted(
              node.channel,
              muted: !node.channel.muted,
            ),
            onSoloToggle: () => engine.setChannelSoloed(
              node.channel,
              soloed: !node.channel.soloed,
            ),
            onRename: (name) => engine.renameChannel(node.channel, name),
            onRemove: () => engine.removeChannel(node.channel),
          ),
          _InsertsArea(engine: engine, channel: node.channel),
          _SendsArea(engine: engine, channel: node.channel),
        ],
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
        // One meter bar per speaker output (design §6): the count follows the
        // live device layout, so a stereo → 5.1 swap re-renders without restart.
        outputPeaks: channel.outputPeaks,
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

/// The compact **INSERTS** area beneath a strip or group-bus header (racks
/// design §5): the bus's ordered `fx.` chain — one [_InsertRow] per placed
/// effect (drag a row's grip onto another to reorder, `×` to remove), plus an
/// [_AddInsertRow] picker while the project defines an fx that isn't already
/// here. Hidden entirely when the channel carries no inserts and no fx is
/// available to place, so a project with no effects shows nothing.
///
/// Reads the chain off the engine (`channelInserts`), which comes from the
/// stored payload, so every structural edit (place / move / reorder / remove)
/// lands through the ordinary journaled payload-command path and re-renders on
/// the ensuing re-sync — the engine's [RackMaterialiser] turns the order into a
/// live `DspObject` chain (issue #208).
class _InsertsArea extends StatelessWidget {
  const _InsertsArea({required this.engine, required this.channel});

  final PhiEngine engine;
  final MixerChannel channel;

  @override
  Widget build(BuildContext context) {
    final inserts = engine.channelInserts(channel);
    final available = engine.availableFxFor(channel);
    if (inserts.isEmpty && available.isEmpty) return const SizedBox.shrink();
    return Container(
      width: ChannelStrip.width,
      margin: const EdgeInsets.only(top: PhiSpacing.s1),
      padding: const EdgeInsets.all(PhiSpacing.s1),
      decoration: BoxDecoration(
        color: PhiColors.bg0,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('INSERTS', style: PhiType.caption()),
          const SizedBox(height: PhiSpacing.s1),
          for (var slot = 0; slot < inserts.length; slot++) ...[
            _InsertRow(
              engine: engine,
              channel: channel,
              slot: slot,
              fx: inserts[slot],
            ),
            const SizedBox(height: PhiSpacing.s1),
          ],
          if (available.isNotEmpty)
            _AddInsertRow(
              engine: engine,
              channel: channel,
              available: available,
            ),
        ],
      ),
    );
  }
}

/// One insert row: a drag grip (reorder) · the fx name + kind · a remove `×`
/// (racks design §5). The whole row is a [DragTarget] so dropping another
/// insert's grip onto it reorders that insert to just before this one; the grip
/// itself is the [Draggable]. Removing detaches the placement (the fx entity
/// survives).
class _InsertRow extends StatelessWidget {
  const _InsertRow({
    required this.engine,
    required this.channel,
    required this.slot,
    required this.fx,
  });

  final PhiEngine engine;
  final MixerChannel channel;
  final int slot;
  final EntityAddress fx;

  @override
  Widget build(BuildContext context) {
    final kind = engine.fxKindOf(fx);
    return DragTarget<EntityAddress>(
      onWillAcceptWithDetails: (details) => details.data != fx,
      onAcceptWithDetails: (details) =>
          engine.moveChannelInsertBefore(channel, details.data, fx),
      builder: (context, candidate, rejected) => Container(
        key: MixSurface.insertRowKey(channel.name, fx.name),
        padding: const EdgeInsets.symmetric(
          horizontal: PhiSpacing.s0,
          vertical: PhiSpacing.s0,
        ),
        decoration: BoxDecoration(
          color: candidate.isNotEmpty ? PhiColors.bg2 : PhiColors.bg1,
          border: Border.all(
            color: candidate.isNotEmpty ? PhiColors.lineHot : PhiColors.line1,
          ),
          borderRadius: PhiRadii.all1,
        ),
        child: Row(
          children: [
            _InsertDragGrip(channel: channel, fx: fx),
            const SizedBox(width: PhiSpacing.s0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fx.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PhiType.monoS().copyWith(color: PhiColors.fg0),
                  ),
                  if (kind != null)
                    Text(
                      kind.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhiType.monoS().copyWith(
                        fontSize: 8,
                        color: PhiColors.fg3,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: PhiSpacing.s0),
            _InsertRemoveButton(
              buttonKey: MixSurface.insertRemoveKey(channel.name, slot),
              onPressed: () => engine.removeChannelInsert(channel, slot),
            ),
          ],
        ),
      ),
    );
  }
}

/// The grip that starts a reorder drag on an insert row. Its feedback is a
/// compact floating chip of the fx name, mirroring the strip drag handle.
class _InsertDragGrip extends StatelessWidget {
  const _InsertDragGrip({required this.channel, required this.fx});

  final MixerChannel channel;
  final EntityAddress fx;

  @override
  Widget build(BuildContext context) {
    return Draggable<EntityAddress>(
      data: fx,
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
            fx.name,
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
          ),
        ),
      ),
      childWhenDragging: const Icon(
        Icons.drag_indicator,
        size: 12,
        color: PhiColors.line2,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Icon(
          Icons.drag_indicator,
          key: MixSurface.insertDragKey(channel.name, fx.name),
          size: 12,
          color: PhiColors.fg3,
        ),
      ),
    );
  }
}

/// The add-insert picker: the fx instances that can be placed on this bus. An fx
/// already on **another** bus is offered with an `· on {bus}` annotation —
/// choosing it *moves* it here behind a [ConfirmDialog] naming the losing bus
/// (racks design §5, "an instance lives on at most one bus"). An unplaced fx is
/// appended straight to the chain.
class _AddInsertRow extends StatelessWidget {
  const _AddInsertRow({
    required this.engine,
    required this.channel,
    required this.available,
  });

  final PhiEngine engine;
  final MixerChannel channel;
  final List<EntityAddress> available;

  Future<void> _place(BuildContext context, EntityAddress fx) async {
    final owner = engine.busHoldingInsert(fx);
    if (owner != null) {
      final confirmed = await ConfirmDialog.show(
        context,
        title: 'move insert',
        message:
            '${fx.name} is on ${owner.name}. Moving it to ${channel.name} '
            'removes it from ${owner.name}.',
        confirmLabel: 'move',
      );
      if (!confirmed) return;
    }
    engine.addChannelInsert(channel, fx);
  }

  @override
  Widget build(BuildContext context) {
    return PhiSelect<EntityAddress>.flat(
      key: MixSurface.addInsertKey(channel.name),
      value: null,
      placeholder: '+ insert',
      options: [
        for (final fx in available)
          PhiSelectOption<EntityAddress>(value: fx, label: _labelFor(fx)),
      ],
      onChanged: (fx) => _place(context, fx),
    );
  }

  /// The picker label for [fx]: its leaf name, annotated with the bus it sits on
  /// when it is placed elsewhere (so the performer knows a pick will move it).
  String _labelFor(EntityAddress fx) {
    final owner = engine.busHoldingInsert(fx);
    return owner == null ? fx.name : '${fx.name} · on ${owner.name}';
  }
}

/// An insert row's remove control — a small `×` box mirroring the send row's
/// remove affordance. Clearing detaches the placement (racks design §5).
class _InsertRemoveButton extends StatelessWidget {
  const _InsertRemoveButton({required this.buttonKey, required this.onPressed});

  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          key: buttonKey,
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PhiColors.bg0,
            border: Border.all(color: PhiColors.line1),
            borderRadius: PhiRadii.all1,
          ),
          child: Text(
            '×',
            style: PhiType.monoS().copyWith(color: PhiColors.fg2, height: 1),
          ),
        ),
      ),
    );
  }
}

/// The compact **SENDS** area beneath a strip or group-bus header (design §4,
/// §7): one [_SendRow] per stored aux send, plus an [_AddSendRow] while there is
/// a return to target (send slots have no cap — the engine auto-upgrades). Hidden
/// entirely when the channel has no sends and there are no returns to send to.
///
/// Reads the sends off the engine (`channelSends`), which come from the stored
/// payload, so structural send edits (add / edit target / pre-post / remove) all
/// land through the ordinary payload-command path and re-render on the ensuing
/// re-sync; a live *level* drag holds its transient value inside the mini-fader.
class _SendsArea extends StatelessWidget {
  const _SendsArea({required this.engine, required this.channel});

  final PhiEngine engine;
  final MixerChannel channel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MixerChannel>>(
      valueListenable: engine.returns,
      builder: (context, returns, _) {
        final sends = engine.channelSends(channel);
        if (sends.isEmpty && returns.isEmpty) return const SizedBox.shrink();
        return Container(
          width: ChannelStrip.width,
          margin: const EdgeInsets.only(top: PhiSpacing.s1),
          padding: const EdgeInsets.all(PhiSpacing.s1),
          decoration: BoxDecoration(
            color: PhiColors.bg0,
            border: Border.all(color: PhiColors.line1),
            borderRadius: PhiRadii.all1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SENDS', style: PhiType.caption()),
              const SizedBox(height: PhiSpacing.s1),
              for (var slot = 0; slot < sends.length; slot++) ...[
                _SendRow(
                  engine: engine,
                  channel: channel,
                  slot: slot,
                  send: sends[slot],
                  returns: returns,
                ),
                const SizedBox(height: PhiSpacing.s1),
              ],
              if (returns.isNotEmpty)
                _AddSendRow(
                  engine: engine,
                  channel: channel,
                  slot: sends.length,
                  returns: returns,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One aux-send row: target picker (returns only) · level mini-fader · pre/post
/// toggle · remove (design §4). Editing the target rewires the slot through the
/// engine sync; the level fader drags are gesture-coalesced; removing clears the
/// slot.
class _SendRow extends StatelessWidget {
  const _SendRow({
    required this.engine,
    required this.channel,
    required this.slot,
    required this.send,
    required this.returns,
  });

  final PhiEngine engine;
  final MixerChannel channel;
  final int slot;
  final MixSend send;
  final List<MixerChannel> returns;

  @override
  Widget build(BuildContext context) {
    // The materialised return this send currently targets — `null` only when the
    // return has gone (a dangling target), in which case the picker falls back to
    // naming the stored address and the pre/post toggle is inert.
    final target = engine.returnChannelFor(send.to);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PhiSelect<MixerChannel>.flat(
          key: MixSurface.sendTargetKey(channel.name, slot),
          value: target,
          placeholder: send.to.name,
          options: [
            for (final r in returns)
              PhiSelectOption<MixerChannel>(value: r, label: r.name),
          ],
          onChanged: (r) => engine.setChannelSend(
            channel,
            slot,
            returnBus: r,
            level: send.level,
            preFader: send.preFader,
          ),
        ),
        const SizedBox(height: PhiSpacing.s0),
        _SendLevelFader(
          key: MixSurface.sendLevelKey(channel.name, slot),
          level: send.level,
          onChangeStart: () => engine.beginSendLevelGesture(channel, slot),
          onChanged: (v) => engine.setChannelSendLevel(channel, slot, v),
          onChangeEnd: () => engine.endSendLevelGesture(channel, slot),
        ),
        const SizedBox(height: PhiSpacing.s0),
        Row(
          children: [
            Expanded(
              child: _PrePostToggle(
                key: MixSurface.sendPrePostKey(channel.name, slot),
                preFader: send.preFader,
                onToggle: target == null
                    ? null
                    : () => engine.setChannelSend(
                        channel,
                        slot,
                        returnBus: target,
                        level: send.level,
                        preFader: !send.preFader,
                      ),
              ),
            ),
            const SizedBox(width: PhiSpacing.s0),
            _SendRemoveButton(
              buttonKey: MixSurface.sendRemoveKey(channel.name, slot),
              onPressed: () => engine.clearChannelSend(channel, slot),
            ),
          ],
        ),
      ],
    );
  }
}

/// The add-send row: a placeholder picker of the available returns. Picking one
/// appends a fresh unity, post-fader send at the next slot (design §4 — slots
/// auto-upgrade, so there is no cap and the row is always available while a
/// return exists to target).
class _AddSendRow extends StatelessWidget {
  const _AddSendRow({
    required this.engine,
    required this.channel,
    required this.slot,
    required this.returns,
  });

  final PhiEngine engine;
  final MixerChannel channel;
  final int slot;
  final List<MixerChannel> returns;

  @override
  Widget build(BuildContext context) {
    return PhiSelect<MixerChannel>.flat(
      key: MixSurface.addSendKey(channel.name),
      value: null,
      placeholder: '+ send',
      options: [
        for (final r in returns)
          PhiSelectOption<MixerChannel>(value: r, label: r.name),
      ],
      onChanged: (r) => engine.setChannelSend(
        channel,
        slot,
        returnBus: r,
        level: 1.0,
        preFader: false,
      ),
    );
  }
}

/// A compact send-level mini-fader. A **vertical** drag adjusts the level (drag
/// up to raise) — matching the main fader's axis so it never fights the rack's
/// horizontal scroll — and holds a transient value while the drag is live, so the
/// display tracks the gesture even though the engine defers the journal write to
/// the release (gesture coalescing, design §4).
class _SendLevelFader extends StatefulWidget {
  const _SendLevelFader({
    required this.level,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  /// The committed send level in `[0, 1]` — shown whenever no drag is live.
  final double level;

  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  State<_SendLevelFader> createState() => _SendLevelFaderState();
}

class _SendLevelFaderState extends State<_SendLevelFader> {
  /// The transient value while a drag is live; `null` when idle (display then
  /// follows the committed [_SendLevelFader.level]).
  double? _dragValue;

  static const double _height = 16;

  /// Vertical pixels of travel that span the full `0 → 1` range.
  static const double _travel = 120;

  double get _value => (_dragValue ?? widget.level).clamp(0.0, 1.0);

  void _start(DragStartDetails _) {
    widget.onChangeStart();
    setState(() => _dragValue = widget.level);
  }

  void _update(DragUpdateDetails d) {
    final next = ((_dragValue ?? widget.level) - d.delta.dy / _travel).clamp(
      0.0,
      1.0,
    );
    setState(() => _dragValue = next);
    widget.onChanged(next);
  }

  void _end([DragEndDetails? _]) {
    widget.onChangeEnd();
    setState(() => _dragValue = null);
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _start,
        onVerticalDragUpdate: _update,
        onVerticalDragEnd: _end,
        child: SizedBox(
          height: _height,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: PhiColors.bg2,
                    border: Border.all(color: PhiColors.line1),
                    borderRadius: PhiRadii.all1,
                  ),
                ),
              ),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value,
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: PhiColors.voice1,
                    borderRadius: PhiRadii.all1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A send's pre/post-fader toggle: highlighted `PRE` when the send is taken
/// pre-fader, dim `POST` otherwise (post is the default, design §2). Inert (no
/// tap) when the send's target has gone.
class _PrePostToggle extends StatelessWidget {
  const _PrePostToggle({
    required this.preFader,
    required this.onToggle,
    super.key,
  });

  final bool preFader;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onToggle == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: preFader ? PhiColors.bg3 : PhiColors.bg0,
            border: Border.all(
              color: preFader ? PhiColors.voice3 : PhiColors.line1,
            ),
            borderRadius: PhiRadii.all1,
          ),
          child: Text(
            preFader ? 'PRE' : 'POST',
            style: PhiType.monoS().copyWith(
              fontSize: 8,
              color: preFader ? PhiColors.voice3 : PhiColors.fg2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A send row's remove control — a small `×` box mirroring the strip's own
/// remove affordance. Clearing the send detaches its slot (design §4).
class _SendRemoveButton extends StatelessWidget {
  const _SendRemoveButton({required this.buttonKey, required this.onPressed});

  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          key: buttonKey,
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PhiColors.bg0,
            border: Border.all(color: PhiColors.line1),
            borderRadius: PhiRadii.all1,
          ),
          child: Text(
            '×',
            style: PhiType.monoS().copyWith(color: PhiColors.fg2, height: 1),
          ),
        ),
      ),
    );
  }
}

/// The returns section pinned beside master (design §4, §7): a framed column of
/// one [_ReturnStrip] per return bus. Rendered only when returns exist, so a
/// project with none shows nothing here.
class _ReturnsSection extends StatelessWidget {
  const _ReturnsSection({required this.engine});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MixerChannel>>(
      valueListenable: engine.returns,
      builder: (context, returns, _) {
        if (returns.isEmpty) return const SizedBox.shrink();
        return Container(
          key: MixSurface.returnsSectionKey,
          margin: const EdgeInsets.only(right: PhiSpacing.s2),
          padding: const EdgeInsets.all(PhiSpacing.s2),
          decoration: BoxDecoration(
            color: PhiColors.bg0,
            border: Border.all(color: PhiColors.line2),
            borderRadius: PhiRadii.all1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('RETURNS', style: PhiType.caption()),
              const SizedBox(height: PhiSpacing.s1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in returns) ...[
                    _ReturnStrip(engine: engine, channel: r),
                    const SizedBox(width: PhiSpacing.s1),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A single return strip: fader, mute, meter — **no solo** (returns are exempt,
/// design §5) and no drag handle (returns sit outside the tree). Renaming rewires
/// every send targeting it (the ordinary rename-refactor); removing it goes
/// through the **delete-impact dialog** (design §7) when strips still send to it
/// — the warning lists those senders and confirming clears their sends before
/// the return is removed. A return nobody sends to removes without a prompt.
class _ReturnStrip extends StatelessWidget {
  const _ReturnStrip({required this.engine, required this.channel});

  final PhiEngine engine;
  final MixerChannel channel;

  /// Warn-then-remove: if any strip still sends to this return, raise the
  /// delete-impact dialog listing them and, on confirm, clear those sends and
  /// remove the return; otherwise remove it outright. The clear + remove is one
  /// engine call so it journals as a unit.
  Future<void> _remove(BuildContext context) async {
    final impact = engine.channelRemovalImpact(channel);
    if (impact.hasReferrers) {
      final confirmed = await DeleteImpactDialog.show(
        context,
        title: 'delete return',
        message:
            '${channel.name} still receives these sends — '
            'deleting it clears them:',
        referrers: [for (final r in impact.referrers) r.format()],
      );
      if (!confirmed) return;
    }
    engine.removeChannelClearingSenders(channel);
  }

  @override
  Widget build(BuildContext context) {
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
        soloable: false,
        removeKey: MixSurface.returnRemoveKey(channel.name),
        onVolumeChanged: (v) => engine.setChannelVolume(channel, v),
        onVolumeChangeStart: () => engine.beginChannelVolumeGesture(channel),
        onVolumeChangeEnd: () => engine.endChannelVolumeGesture(channel),
        onMuteToggle: () =>
            engine.setChannelMuted(channel, muted: !channel.muted),
        onRename: (name) => engine.renameChannel(channel, name),
        onRemove: () => _remove(context),
      ),
    );
  }
}
