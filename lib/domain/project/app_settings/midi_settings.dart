/// The MIDI section of `settings.json` (design
/// `docs/design/settings-and-devices.md` §3) — which output port to send on, and
/// which input ports to open.
///
/// A plain immutable value type in the same style as `AppSettings`: it
/// (de)serialises to a JSON map, compares by value, and its [fromJson] tolerates
/// missing or malformed keys with defaults.
///
/// Ports are identified by **name**, never by index — the stored name is
/// resolved to the current device index each time a port is (re)opened, so
/// replugging keeps working (§4). Opening the input ports and routing their
/// events belongs to later issues; this type only remembers the choice.
class MidiSettings {
  /// Builds the MIDI settings. The all-default instance
  /// (`const MidiSettings()`) means "no output port chosen, no inputs open".
  const MidiSettings({this.outputPort, this.inputPorts = const []});

  /// Reads the MIDI section from a decoded map, tolerating missing or malformed
  /// keys with defaults. Non-string entries in `inputPorts` are dropped.
  factory MidiSettings.fromJson(Map<String, Object?> json) {
    final rawInputs = json['inputPorts'];
    final inputs = <String>[
      for (final entry in (rawInputs is List ? rawInputs : const []))
        if (entry is String) entry,
    ];
    final port = json['outputPort'];
    return MidiSettings(
      outputPort: port is String ? port : null,
      inputPorts: List.unmodifiable(inputs),
    );
  }

  /// The chosen MIDI output port's name, or `null` when none is chosen (the
  /// engine's hard-coded port 0 stays in use until a later issue reads this).
  final String? outputPort;

  /// The names of the MIDI input ports the performer enabled, in listing order.
  final List<String> inputPorts;

  /// A copy with the output port set to [port] (or cleared when `null`) — the
  /// MIDI section's output-port picker (design §6). [inputPorts] is unchanged.
  MidiSettings withOutputPort(String? port) =>
      MidiSettings(outputPort: port, inputPorts: inputPorts);

  /// A copy with input port [name] enabled or disabled — the MIDI section's
  /// input checklist (design §6). Enabling appends [name] (de-duplicated, at the
  /// end so listing order is stable); disabling removes it. [outputPort] is
  /// unchanged.
  MidiSettings withInput(String name, {required bool enabled}) {
    if (enabled) {
      if (inputPorts.contains(name)) return this;
      return MidiSettings(
        outputPort: outputPort,
        inputPorts: List.unmodifiable([...inputPorts, name]),
      );
    }
    if (!inputPorts.contains(name)) return this;
    return MidiSettings(
      outputPort: outputPort,
      inputPorts: List.unmodifiable(inputPorts.where((p) => p != name)),
    );
  }

  /// The section as the JSON map nested under `midi` in `settings.json`. A null
  /// [outputPort] is omitted (absent = none chosen); [inputPorts] is always
  /// written (possibly empty) so a round-trip is an identity.
  Map<String, Object?> toJson() => {
    if (outputPort != null) 'outputPort': outputPort,
    'inputPorts': inputPorts,
  };

  @override
  bool operator ==(Object other) =>
      other is MidiSettings &&
      other.outputPort == outputPort &&
      _listEquals(other.inputPorts, inputPorts);

  @override
  int get hashCode => Object.hash(outputPort, Object.hashAll(inputPorts));

  @override
  String toString() =>
      'MidiSettings(outputPort: $outputPort, inputPorts: $inputPorts)';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
