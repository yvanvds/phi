import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_spacing.dart';
import '../../tokens/phi_type.dart';
import '../inline_editable_text/inline_editable_text.dart';

/// Single mixer channel strip — voice-swatch dot, name, fader with an
/// overlaid peak meter, mute/solo buttons, and a numeric readout.
///
/// Stateless. The strip is a presentation: callers feed it the current
/// volume / peak / mute / solo and receive callbacks to mutate them.
/// `isMaster` flips the strip to its accent treatment (voice-coloured
/// border with a soft halo) and hides the mute/solo buttons — the master
/// has nothing to mute against.
///
/// When [onRename] is wired the header name becomes inline-editable (tap to
/// edit, commit on Enter/blur); when [onRemove] is wired a compact remove
/// control appears in the header. Both are left null on the master strip — it
/// is neither renamed nor removed.
class ChannelStrip extends StatelessWidget {
  const ChannelStrip({
    required this.name,
    required this.volume,
    required this.peak,
    required this.muted,
    required this.soloed,
    required this.voiceColor,
    required this.voiceGlow,
    required this.onVolumeChanged,
    this.onVolumeChangeStart,
    this.onVolumeChangeEnd,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onRename,
    this.onRemove,
    this.removeKey,
    this.dragHandle,
    this.isMaster = false,
    this.soloable = true,
    this.outputPeaks = const <double>[],
    super.key,
  });

  /// Channel name shown in the header row.
  final String name;

  /// User-set volume in `[0.0, 1.0]`.
  final double volume;

  /// Most recent post-volume peak in `[0.0, 1.0+]`.
  final double peak;

  final bool muted;
  final bool soloed;

  /// Saturated swatch for the voice dot, fader fill and master glow.
  final Color voiceColor;

  /// Soft halo variant used for the master strip's outer glow.
  final Color voiceGlow;

  /// Whether this is the master strip — gets the accent border and hides
  /// the mute/solo buttons.
  final bool isMaster;

  /// Whether the strip offers a **solo** button. Returns are exempt from solo
  /// (design `docs/design/mix.md` §5, §10 decision 3), so a return strip passes
  /// `false` to render only the mute control. Ignored on the master, which shows
  /// neither button. Defaults to `true` for ordinary channels and group buses.
  final bool soloable;

  final ValueChanged<double> onVolumeChanged;

  /// Fired when a fader interaction begins (drag start or a click-to-set). The
  /// mix surface uses it to open a gesture the engine coalesces, so a drag emits
  /// one persisted command instead of one per tick. Optional — a strip without
  /// coalescing (a plain widget test) leaves it null.
  final VoidCallback? onVolumeChangeStart;

  /// Fired when a fader interaction ends (drag end/cancel or the tap releasing),
  /// closing the coalesced gesture so the engine flushes one command. Optional.
  final VoidCallback? onVolumeChangeEnd;

  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;

  /// Fired with the edited name when the performer renames the strip inline.
  /// When null the header name is a plain, non-editable label (the master
  /// strip, or a plain widget test).
  final ValueChanged<String>? onRename;

  /// Fired when the performer triggers the header remove control. When null no
  /// remove control is shown (the master strip is never removed).
  final VoidCallback? onRemove;

  /// Optional key for the header remove control, overriding the shared
  /// [removeButtonKey] default. A rack shows several strips at once — each with
  /// its own remove control under the same default key — so a caller that needs
  /// to target one specific strip's control (a return, to open the delete-impact
  /// dialog) passes a distinct key here. Ignored when [onRemove] is null.
  final Key? removeKey;

  /// Per speaker-output post-fader peaks, one entry per output — the master
  /// strip's layout-aware meter (design `docs/design/mix.md` §6): stereo renders
  /// two bars, 5.1 renders six. Empty (the default) on ordinary strips, which
  /// keep their single overlaid peak meter. Each bar is keyed by [outputMeterKey]
  /// so tests can assert the count derived from the live output count.
  final List<double> outputPeaks;

  /// An optional drag affordance placed at the start of the header row (before
  /// the voice dot) — the Mix surface fills it with a `Draggable` grip so a strip
  /// can be dragged into / out of a group or reordered (design §7). Left null on
  /// the master, group buses, and plain widget tests, which are not draggable.
  final Widget? dragHandle;

  static const double width = 86;
  static const double _faderHeight = 160;
  static const double _faderTrackWidth = 14;
  static const double _faderThumbOverhang = 4;
  static const double _faderThumbHeight = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(PhiSpacing.s2),
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: isMaster ? voiceGlow : PhiColors.line1),
        borderRadius: PhiRadii.all1,
        boxShadow: isMaster
            ? [BoxShadow(color: voiceGlow, blurRadius: 16)]
            : null,
      ),
      // When the strip is docked in a pane shorter than its natural height
      // (issue #287), the fader — the tallest, most elastic element — yields
      // its height so the header, readout and mute/solo controls stay visible
      // rather than the Column asserting a `RenderFlex overflowed`. With
      // unbounded height (the isolated widget host) the fader keeps its full
      // `_faderHeight`, so nothing changes when there is room to spare.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fader = _faderWithMeter();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              const SizedBox(height: PhiSpacing.s2),
              // `Flexible` only lays out with a bounded height; under unbounded
              // constraints a flex child would assert, so keep the fader rigid
              // there and let it flex only when the pane actually constrains it.
              if (constraints.maxHeight.isFinite)
                Flexible(child: fader)
              else
                fader,
              const SizedBox(height: PhiSpacing.s2),
              _readout(),
              if (outputPeaks.isNotEmpty) ...[
                const SizedBox(height: PhiSpacing.s2),
                _outputMeters(),
              ],
              if (!isMaster) ...[
                const SizedBox(height: PhiSpacing.s2),
                _muteSoloButtons(),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Key on the header's remove control — exposed so widget tests can trigger
  /// removal without depending on the glyph or layout.
  static const Key removeButtonKey = Key('ChannelStrip.removeButton');

  /// Key on the [index]th per-output meter bar (design §6) — exposed so widget
  /// tests can assert the bar count the strip derived from the live output count
  /// (two on stereo, six on 5.1) without depending on layout offsets.
  static Key outputMeterKey(int index) =>
      Key('ChannelStrip.outputMeter.$index');

  Widget _header() {
    return Row(
      children: [
        if (dragHandle != null) ...[
          dragHandle!,
          const SizedBox(width: PhiSpacing.s1),
        ],
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: voiceColor,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: voiceGlow, blurRadius: 4)],
          ),
        ),
        const SizedBox(width: PhiSpacing.s1),
        Expanded(child: _name()),
        if (onRemove != null) ...[
          const SizedBox(width: PhiSpacing.s1),
          _RemoveButton(
            onPressed: onRemove!,
            buttonKey: removeKey ?? removeButtonKey,
          ),
        ],
      ],
    );
  }

  Widget _name() {
    final style = PhiType.monoS().copyWith(
      color: muted ? PhiColors.fg3 : PhiColors.fg0,
    );
    final rename = onRename;
    if (rename != null) {
      return InlineEditableText(
        value: name,
        onChanged: rename,
        style: style,
        maxWidth: width,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(name, overflow: TextOverflow.ellipsis, style: style);
  }

  /// Key on the fader's hit-area — exposed so widget tests can locate the
  /// fader without depending on layout offsets.
  static const Key faderHitAreaKey = Key('ChannelStrip.faderHitArea');

  Widget _faderWithMeter() {
    final clampedVolume = volume.clamp(0.0, 1.0);
    final clampedPeak = peak.clamp(0.0, 1.0);
    // Read the height actually granted (capped at `_faderHeight`, so the fader
    // never grows past its design size in a tall pane) and drive the fader
    // geometry — thumb, peak fill and the y→value mapping — from it, so a
    // shrunk fader (issue #287) stays internally consistent.
    return LayoutBuilder(
      builder: (context, constraints) {
        final faderHeight = constraints.maxHeight.isFinite
            ? math.min(constraints.maxHeight, _faderHeight)
            : _faderHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // A fader interaction opens a coalescing gesture on pointer-down and
          // closes it when the interaction ends, so the engine journals one
          // command per drag rather than one per tick. A click-to-set uses the
          // tap recognizer (down → up); a drag uses the vertical-drag
          // recognizer (start → end). The two are disjoint here, so each
          // interaction fires exactly one start / end pair.
          // (`onVerticalDragCancel` is intentionally unwired: it fires whenever
          // the drag recognizer merely loses the arena to a tap, so it is not a
          // reliable "gesture ended" signal — a started drag always ends via
          // `onVerticalDragEnd`, and any stray unclosed gesture self-heals on
          // the next `begin`.)
          onTapDown: (d) {
            onVolumeChangeStart?.call();
            onVolumeChanged(_yToValue(d.localPosition.dy, faderHeight));
          },
          onTapUp: (_) => onVolumeChangeEnd?.call(),
          onVerticalDragStart: (d) {
            onVolumeChangeStart?.call();
            onVolumeChanged(_yToValue(d.localPosition.dy, faderHeight));
          },
          onVerticalDragUpdate: (d) =>
              onVolumeChanged(_yToValue(d.localPosition.dy, faderHeight)),
          onVerticalDragEnd: (_) => onVolumeChangeEnd?.call(),
          child: SizedBox(
            key: faderHitAreaKey,
            height: faderHeight,
            child: Center(
              child: SizedBox(
                width: _faderTrackWidth + _faderThumbOverhang * 2,
                height: faderHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _trackBackground(),
                    _peakFill(clampedPeak, faderHeight),
                    _thumb(clampedVolume, faderHeight),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _trackBackground() {
    return Container(
      width: _faderTrackWidth,
      decoration: BoxDecoration(
        color: PhiColors.bg0,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all1,
      ),
    );
  }

  Widget _peakFill(double peak, double faderHeight) {
    if (muted || peak <= 0) return const SizedBox.shrink();
    final fillHeight = math.max(0.0, faderHeight - 2) * peak;
    final greenEnd = (0.60 / peak).clamp(0.0, 1.0);
    final amberEnd = (0.85 / peak).clamp(0.0, 1.0);
    return Positioned(
      left: _faderThumbOverhang + 1,
      right: _faderThumbOverhang + 1,
      bottom: 1,
      height: fillHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: const [
              PhiColors.voice4,
              PhiColors.voice4,
              PhiColors.voice3,
              PhiColors.voice3,
              PhiColors.hot,
              PhiColors.hot,
            ],
            stops: [0, greenEnd, greenEnd, amberEnd, amberEnd, 1],
          ),
          boxShadow: [BoxShadow(color: _glow(peak), blurRadius: 6)],
        ),
      ),
    );
  }

  Widget _thumb(double volume, double faderHeight) {
    final thumbBottom = faderHeight * volume - _faderThumbHeight / 2;
    // A fader squeezed shorter than the thumb (a very small dock pane) has no
    // travel: pin the thumb at the bottom rather than passing an inverted
    // `clamp` range, which would throw.
    final maxBottom = math.max(0.0, faderHeight - _faderThumbHeight);
    return Positioned(
      left: 0,
      right: 0,
      bottom: thumbBottom.clamp(0.0, maxBottom),
      height: _faderThumbHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PhiColors.bg3,
          border: Border.all(
            color: isMaster ? PhiColors.lineHot : PhiColors.line2,
          ),
          borderRadius: PhiRadii.all1,
          boxShadow: isMaster
              ? [BoxShadow(color: voiceGlow, blurRadius: 8)]
              : null,
        ),
      ),
    );
  }

  Widget _readout() {
    if (muted) {
      return Text(
        'muted',
        textAlign: TextAlign.center,
        style: PhiType.monoS().copyWith(color: PhiColors.fg3),
      );
    }
    final db = peak <= 0
        ? '−∞'
        : '−${(20 - peak.clamp(0.0, 1.0) * 20).toStringAsFixed(1)}';
    final color = peak > 0.85
        ? PhiColors.hot
        : peak > 0.60
        ? PhiColors.voice3
        : PhiColors.voice4;
    return Text(
      db,
      textAlign: TextAlign.center,
      style: PhiType.monoS().copyWith(
        color: color,
        shadows: peak > 0.05
            ? [Shadow(color: _glow(peak), blurRadius: 6)]
            : null,
      ),
    );
  }

  /// The master strip's layout-aware meter (design §6): a fixed-height row of
  /// thin vertical bars, one per speaker output, each filling bottom-up to its
  /// output's peak. The bar count is [outputPeaks.length] — the live output
  /// count — so a device/layout swap re-renders it (two bars on stereo, six on
  /// 5.1).
  Widget _outputMeters() {
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < outputPeaks.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: _OutputMeterBar(
                key: outputMeterKey(i),
                peak: outputPeaks[i].clamp(0.0, 1.0),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _muteSoloButtons() {
    return Row(
      children: [
        Expanded(
          child: _StripButton(
            label: 'M',
            active: muted,
            activeColor: PhiColors.hot,
            onPressed: onMuteToggle,
          ),
        ),
        if (soloable) ...[
          const SizedBox(width: PhiSpacing.s0),
          Expanded(
            child: _StripButton(
              label: 'S',
              active: soloed,
              activeColor: PhiColors.voice3,
              onPressed: onSoloToggle,
            ),
          ),
        ],
      ],
    );
  }

  double _yToValue(double localY, double faderHeight) {
    if (faderHeight <= 0) return volume.clamp(0.0, 1.0);
    final clamped = localY.clamp(0.0, faderHeight);
    return 1.0 - (clamped / faderHeight);
  }

  Color _glow(double peak) {
    if (peak > 0.85) return PhiColors.hot.withValues(alpha: 0.5);
    if (peak > 0.60) return PhiColors.voice3.withValues(alpha: 0.45);
    return PhiColors.voice4.withValues(alpha: 0.35);
  }
}

class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? PhiColors.bg3 : PhiColors.bg0,
            border: Border.all(color: active ? activeColor : PhiColors.line1),
            borderRadius: PhiRadii.all1,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: PhiType.monoS().copyWith(
              color: active ? activeColor : PhiColors.fg2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact header affordance to remove a user strip — a small `×` box that
/// mirrors the mix header's `+` add control.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed, required this.buttonKey});

  final VoidCallback onPressed;
  final Key buttonKey;

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

/// One vertical speaker-output meter bar in the master strip (design §6): a dark
/// track with a bottom-anchored fill scaled to [peak] and tinted by level
/// (green below −6, amber to −2.5, hot at the top). Always present so its key is
/// stable — only the fill height reacts to the signal.
class _OutputMeterBar extends StatelessWidget {
  const _OutputMeterBar({required this.peak, super.key});

  /// This output's post-fader peak, clamped to `[0.0, 1.0]`.
  final double peak;

  Color get _fillColor {
    if (peak > 0.85) return PhiColors.hot;
    if (peak > 0.60) return PhiColors.voice3;
    return PhiColors.voice4;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg0,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all1,
      ),
      child: FractionallySizedBox(
        alignment: Alignment.bottomCenter,
        heightFactor: peak <= 0 ? 0.0 : peak,
        widthFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _fillColor,
            borderRadius: PhiRadii.all1,
          ),
        ),
      ),
    );
  }
}
