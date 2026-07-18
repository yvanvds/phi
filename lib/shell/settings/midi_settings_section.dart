import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_motion.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/checklist/phi_checklist_row.dart';
import '../../design/widgets/select/phi_select.dart';
import '../../design/widgets/select/phi_select_option.dart';
import '../../domain/project/app_settings/app_settings_controller.dart';
import '../../domain/project/app_settings/midi_settings.dart';
import '../../engine/engine.dart';

/// The MIDI section of the settings dialog (design
/// `docs/design/settings-and-devices.md` §6): an output-port picker and an
/// input-port checklist with a per-port activity dot.
///
/// Ports are chosen by **name** (design §5): the picked output port replaces the
/// hard-coded port 0 in the engine's MIDI player, resolved to an index each time
/// the port is (re)opened so a replug keeps working; the checked input ports are
/// opened and their receive activity shown, but **nothing is routed anywhere
/// yet** — consuming MIDI-in belongs to the racks & voices epic (design §8).
///
/// Every control applies immediately (design §5): a change persists the new
/// [MidiSettings] through the single settings owner and pushes it to the engine.
class MidiSettingsSection extends StatelessWidget {
  const MidiSettingsSection({
    required this.engine,
    required this.settings,
    super.key,
  });

  /// The engine façade — the only path above the bridge to the MIDI port list,
  /// the apply call, and the input-activity stream.
  final PhiEngine engine;

  /// The single owner of the app settings (design §7). Seeds the current choice
  /// and receives the persisted edit on every change.
  final AppSettingsController settings;

  /// Sentinel picker value for "no explicit output port — the engine's default
  /// (first) port". A real port name is never empty, so `''` cannot collide.
  static const String _defaultPortKey = '';

  void _apply(BuildContext context, MidiSettings next) {
    unawaited(settings.update(settings.value.withMidi(next)));
    engine.applyMidiSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final midi = settings.value.midi;
        final outputs = engine.midiOutputPorts();
        final inputs = engine.midiInputPorts();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(PhiSpacing.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field('OUTPUT PORT', _outputSelect(context, midi, outputs)),
              const SizedBox(height: PhiSpacing.s6),
              Text('INPUT PORTS', style: PhiType.caption()),
              const SizedBox(height: PhiSpacing.s2),
              _inputList(context, midi, inputs),
            ],
          ),
        );
      },
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

  Widget _outputSelect(
    BuildContext context,
    MidiSettings midi,
    List<String> outputs,
  ) {
    final chosen = midi.outputPort;
    // A stored port that is not currently visible: show its name as the
    // placeholder (unavailable) rather than silently snapping to default.
    final unavailable = chosen != null && !outputs.contains(chosen);
    return PhiSelect<String>.flat(
      value: unavailable ? ' missing' : (chosen ?? _defaultPortKey),
      placeholder: unavailable ? '$chosen (unavailable)' : 'System default',
      options: [
        const PhiSelectOption(value: _defaultPortKey, label: 'System default'),
        for (final name in outputs) PhiSelectOption(value: name, label: name),
      ],
      onChanged: (key) => _apply(
        context,
        midi.withOutputPort(key == _defaultPortKey ? null : key),
      ),
    );
  }

  Widget _inputList(
    BuildContext context,
    MidiSettings midi,
    List<String> inputs,
  ) {
    if (inputs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s2),
        child: Text(
          'no MIDI input ports found',
          style: PhiType.small().copyWith(color: PhiColors.fg3),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final name in inputs)
          PhiChecklistRow(
            label: name,
            value: midi.inputPorts.contains(name),
            trailing: MidiActivityDot(
              activity: engine.midiInputActivity,
              portName: name,
            ),
            onChanged: (enabled) =>
                _apply(context, midi.withInput(name, enabled: enabled)),
          ),
      ],
    );
  }
}

/// A small dot that flashes when its [portName] receives a MIDI message — the
/// per-port activity indicator in the input checklist (design §6). It listens to
/// the engine's [PhiEngine.midiInputActivity] stream (which emits the port name
/// on every received message) and lights up briefly on a match.
class MidiActivityDot extends StatefulWidget {
  const MidiActivityDot({
    required this.activity,
    required this.portName,
    super.key,
  });

  /// The engine's per-port activity stream — emits the name of the port a
  /// message arrived on.
  final Stream<String> activity;

  /// The port this dot represents; it flashes only on a matching emission.
  final String portName;

  @override
  State<MidiActivityDot> createState() => _MidiActivityDotState();
}

class _MidiActivityDotState extends State<MidiActivityDot> {
  static const Duration _flashHold = Duration(milliseconds: 180);

  StreamSubscription<String>? _sub;
  Timer? _resetTimer;
  bool _lit = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.activity.listen(_onActivity);
  }

  void _onActivity(String port) {
    if (port != widget.portName || !mounted) return;
    setState(() => _lit = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(_flashHold, () {
      if (mounted) setState(() => _lit = false);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: PhiMotion.dur1,
      curve: PhiMotion.easeOut,
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _lit ? PhiColors.voice1 : PhiColors.fg4,
        boxShadow: _lit
            ? const [BoxShadow(color: PhiColors.voice1Soft, blurRadius: 8)]
            : null,
      ),
    );
  }
}
