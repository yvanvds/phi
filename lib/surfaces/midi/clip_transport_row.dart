import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/toggle/phi_toggle.dart';
import '../../design/widgets/transport_button/transport_button.dart';

/// Play / pause / stop / loop wiring for the clip currently open in the editor,
/// plus the loop-flag state, driven by the header transport row (issue #190).
///
/// `null` on the row hides the transport buttons — a viewport without a live
/// session (a bare widget-test setup) still shows the length fields and the
/// auto-extend toggle, but has no transport to drive.
class ClipTransportControls {
  const ClipTransportControls({
    required this.isPlaying,
    required this.isPaused,
    required this.loop,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onToggleLoop,
  });

  final bool isPlaying;
  final bool isPaused;
  final bool loop;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onToggleLoop;
}

/// The editor header's **transport + length row** (issue #190, design §5): the
/// clip's length authority (editable `bars × beats-per-bar`), the auto-extend
/// toggle, and — when a session is live — the play / pause / stop / loop
/// transport for the edited clip.
///
/// The length fields and auto-extend toggle are always present (they act on the
/// [ClipEditor], which the viewport always owns); the transport cluster shows
/// only when [transport] is wired.
class ClipTransportRow extends StatelessWidget {
  const ClipTransportRow({
    required this.bars,
    required this.beatsPerBar,
    required this.autoExtend,
    required this.onBarsChanged,
    required this.onBeatsPerBarChanged,
    required this.onAutoExtendChanged,
    this.transport,
    super.key,
  });

  final int bars;
  final int beatsPerBar;
  final bool autoExtend;
  final ValueChanged<int> onBarsChanged;
  final ValueChanged<int> onBeatsPerBarChanged;
  final ValueChanged<bool> onAutoExtendChanged;

  /// The edited clip's transport seam, or `null` when no session is live.
  final ClipTransportControls? transport;

  /// Keys so tests can drive each control.
  static const Key barsFieldKey = Key('ClipTransportRow.bars');
  static const Key beatsPerBarFieldKey = Key('ClipTransportRow.beatsPerBar');
  static const Key autoExtendKey = Key('ClipTransportRow.autoExtend');
  static const Key playKey = Key('ClipTransportRow.play');
  static const Key pauseKey = Key('ClipTransportRow.pause');
  static const Key stopKey = Key('ClipTransportRow.stop');
  static const Key loopKey = Key('ClipTransportRow.loop');

  @override
  Widget build(BuildContext context) {
    final controls = transport;
    return Row(
      children: [
        const _Label('length'),
        const SizedBox(width: 6),
        _LengthField(
          fieldKey: barsFieldKey,
          value: bars,
          onChanged: onBarsChanged,
        ),
        Text('×', style: PhiType.monoS().copyWith(color: PhiColors.fg3)),
        _LengthField(
          fieldKey: beatsPerBarFieldKey,
          value: beatsPerBar,
          onChanged: onBeatsPerBarChanged,
        ),
        const SizedBox(width: 6),
        Text(
          'bars × beats',
          style: PhiType.monoS().copyWith(color: PhiColors.fg3),
        ),
        const SizedBox(width: 16),
        const _Label('auto-extend'),
        const SizedBox(width: 6),
        PhiToggle(
          key: autoExtendKey,
          value: autoExtend,
          onChanged: onAutoExtendChanged,
        ),
        const Spacer(),
        if (controls != null) ...[
          TransportButton(
            key: playKey,
            icon: Icons.play_arrow,
            tooltip: controls.isPaused ? 'resume' : 'play',
            isActive: controls.isPlaying,
            onPressed: controls.onPlay,
          ),
          const SizedBox(width: 6),
          TransportButton(
            key: pauseKey,
            icon: Icons.pause,
            tooltip: 'pause',
            isActive: controls.isPaused,
            onPressed: controls.onPause,
          ),
          const SizedBox(width: 6),
          TransportButton(
            key: stopKey,
            icon: Icons.stop,
            tooltip: 'stop',
            onPressed: controls.onStop,
          ),
          const SizedBox(width: 6),
          TransportButton(
            key: loopKey,
            icon: Icons.loop,
            tooltip: controls.loop ? 'loop on' : 'loop off',
            isActive: controls.loop,
            onPressed: controls.onToggleLoop,
          ),
        ],
      ],
    );
  }
}

/// A dim caption naming a control cluster in the transport row.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: PhiType.monoS().copyWith(
        color: PhiColors.fg3,
        fontSize: 9,
        letterSpacing: 0.08 * 9,
      ),
    );
  }
}

/// A compact editable integer field for a length dimension. Commits the parsed
/// value on Enter or on blur; a blank or unparseable entry (or one below 1)
/// reverts to the current [value].
class _LengthField extends StatefulWidget {
  const _LengthField({
    required this.value,
    required this.onChanged,
    required this.fieldKey,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final Key fieldKey;

  @override
  State<_LengthField> createState() => _LengthFieldState();
}

class _LengthFieldState extends State<_LengthField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _LengthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the field showing the authoritative value whenever it isn't being
    // edited — so a rejected shrink (or a clamp) snaps the text back.
    if (!_focus.hasFocus && _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 1) {
      _controller.text = '${widget.value}';
      return;
    }
    if (parsed != widget.value) widget.onChanged(parsed);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.all1,
        border: Border.all(color: PhiColors.line1),
      ),
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        cursorColor: PhiColors.voice1,
        cursorWidth: 1,
        style: PhiType.mono().copyWith(color: PhiColors.fg0, fontSize: 12),
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
