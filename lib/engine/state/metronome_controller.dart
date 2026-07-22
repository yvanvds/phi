import 'package:flutter/foundation.dart';

import '../../domain/metronome/click_pattern.dart';
import '../../domain/time_domains/time_domain.dart';
import '../../domain/time_domains/time_domain_registry.dart';
import '../bridge/materialised_synth.dart';
import '../bridge/midi_gateway.dart';
import '../bridge/midi_transport.dart';
import '../bridge/transport_note.dart';

/// The metronome — a click session on a chosen time domain's clock (issue #262,
/// design `docs/design/midi-recording.md` §4).
///
/// A [ChangeNotifier] the toolbar toggle + popover bind to. It holds the click's
/// **performance state** — enabled, the bound domain, the meter, the downbeat
/// accent, and the volume — none of which is ever persisted (a loaded project
/// starts silent, §4). Built on the ordinary session/transport machinery: it
/// mints a [MidiTransport] on its own reserved clock, pushes a one-bar
/// [ClickPattern] flattened into [TransportNote]s (looping the meter), and lets
/// the engine dispatch every click from the audio thread — the click is a
/// session like any other, just not in the library.
///
/// The click paces from the **bound domain's tempo** (the session tempo when no
/// domain is bound), so bending the domain's tempo bends the click —
/// polytemporal by construction. Switching the bound domain, or a change to the
/// bound domain's tempo ([refreshDomains]), re-paces the running click without
/// ever re-pushing the note list: tempo lives in the clock, not the data.
///
/// A **state application** can lay a live per-domain tempo override over the
/// authored `domain.` tempo (issue #331, following #243): the click follows it
/// exactly as a subscribed clip does. The override is read through the
/// [domainTempoOverride] seam (the engine's live overrides) and wins over the
/// authored tempo, so firing a state that re-tempos the bound domain re-paces
/// the click, and the click falls back to the authored tempo when the overrides
/// clear (a project swap). The engine re-paces the running click ([applyTempo])
/// whenever it lays or clears an override.
///
/// The click plays a reserved, seeded **click voice** synthesized from the sine
/// kind (zero assets, §8), routed to master like any voice — supplied by the
/// engine through [clickSynth] and connected to the click transport while the
/// click runs. Setups without a synth gateway (Phase-1 tests) pass no synth; the
/// transport still runs, silently.
class MetronomeController extends ChangeNotifier {
  MetronomeController({
    required MidiGateway gateway,
    required TimeDomainRegistry Function() domains,
    required double Function() sessionTempo,
    MaterialisedSynth? Function()? clickSynth,
    double? Function(String domainName)? domainTempoOverride,
    String clockName = defaultClockName,
    int beatsPerBar = 4,
    bool accentDownbeat = true,
    double volume = 0.7,
    String? domainName,
  }) : _gateway = gateway,
       _domains = domains,
       _sessionTempo = sessionTempo,
       _clickSynth = clickSynth,
       _domainTempoOverride = domainTempoOverride,
       _clockName = clockName,
       _beatsPerBar = beatsPerBar < 1 ? 1 : beatsPerBar,
       _accentDownbeat = accentDownbeat,
       _volume = volume.clamp(0.0, 1.0).toDouble(),
       _domainName = domainName;

  final MidiGateway _gateway;
  final TimeDomainRegistry Function() _domains;
  final double Function() _sessionTempo;
  final MaterialisedSynth? Function()? _clickSynth;

  /// Reads the engine's live per-domain tempo override for a domain name, or
  /// `null` when it runs at its authored tempo (issue #331). A state
  /// application lays these overrides through the clock binding (issue #243);
  /// the click consults it so it tracks an applied tempo exactly as a
  /// subscribed clip does. `null` in setups without live overrides (bare /
  /// Phase-1 tests) — the click then always paces from the authored tempo.
  final double? Function(String domainName)? _domainTempoOverride;

  final String _clockName;

  /// The reserved clock name the click transport binds to — distinct from any
  /// clip session's clock so the click runs independently beside them.
  static const String defaultClockName = 'phi.metronome';

  /// The reserved transport channel the click rides (Phi's `0..15` convention).
  /// The engine materialises the click synth one channel higher (`1..16`), so
  /// the click never collides with a performer's voices.
  static const int clickChannel = 15;

  /// The engine MIDI channel (`1..16`) the reserved click synth is materialised
  /// on — [clickChannel] in the engine's one-based convention.
  static const int clickSynthChannel = clickChannel + 1;

  // Click voicing — a high, short sine blip; the accent a fifth up and louder.
  static const int _beatPitch = 84; // C6
  static const int _accentPitch = 91; // G6
  static const double _beatVelocity = 0.6;
  static const double _accentVelocity = 1.0;
  static const double _clickDurationBeats = 0.1;

  MidiTransport? _transport;
  bool _connected = false;
  double? _appliedTempo;

  bool _enabled = false;

  /// Whether the click is sounding. Performance state — never persisted (§4).
  bool get enabled => _enabled;

  String? _domainName;

  /// The name of the bound time domain, or `null` for "no domain" — the click
  /// then paces from the session tempo. Switching it re-paces a running click.
  String? get domainName => _domainName;
  set domainName(String? name) {
    if (_domainName == name) return;
    _domainName = name;
    applyTempo();
    notifyListeners();
  }

  int _beatsPerBar;

  /// Beats per bar — the click's meter. Always at least one. Changing it rebuilds
  /// the one-bar pattern (and its loop length) live.
  int get beatsPerBar => _beatsPerBar;
  set beatsPerBar(int value) {
    final next = value < 1 ? 1 : value;
    if (_beatsPerBar == next) return;
    _beatsPerBar = next;
    _pushIfRunning();
    notifyListeners();
  }

  bool _accentDownbeat;

  /// Whether the downbeat is accented. Changing it rebuilds the pattern live.
  bool get accentDownbeat => _accentDownbeat;
  set accentDownbeat(bool value) {
    if (_accentDownbeat == value) return;
    _accentDownbeat = value;
    _pushIfRunning();
    notifyListeners();
  }

  double _volume;

  /// Click level in `[0, 1]`, scaling every click's velocity. Changing it
  /// rebuilds the pattern live.
  double get volume => _volume;
  set volume(double value) {
    final next = value.clamp(0.0, 1.0).toDouble();
    if (_volume == next) return;
    _volume = next;
    _pushIfRunning();
    notifyListeners();
  }

  /// The time domains the click can bind to, in registry order — the popover's
  /// domain picker reads this.
  List<TimeDomain> get availableDomains => _domains().domains.toList();

  /// The bound domain, or `null` when [domainName] names none (or none is set).
  TimeDomain? get boundDomain =>
      _domainName == null ? null : _domains().resolve(_domainName!);

  /// The click's base tempo. A live per-domain tempo override — a state's
  /// tempos slice applied through the clock binding (issue #331/#243) — wins
  /// over everything, so the click tracks a state-applied tempo just as a
  /// subscribed clip does. Otherwise: the bound domain's authored tempo, or the
  /// session tempo when no domain is bound (or the bound name has vanished from
  /// the registry).
  double get _baseTempo {
    final name = _domainName;
    if (name != null) {
      final override = _domainTempoOverride?.call(name);
      if (override != null) return override;
    }
    return boundDomain?.tempo ?? _sessionTempo();
  }

  // ── control ────────────────────────────────────────────────────────────────

  /// Flip [enabled] — the toolbar toggle.
  void toggle() => setEnabled(!_enabled);

  /// Turn the click on or off. Enabling mints the transport (once), paces it to
  /// the bound tempo, pushes the pattern, connects the click voice and starts
  /// it; disabling stops it and drops the voice connection. A no-op when already
  /// in [value].
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (_enabled) {
      _start();
    } else {
      _stopClick();
    }
    notifyListeners();
  }

  void _start() {
    final transport = _transport ??= _mintTransport();
    applyTempo();
    pushEvents();
    _connectSynth(transport);
    transport.play();
  }

  void _stopClick() {
    _transport?.stop();
    _disconnectSynth();
  }

  MidiTransport _mintTransport() {
    final tempo = _baseTempo;
    _appliedTempo = tempo;
    return _gateway.createTransport(clockName: _clockName, tempo: tempo);
  }

  /// Re-pace the running click to the current [_baseTempo] when it moved. Called
  /// on a domain switch and by the engine on a domain-tempo change
  /// ([refreshDomains]). Idempotent between changes — tempo lives in the clock,
  /// so re-pacing never re-pushes the note list.
  void applyTempo() {
    final transport = _transport;
    if (transport == null) return;
    final tempo = _baseTempo;
    if (tempo == _appliedTempo) return;
    _appliedTempo = tempo;
    transport.setTempo(tempo);
  }

  /// The available domains (or the bound domain's tempo) changed — a project was
  /// opened, or the bound domain's tempo edited. Re-pace a running click and
  /// refresh the picker.
  void refreshDomains() {
    applyTempo();
    notifyListeners();
  }

  void _pushIfRunning() {
    if (_enabled) pushEvents();
  }

  /// Flatten the one-bar [ClickPattern] into [TransportNote]s and push them (with
  /// the meter as the loop length) to the click transport. A no-op before the
  /// transport is minted.
  void pushEvents() {
    final transport = _transport;
    if (transport == null) return;
    final pattern = ClickPattern(
      beatsPerBar: _beatsPerBar,
      accentDownbeat: _accentDownbeat,
    );
    final events = [
      for (final beat in pattern.beats())
        TransportNote(
          startBeat: beat.beat.toDouble(),
          durationBeats: _clickDurationBeats,
          channel: clickChannel,
          pitch: beat.accent ? _accentPitch : _beatPitch,
          velocity: ((beat.accent ? _accentVelocity : _beatVelocity) * _volume)
              .clamp(0.0, 1.0)
              .toDouble(),
        ),
    ];
    transport.setEvents(events, loopBeats: _beatsPerBar.toDouble());
  }

  void _connectSynth(MidiTransport transport) {
    if (_connected) return;
    final synth = _clickSynth?.call();
    if (synth == null) return;
    transport.connectSynth(synth);
    _connected = true;
  }

  void _disconnectSynth() {
    final transport = _transport;
    if (transport == null || !_connected) return;
    final synth = _clickSynth?.call();
    if (synth != null) transport.disconnectSynth(synth);
    _connected = false;
  }

  @override
  void dispose() {
    _disconnectSynth();
    _transport?.dispose();
    _transport = null;
    super.dispose();
  }
}
