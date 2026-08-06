import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/select/phi_select.dart';
import '../../design/widgets/select/phi_select_group.dart';
import '../../design/widgets/select/phi_select_option.dart';
import '../../domain/project/app_settings/app_settings_controller.dart';
import '../../domain/project/app_settings/audio_settings.dart';
import '../../domain/project/app_settings/speaker_layout.dart';
import '../../engine/bridge/audio_device_descriptor.dart';
import '../../engine/bridge/audio_device_notice.dart';
import '../../engine/engine.dart';
import '../../engine/state/engine_telemetry.dart';

/// The AUDIO section of the settings dialog (design
/// `docs/design/settings-and-devices.md` §6): an output-device picker grouped by
/// host, sample-rate and buffer-size pickers populated from the *selected*
/// device's reported lists ("device default" first — always visible, no override
/// toggle, §9.4), a speaker-layout picker, and a live read-back of the active
/// rate / buffer / latency.
///
/// Every control applies immediately through the engine's live-switch path
/// (design §5): a change opens the device (or rate / buffer / layout) at once and
/// — on success — persists the new [AudioSettings] through the single settings
/// owner. A failed switch reverts to the previous working device (design §9.3):
/// the pickers are bound to [_selected], which is left untouched on failure, so
/// they snap back to the previous choice and nothing is persisted.
class AudioSettingsSection extends StatefulWidget {
  const AudioSettingsSection({
    required this.engine,
    required this.settings,
    super.key,
  });

  /// The engine façade — the only path above the bridge to the device list, the
  /// live-switch, the active read-back, and fallback notices.
  final PhiEngine engine;

  /// The single owner of the app settings (design §7). Seeds the initial choice
  /// and receives the persisted edit on a successful switch.
  final AppSettingsController settings;

  @override
  State<AudioSettingsSection> createState() => _AudioSettingsSectionState();
}

class _AudioSettingsSectionState extends State<AudioSettingsSection> {
  /// Value used in the device picker for "no chosen device — platform default".
  static const String _defaultDeviceKey = '';

  /// Sentinel picker value for the "device default" rate / buffer entry (a real
  /// rate or buffer is always positive, so `-1` can never collide).
  static const int _deviceDefault = -1;

  static const Map<SpeakerLayout, String> _layoutLabels = {
    SpeakerLayout.auto: 'Automatic (stereo)',
    SpeakerLayout.mono: 'Mono',
    SpeakerLayout.stereo: 'Stereo',
    SpeakerLayout.quad: 'Quad',
    SpeakerLayout.surround51: '5.1 Surround',
    SpeakerLayout.surround51Side: '5.1 Side',
    SpeakerLayout.surround61: '6.1 Surround',
    SpeakerLayout.surround71: '7.1 Surround',
  };

  /// The audio settings the pickers currently reflect — the source of truth for
  /// the closed controls. Seeded from the stored preference; advanced only on a
  /// *successful* switch, so a failed one leaves it (and the pickers) unchanged.
  late AudioSettings _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.settings.value.audio;
  }

  List<AudioDeviceDescriptor> get _devices => widget.engine.audioDevices();

  /// The descriptor matching [_selected]'s host + name, or `null` when none is
  /// chosen (platform default) or the stored device is not currently present.
  AudioDeviceDescriptor? get _selectedDescriptor {
    final name = _selected.outputDevice;
    if (name == null) return null;
    final host = _selected.outputHost;
    for (final d in _devices) {
      if (d.name == name && (host == null || d.hostName == host)) return d;
    }
    return null;
  }

  String _keyFor(AudioDeviceDescriptor d) => '${d.hostName}${d.name}';

  AudioDeviceDescriptor? _deviceForKey(String key) {
    for (final d in _devices) {
      if (_keyFor(d) == key) return d;
    }
    return null;
  }

  /// Applies [desired] through the engine's live-switch path and, on success,
  /// advances [_selected] to what the device actually accepted (rate / buffer
  /// normalised) and persists it. On failure the switch has already reverted to
  /// the previous device (design §9.3); [_selected] is left untouched so the
  /// pickers snap back, and nothing is written.
  void _apply(AudioSettings desired) {
    final ok = widget.engine.switchAudioDevice(desired);
    // A successful switch always leaves a device open, so `applied` is non-null
    // here; the guard keeps a "no device open" reading (issue #408) from ever
    // being persisted as the stored preference.
    final applied = widget.engine.activeAudioSettings;
    if (ok && applied != null) {
      setState(() => _selected = applied);
      unawaited(
        widget.settings.update(widget.settings.value.withAudio(applied)),
      );
    } else {
      // Reverted — rebuild so the pickers re-read the unchanged [_selected] and
      // the notice line refreshes.
      setState(() {});
    }
  }

  void _onDeviceChanged(String key) {
    final descriptor = key == _defaultDeviceKey ? null : _deviceForKey(key);
    // A new device reports its own rate / buffer lists, so drop the previous
    // overrides back to the device default; keep the chosen layout.
    _apply(
      AudioSettings(
        outputHost: descriptor?.hostName,
        outputDevice: descriptor?.name,
        layout: _selected.layout,
      ),
    );
  }

  void _onRateChanged(int value) => _apply(
    AudioSettings(
      outputHost: _selected.outputHost,
      outputDevice: _selected.outputDevice,
      sampleRate: value == _deviceDefault ? null : value,
      bufferSize: _selected.bufferSize,
      layout: _selected.layout,
    ),
  );

  void _onBufferChanged(int value) => _apply(
    AudioSettings(
      outputHost: _selected.outputHost,
      outputDevice: _selected.outputDevice,
      sampleRate: _selected.sampleRate,
      bufferSize: value == _deviceDefault ? null : value,
      layout: _selected.layout,
    ),
  );

  void _onLayoutChanged(SpeakerLayout layout) => _apply(
    AudioSettings(
      outputHost: _selected.outputHost,
      outputDevice: _selected.outputDevice,
      sampleRate: _selected.sampleRate,
      bufferSize: _selected.bufferSize,
      layout: layout,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final descriptor = _selectedDescriptor;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(PhiSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field('OUTPUT DEVICE', _deviceSelect()),
          const SizedBox(height: PhiSpacing.s4),
          _field('SAMPLE RATE', _rateSelect(descriptor)),
          const SizedBox(height: PhiSpacing.s4),
          _field('BUFFER SIZE', _bufferSelect(descriptor)),
          const SizedBox(height: PhiSpacing.s4),
          _field('SPEAKER LAYOUT', _layoutSelect()),
          const SizedBox(height: PhiSpacing.s6),
          _field('ACTIVE', _readBack()),
          _notice(),
        ],
      ),
    );
  }

  Widget _field(String label, Widget control) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s2),
        control,
      ],
    );
  }

  Widget _deviceSelect() {
    final devices = _devices;
    final byHost = <String, List<AudioDeviceDescriptor>>{};
    for (final d in devices) {
      byHost.putIfAbsent(d.hostName, () => []).add(d);
    }
    final groups = <PhiSelectGroup<String>>[
      const PhiSelectGroup<String>(
        options: [
          PhiSelectOption(value: _defaultDeviceKey, label: 'System default'),
        ],
      ),
      for (final entry in byHost.entries)
        PhiSelectGroup<String>(
          label: entry.key,
          options: [
            for (final d in entry.value)
              PhiSelectOption(value: _keyFor(d), label: d.name),
          ],
        ),
    ];

    final unavailable =
        _selected.outputDevice != null && _selectedDescriptor == null;
    return PhiSelect<String>(
      value: _selectedKey(),
      groups: groups,
      placeholder: unavailable
          ? '${_selected.outputDevice} (unavailable)'
          : 'System default',
      onChanged: _onDeviceChanged,
    );
  }

  String _selectedKey() {
    if (_selected.outputDevice == null) return _defaultDeviceKey;
    final d = _selectedDescriptor;
    // No match → return a key present in no option so the placeholder (the
    // stored-but-unavailable device name) shows instead of a wrong row.
    return d == null ? ' missing' : _keyFor(d);
  }

  Widget _rateSelect(AudioDeviceDescriptor? descriptor) {
    return PhiSelect<int>.flat(
      value: _selected.sampleRate ?? _deviceDefault,
      enabled: descriptor != null,
      options: [
        const PhiSelectOption(value: _deviceDefault, label: 'device default'),
        if (descriptor != null)
          for (final rate in descriptor.sampleRates)
            PhiSelectOption(value: rate.toInt(), label: '${rate.toInt()} Hz'),
      ],
      onChanged: _onRateChanged,
    );
  }

  Widget _bufferSelect(AudioDeviceDescriptor? descriptor) {
    return PhiSelect<int>.flat(
      value: _selected.bufferSize ?? _deviceDefault,
      enabled: descriptor != null,
      options: [
        const PhiSelectOption(value: _deviceDefault, label: 'device default'),
        if (descriptor != null)
          for (final buffer in descriptor.bufferSizes)
            PhiSelectOption(value: buffer, label: '$buffer frames'),
      ],
      onChanged: _onBufferChanged,
    );
  }

  Widget _layoutSelect() {
    return PhiSelect<SpeakerLayout>.flat(
      value: _selected.layout,
      options: [
        for (final layout in SpeakerLayout.values)
          PhiSelectOption(value: layout, label: _layoutLabels[layout]!),
      ],
      onChanged: _onLayoutChanged,
    );
  }

  /// Live read-back of the active device state (design §6). Rebuilds on every
  /// telemetry tick — and, via [_apply]'s `setState`, immediately after a switch
  /// — re-reading [PhiEngine.activeAudioState] each time so it tracks the device
  /// actually open, not the stored preference.
  Widget _readBack() {
    return StreamBuilder<EngineTelemetry>(
      stream: widget.engine.telemetry,
      builder: (context, _) {
        final state = widget.engine.activeAudioState();
        if (state.sampleRate <= 0) {
          return Text(
            'no device open',
            style: PhiType.mono().copyWith(color: PhiColors.fg3),
          );
        }
        final text =
            '${state.sampleRate.toStringAsFixed(0)} Hz'
            '   ·   ${state.bufferSize} frames'
            '   ·   ${state.outputLatencyMs.toStringAsFixed(1)} ms';
        return Text(text, style: PhiType.readout());
      },
    );
  }

  /// Shows the most recent fallback notice (design §5, §9.3) — a missing device
  /// on boot, or a reverted live switch — so the performer learns why a choice
  /// did not stick. Nothing renders while no notice has been raised.
  Widget _notice() {
    return ValueListenableBuilder<AudioDeviceNotice?>(
      valueListenable: widget.engine.lastAudioNotice,
      builder: (context, notice, _) {
        if (notice == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: PhiSpacing.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: PhiColors.warm,
              ),
              const SizedBox(width: PhiSpacing.s2),
              Expanded(
                child: Text(
                  notice.message,
                  style: PhiType.small().copyWith(color: PhiColors.warm),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
