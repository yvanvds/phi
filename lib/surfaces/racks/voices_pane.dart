import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../design/widgets/dialog/confirm_dialog.dart';
import '../../design/widgets/dialog/delete_impact_dialog.dart';
import '../../design/widgets/select/phi_select.dart';
import '../../design/widgets/select/phi_select_option.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/voice/voice_definition.dart';
import '../../domain/voice/voice_kind.dart';
import '../../engine/state/rack_definitions_controller.dart';
import '../../engine/state/rack_voice_row.dart';
import '../../engine/state/voice_audition_controller.dart';

/// The racks surface's right **voices pane** (issue #211, design
/// `docs/design/racks-and-voices.md` §7, §8) — one editable row per `voice.`
/// entity, plus a one-octave test strip.
///
/// Each row binds a voice: its name (address leaf), a **kind** toggle
/// (internal / external + channel), the **synth** definition it instantiates (or
/// the external MIDI channel it plays), the **bus** it routes to, and its
/// **colour** (six quick-pick swatches). An **arm** toggle (one voice at a time)
/// makes MIDI-in play that voice immediately; the pane's one-octave test strip
/// does the same from the mouse. All editing threads through the
/// [RackDefinitionsController]'s journaled command layer; arming and audition go
/// through the [VoiceAuditionController].
///
/// The [audition] seam is `null` only in bare tests / projects with no MIDI
/// subsystem — arming and the test strip are then disabled, but every row still
/// renders and edits.
class VoicesPane extends StatefulWidget {
  const VoicesPane({required this.controller, this.audition, super.key});

  final RackDefinitionsController controller;

  /// Arm + audition seam (issue #211). `null` disables arming and the test strip
  /// (no MIDI subsystem wired); row editing stays fully live.
  final VoiceAuditionController? audition;

  /// Fixed pane width — the right column of the three-pane racks layout.
  static const double width = 264;

  /// Key on a voice row, by address — so tests can find a specific voice.
  static Key rowKey(EntityAddress address) =>
      Key('VoicesPane.row.${address.format()}');

  /// Key on the header add-voice `+` button.
  static const Key addKey = Key('VoicesPane.add');

  /// Key on a row's arm toggle, by address.
  static Key armKey(EntityAddress address) =>
      Key('VoicesPane.arm.${address.format()}');

  /// Key on a row's context-menu (`⋯`) button, by address.
  static Key menuKey(EntityAddress address) =>
      Key('VoicesPane.menu.${address.format()}');

  /// Key on a row's kind segment (`internal` / `external`), by address + kind.
  static Key kindKey(EntityAddress address, VoiceKind kind) =>
      Key('VoicesPane.kind.${address.format()}.${kind.name}');

  /// Key on a row's synth picker, by address.
  static Key synthKey(EntityAddress address) =>
      Key('VoicesPane.synth.${address.format()}');

  /// Key on a row's bus picker, by address.
  static Key busKey(EntityAddress address) =>
      Key('VoicesPane.bus.${address.format()}');

  /// Key on a row's external-channel picker, by address.
  static Key channelKey(EntityAddress address) =>
      Key('VoicesPane.channel.${address.format()}');

  /// Key on a row's colour quick-pick swatch, by address + `voice1..voice6`.
  static Key colorKey(EntityAddress address, String token) =>
      Key('VoicesPane.color.${address.format()}.$token');

  /// Key on a test-strip key, by MIDI note number.
  static Key testKeyKey(int note) => Key('VoicesPane.testKey.$note');

  @override
  State<VoicesPane> createState() => _VoicesPaneState();
}

class _VoicesPaneState extends State<VoicesPane> {
  RackDefinitionsController get _controller => widget.controller;
  VoiceAuditionController? get _audition => widget.audition;

  @override
  Widget build(BuildContext context) {
    final audition = _audition;
    final listenable = audition == null
        ? _controller
        : Listenable.merge([_controller, audition]);
    return Container(
      width: VoicesPane.width,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(left: BorderSide(color: PhiColors.line1)),
      ),
      child: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final voices = _controller.voices;
          final armed = audition?.armed;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Expanded(
                child: voices.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(PhiSpacing.s3),
                        child: Text(
                          'no voices — use + to add one',
                          style: PhiType.monoS().copyWith(color: PhiColors.fg3),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                          vertical: PhiSpacing.s1,
                        ),
                        children: [
                          for (final voice in voices)
                            _VoiceCard(
                              voice: voice,
                              synthOptions: _controller.synthDefinitions,
                              busOptions: _controller.mixBuses,
                              armed: armed == voice.address,
                              canArm: audition != null,
                              onArm: audition == null
                                  ? null
                                  : () => audition.toggleArm(voice.address),
                              onMenu: (position) =>
                                  _openRowMenu(voice, position),
                              onKind: (kind) => _setKind(voice.address, kind),
                              onSynth: (synth) =>
                                  _setSynth(voice.address, synth),
                              onBus: (bus) => _setOutput(voice.address, bus),
                              onChannel: (channel) =>
                                  _setChannel(voice.address, channel),
                              onColor: (token) =>
                                  _setColor(voice.address, token),
                            ),
                        ],
                      ),
              ),
              _TestStrip(audition: audition, armed: armed),
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.only(left: PhiSpacing.s3),
      height: 28,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'voices'.toUpperCase(),
                style: PhiType.caption().copyWith(color: PhiColors.fg1),
              ),
            ),
          ),
          _IconButton(
            buttonKey: VoicesPane.addKey,
            icon: Icons.add,
            tooltip: 'add voice',
            onTap: () => _controller.newVoice(),
          ),
        ],
      ),
    );
  }

  // ── edits ────────────────────────────────────────────────────────────────

  void _setSynth(EntityAddress address, EntityAddress synth) {
    final voice = _controller.voiceAt(address);
    if (voice == null) return;
    _controller.updateVoice(address, voice.copyWith(synth: synth));
  }

  void _setOutput(EntityAddress address, EntityAddress bus) {
    final voice = _controller.voiceAt(address);
    if (voice == null) return;
    _controller.updateVoice(address, voice.copyWith(output: bus));
  }

  void _setColor(EntityAddress address, String token) {
    final voice = _controller.voiceAt(address);
    if (voice == null) return;
    _controller.updateVoice(address, voice.copyWith(color: token));
  }

  void _setChannel(EntityAddress address, int channel) {
    final voice = _controller.voiceAt(address);
    if (voice == null || voice.kind != VoiceKind.external) return;
    _controller.updateVoice(address, voice.copyWith(channel: channel));
  }

  /// Switch a voice between internal and external — [copyWith] keeps a voice's
  /// kind, so a kind flip builds a fresh definition of the target kind, carrying
  /// the bus + colour across. Internal reuses the voice's old synth (or the first
  /// available definition); external reuses its old channel (or 1). A flip to
  /// internal with no synth definitions is a no-op (nothing to play).
  void _setKind(EntityAddress address, VoiceKind kind) {
    final voice = _controller.voiceAt(address);
    if (voice == null || voice.kind == kind) return;
    switch (kind) {
      case VoiceKind.internal:
        final synths = _controller.synthDefinitions;
        final synth = voice.synth ?? (synths.isEmpty ? null : synths.first);
        if (synth == null) return;
        _controller.updateVoice(
          address,
          VoiceDefinition.internal(
            synth: synth,
            output: voice.output,
            color: voice.color,
          ),
        );
      case VoiceKind.external:
        _controller.updateVoice(
          address,
          VoiceDefinition.external(
            channel: voice.channel ?? 1,
            output: voice.output,
            color: voice.color,
          ),
        );
    }
  }

  // ── row menu (rename / delete) ─────────────────────────────────────────────

  Future<void> _openRowMenu(RackVoiceRow voice, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final action = await showMenu<_VoiceAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      color: PhiColors.bg2,
      items: [
        for (final a in _VoiceAction.values)
          PopupMenuItem<_VoiceAction>(
            value: a,
            height: 34,
            child: Text(
              a.label,
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            ),
          ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _VoiceAction.rename:
        await _renameVoice(voice);
      case _VoiceAction.delete:
        await _deleteVoice(voice);
    }
  }

  Future<void> _renameVoice(RackVoiceRow voice) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: voice.name),
    );
    if (name == null || name.trim().isEmpty) return;
    _controller.rename(voice.address, name);
  }

  Future<void> _deleteVoice(RackVoiceRow voice) async {
    final impact = _controller.impactOf(voice.address);
    final bool confirmed;
    if (impact.hasReferrers) {
      confirmed = await DeleteImpactDialog.show(
        context,
        title: 'delete voice',
        message:
            '${voice.name} is still referenced — deleting it strands these:',
        referrers: [for (final r in impact.referrers) r.format()],
      );
    } else {
      confirmed = await ConfirmDialog.show(
        context,
        title: 'delete voice',
        message: 'Delete "${voice.name}"?',
        confirmLabel: 'delete',
      );
    }
    if (!confirmed) return;
    // Drop the arm if it targeted the deleted voice, so no stale voice stays
    // armed after it's gone.
    if (_audition?.armed == voice.address) _audition?.disarm();
    _controller.delete(voice.address);
  }
}

/// The per-row context-menu actions.
enum _VoiceAction {
  rename('rename…'),
  delete('delete');

  const _VoiceAction(this.label);

  final String label;
}

/// One editable voice card: colour swatch + name + arm, a kind toggle, the
/// synth / channel + bus pickers, and the colour quick-picks.
class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.synthOptions,
    required this.busOptions,
    required this.armed,
    required this.canArm,
    required this.onArm,
    required this.onMenu,
    required this.onKind,
    required this.onSynth,
    required this.onBus,
    required this.onChannel,
    required this.onColor,
  });

  final RackVoiceRow voice;
  final List<EntityAddress> synthOptions;
  final List<EntityAddress> busOptions;
  final bool armed;
  final bool canArm;
  final VoidCallback? onArm;
  final void Function(Offset globalPosition) onMenu;
  final ValueChanged<VoiceKind> onKind;
  final ValueChanged<EntityAddress> onSynth;
  final ValueChanged<EntityAddress> onBus;
  final ValueChanged<int> onChannel;
  final ValueChanged<String> onColor;

  static String _label(EntityAddress address) => address.segments.join(' / ');

  @override
  Widget build(BuildContext context) {
    final internal = voice.kind == VoiceKind.internal;
    return Container(
      key: VoicesPane.rowKey(voice.address),
      margin: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s2,
        vertical: PhiSpacing.s1,
      ),
      padding: const EdgeInsets.all(PhiSpacing.s2),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.all2,
        border: Border.all(color: armed ? PhiColors.lineHot : PhiColors.line1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleRow(context),
          const SizedBox(height: PhiSpacing.s2),
          _KindToggle(
            address: voice.address,
            kind: voice.kind,
            canGoInternal: synthOptions.isNotEmpty || voice.synth != null,
            onKind: onKind,
          ),
          const SizedBox(height: PhiSpacing.s2),
          if (internal) _synthPicker() else _channelPicker(),
          const SizedBox(height: PhiSpacing.s1),
          _busPicker(),
          const SizedBox(height: PhiSpacing.s2),
          _ColorSwatches(
            address: voice.address,
            selected: voice.colorToken,
            onColor: onColor,
          ),
        ],
      ),
    );
  }

  Widget _titleRow(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _swatch(voice.colorToken),
            borderRadius: PhiRadii.all1,
          ),
        ),
        const SizedBox(width: PhiSpacing.s2),
        Expanded(
          child: Text(
            voice.name,
            overflow: TextOverflow.ellipsis,
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
          ),
        ),
        _ArmButton(address: voice.address, armed: armed, onTap: onArm),
        const SizedBox(width: PhiSpacing.s1),
        _IconButton(
          buttonKey: VoicesPane.menuKey(voice.address),
          icon: Icons.more_horiz,
          tooltip: 'more…',
          onTap: () {
            final box = context.findRenderObject() as RenderBox?;
            final at = box == null
                ? Offset.zero
                : box.localToGlobal(box.size.center(Offset.zero));
            onMenu(at);
          },
        ),
      ],
    );
  }

  Widget _synthPicker() {
    return PhiSelect<EntityAddress>.flat(
      key: VoicesPane.synthKey(voice.address),
      value: voice.synth,
      placeholder: 'no synth',
      options: [
        for (final synth in synthOptions)
          PhiSelectOption(value: synth, label: _label(synth)),
      ],
      onChanged: onSynth,
    );
  }

  Widget _channelPicker() {
    return PhiSelect<int>.flat(
      key: VoicesPane.channelKey(voice.address),
      value: voice.channel,
      placeholder: 'channel',
      options: [
        for (var ch = 1; ch <= 16; ch++)
          PhiSelectOption(value: ch, label: 'ch $ch'),
      ],
      onChanged: onChannel,
    );
  }

  Widget _busPicker() {
    return Row(
      children: [
        Text('→ ', style: PhiType.monoS().copyWith(color: PhiColors.fg2)),
        Expanded(
          child: PhiSelect<EntityAddress>.flat(
            key: VoicesPane.busKey(voice.address),
            value: voice.output,
            placeholder: 'no bus',
            options: [
              for (final bus in busOptions)
                PhiSelectOption(value: bus, label: _label(bus)),
            ],
            onChanged: onBus,
          ),
        ),
      ],
    );
  }
}

/// Resolves a voice colour token (`voice1..voice6`) to its swatch, defaulting to
/// the first swatch for any other/opaque token.
Color _swatch(String token) {
  const prefix = 'voice';
  if (token.startsWith(prefix)) {
    final index = int.tryParse(token.substring(prefix.length));
    if (index != null) return PhiVoices.color(index);
  }
  return PhiVoices.color(1);
}

/// The internal / external segmented toggle.
class _KindToggle extends StatelessWidget {
  const _KindToggle({
    required this.address,
    required this.kind,
    required this.canGoInternal,
    required this.onKind,
  });

  final EntityAddress address;
  final VoiceKind kind;
  final bool canGoInternal;
  final ValueChanged<VoiceKind> onKind;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _segment(VoiceKind.internal, 'internal', enabled: canGoInternal),
        const SizedBox(width: PhiSpacing.s1),
        _segment(VoiceKind.external, 'external', enabled: true),
      ],
    );
  }

  Widget _segment(
    VoiceKind segmentKind,
    String label, {
    required bool enabled,
  }) {
    final selected = kind == segmentKind;
    return Expanded(
      child: GestureDetector(
        key: VoicesPane.kindKey(address, segmentKind),
        behavior: HitTestBehavior.opaque,
        onTap: enabled && !selected ? () => onKind(segmentKind) : null,
        child: Container(
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? PhiColors.bg3 : null,
            borderRadius: PhiRadii.all1,
            border: Border.all(
              color: selected ? PhiColors.line2 : PhiColors.line1,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: PhiType.caption().copyWith(
              color: selected
                  ? PhiColors.fg0
                  : enabled
                  ? PhiColors.fg2
                  : PhiColors.fg3,
            ),
          ),
        ),
      ),
    );
  }
}

/// The six colour quick-picks (`voice1..voice6`), the selected one ringed.
class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({
    required this.address,
    required this.selected,
    required this.onColor,
  });

  final EntityAddress address;
  final String selected;
  final ValueChanged<String> onColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 6; i++) ...[
          if (i > 1) const SizedBox(width: PhiSpacing.s1),
          Expanded(child: _swatchButton(i)),
        ],
      ],
    );
  }

  Widget _swatchButton(int index) {
    final token = 'voice$index';
    final isSelected = token == selected;
    return GestureDetector(
      key: VoicesPane.colorKey(address, token),
      behavior: HitTestBehavior.opaque,
      onTap: () => onColor(token),
      child: Container(
        height: 16,
        decoration: BoxDecoration(
          color: PhiVoices.color(index),
          borderRadius: PhiRadii.all1,
          border: Border.all(
            color: isSelected ? PhiColors.fg0 : PhiColors.line1,
            width: isSelected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// A voice's arm toggle — lit when armed. Disabled (dim, no-op) when no audition
/// seam is wired.
class _ArmButton extends StatelessWidget {
  const _ArmButton({
    required this.address,
    required this.armed,
    required this.onTap,
  });

  final EntityAddress address;
  final bool armed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final Color background = armed ? PhiColors.voice1 : PhiColors.bg3;
    final Color textColor = armed
        ? PhiColors.bg0
        : enabled
        ? PhiColors.fg2
        : PhiColors.fg3;
    return GestureDetector(
      key: VoicesPane.armKey(address),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Tooltip(
        message: armed ? 'armed for MIDI-in' : 'arm for MIDI-in',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: PhiRadii.all1,
            border: Border.all(
              color: armed ? PhiColors.voice1 : PhiColors.line1,
            ),
          ),
          child: Text(
            'ARM',
            style: PhiType.caption().copyWith(color: textColor),
          ),
        ),
      ),
    );
  }
}

/// The one-octave on-screen test strip (design §7, §8): pressing a key sounds
/// the **armed** voice from the mouse, exactly as MIDI-in does. Disabled with a
/// hint until a voice is armed.
class _TestStrip extends StatefulWidget {
  const _TestStrip({required this.audition, required this.armed});

  final VoiceAuditionController? audition;
  final EntityAddress? armed;

  @override
  State<_TestStrip> createState() => _TestStripState();
}

class _TestStripState extends State<_TestStrip> {
  /// The one-octave range shown — C4 (60) up to B4 (71).
  static const int _base = 60;
  static const int _count = 12;

  /// Semitone offsets that are black keys within an octave.
  static const Set<int> _black = {1, 3, 6, 8, 10};

  int? _pressed;

  bool get _enabled => widget.audition != null && widget.armed != null;

  void _press(int note) {
    if (!_enabled) return;
    setState(() => _pressed = note);
    widget.audition!.pressKey(note);
  }

  void _release(int note) {
    if (widget.audition == null) return;
    if (_pressed == note) setState(() => _pressed = null);
    widget.audition!.releaseKey(note);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(PhiSpacing.s2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PhiColors.line1)),
      ),
      child: _enabled
          ? Row(
              children: [
                for (var i = 0; i < _count; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(child: _key(_base + i, _black.contains(i))),
                ],
              ],
            )
          : Center(
              child: Text(
                'arm a voice to audition',
                style: PhiType.caption().copyWith(color: PhiColors.fg3),
              ),
            ),
    );
  }

  Widget _key(int note, bool black) {
    final down = _pressed == note;
    final Color color = down
        ? PhiColors.voice1
        : black
        ? PhiColors.bg0
        : PhiColors.bg3;
    return Listener(
      onPointerDown: (_) => _press(note),
      onPointerUp: (_) => _release(note),
      onPointerCancel: (_) => _release(note),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          key: VoicesPane.testKeyKey(note),
          decoration: BoxDecoration(
            color: color,
            borderRadius: PhiRadii.all1,
            border: Border.all(color: PhiColors.line1),
          ),
        ),
      ),
    );
  }
}

/// A compact square icon button styled to the pane's chrome (mirrors the
/// definitions panel's button).
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.buttonKey,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(icon, size: 15, color: PhiColors.fg2),
          ),
        ),
      ),
    );
  }
}

/// Modal that renames a voice (mirrors the definitions panel's rename dialog).
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'rename voice',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: PhiType.monoS().copyWith(color: PhiColors.fg0),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('rename')),
      ],
    );
  }
}
