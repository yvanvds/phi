import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/project/entity_address.dart';
import 'bus_tap.dart';
import 'clip_control_port.dart';
import 'fx_control_port.dart';
import 'state_control_port.dart';
import 'tempo_control_port.dart';
import 'variable_control_port.dart';
import 'voice_control_port.dart';

/// A degradation notice — a human-readable line describing a `phi.ctl` frame the
/// dispatcher could not route. Delivered instead of throwing, so a malformed or
/// unknown command is logged, never a crash (design §4).
typedef ControlPlaneNotice = void Function(String message);

/// The live-coding **control plane**: it taps the reserved `phi.ctl` bus prefix,
/// decodes each publish, and routes it to the owning controller (design
/// `docs/design/live-coding.md` §4, issue #233).
///
/// A script rides the host-mediated plane by publishing a structural verb to
/// `phi.ctl.*` — `clip.x.play()`, `voice.bells.note(60)`, `var.section = "b"`,
/// `state.fire("break")`, `domain.drum.tempo = 124`. The engine's host bus tap
/// (epic dependency `yvanvds/yse-soundengine#389`) delivers each as a
/// [BusTapFrame]; this dispatcher decodes the address + typed value and hands it
/// to the matching port:
///
/// | address                              | port call                          |
/// |--------------------------------------|------------------------------------|
/// | `phi.ctl.clip.<a>.play` / stop / …   | [ClipControlPort]                  |
/// | `phi.ctl.clip.stop` (root)           | [ClipControlPort.stopAll]          |
/// | `phi.ctl.voice.<a>.note` / off       | [VoiceControlPort]                 |
/// | `phi.ctl.var.<name>`                 | [VariableControlPort.set]          |
/// | `phi.ctl.state[.<m>].fire`           | [StateControlPort.fire]            |
/// | `phi.ctl.domain.<d>.tempo`           | [TempoControlPort.setTempo]        |
/// | `phi.ctl.fx.<a>.<param>`             | [FxControlPort.setParam]           |
///
/// **Graceful degradation.** A malformed frame, an unknown namespace, an
/// unknown verb, or a wrong-typed value never throws: it is reported through
/// [onNotice] (or logged)
/// and dropped. Every decode runs inside a guard, so even an unexpected error
/// degrades to a notice rather than tearing down the tap subscription.
///
/// **The dispatcher lands with fakes.** Clip verbs need epic #183's sessions and
/// voice verbs need epic #203's voices; both are injected as ports, so the whole
/// plane is testable standalone now and the real controllers wire in as those
/// epics merge (design §4, cross-epic note).
class ControlPlaneDispatcher {
  /// Subscribe to [busTap]'s [prefix] frames and route each to the given ports.
  /// [_onNotice] receives every degradation message; when omitted they are logged
  /// via [debugPrint].
  ControlPlaneDispatcher({
    required BusTap busTap,
    required this._clips,
    required this._voices,
    required this._variables,
    required this._states,
    required this._tempo,
    required this._fx,
    this._onNotice,
  }) {
    _subscription = busTap.subscribe(prefix).listen(handleFrame);
  }

  /// The reserved host-mediated control-plane prefix (matches the `phi` library's
  /// `CTL_PREFIX`, design §4).
  static const String prefix = 'phi.ctl';

  final ClipControlPort _clips;
  final VoiceControlPort _voices;
  final VariableControlPort _variables;
  final StateControlPort _states;
  final TempoControlPort _tempo;
  final FxControlPort _fx;
  final ControlPlaneNotice? _onNotice;

  StreamSubscription<BusTapFrame>? _subscription;

  /// Decode and route one tapped frame. Called for every `phi.ctl` publish on
  /// the subscription; also the direct entry point tests drive verbs through.
  /// Guarded end-to-end: any decode/route error becomes a notice, never a throw.
  void handleFrame(BusTapFrame frame) {
    try {
      _route(frame);
    } on Object catch (error) {
      _notify('phi.ctl: dropped "${frame.address}" ($error)');
    }
  }

  /// Stop tapping the bus. Safe to call more than once.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _route(BusTapFrame frame) {
    final address = frame.address;
    if (address != prefix && !address.startsWith('$prefix.')) {
      // The subscription is prefix-scoped, so this is unreachable in practice;
      // guard anyway so a mis-wired tap degrades rather than mis-routes.
      _drop(frame, 'not a $prefix address');
      return;
    }
    if (address.length <= prefix.length + 1) {
      _drop(frame, 'no command after $prefix');
      return;
    }
    final segments = address.substring(prefix.length + 1).split('.');
    final namespace = segments.first;
    final tail = segments.sublist(1);
    switch (namespace) {
      case 'clip':
        _routeClip(frame, tail);
      case 'voice':
        _routeVoice(frame, tail);
      case 'var':
        _routeVar(frame, tail);
      case 'state':
        _routeState(frame, tail);
      case 'domain':
        _routeDomain(frame, tail);
      case 'fx':
        _routeFx(frame, tail);
      default:
        _drop(frame, 'unknown control namespace "$namespace"');
    }
  }

  // ─── clip: play / stop / pause / loop (+ group verbs, stop-all) ───────────
  void _routeClip(BusTapFrame frame, List<String> tail) {
    if (tail.isEmpty) {
      _drop(frame, 'clip command carries no verb');
      return;
    }
    final verb = tail.last;
    final path = tail.sublist(0, tail.length - 1); // entity/group, may be empty
    if (verb == 'stop' && path.isEmpty) {
      _clips.stopAll(); // the namespace-wide `clip.stop()`
      return;
    }
    if (path.isEmpty) {
      _drop(frame, 'clip "$verb" needs a target clip or group');
      return;
    }
    final target = EntityAddress(kind: 'clip', segments: path);
    switch (verb) {
      case 'play':
        _clips.play(target);
      case 'stop':
        _clips.stop(target);
      case 'pause':
        _clips.pause(target);
      case 'loop':
        _clips.loop(target, on: _asBool(frame.value));
      default:
        _drop(frame, 'unknown clip verb "$verb"');
    }
  }

  // ─── voice: note / off (the immediate audition path) ──────────────────────
  void _routeVoice(BusTapFrame frame, List<String> tail) {
    if (tail.isEmpty) {
      _drop(frame, 'voice command carries no verb');
      return;
    }
    final verb = tail.last;
    final path = tail.sublist(0, tail.length - 1);
    if (path.isEmpty) {
      _drop(frame, 'voice "$verb" needs a target voice');
      return;
    }
    final voice = EntityAddress(kind: 'voice', segments: path);
    final args = _asFloatList(frame.value);
    switch (verb) {
      case 'note':
        if (args.isEmpty) {
          _drop(frame, 'voice.note needs a pitch');
          return;
        }
        _voices.note(
          voice,
          pitch: args[0].round(),
          velocity: args.length > 1 ? args[1].round() : 100,
        );
      case 'off':
        _voices.off(voice, pitch: args.isEmpty ? null : args[0].round());
      default:
        _drop(frame, 'unknown voice verb "$verb"');
    }
  }

  // ─── var: `var.x = v` assignment ──────────────────────────────────────────
  void _routeVar(BusTapFrame frame, List<String> tail) {
    if (tail.isEmpty) {
      _drop(frame, 'var assignment carries no name');
      return;
    }
    _variables.set(tail.join('.'), _decode(frame.value));
  }

  // ─── state: `fire` ────────────────────────────────────────────────────────
  void _routeState(BusTapFrame frame, List<String> tail) {
    if (tail.isEmpty || tail.last != 'fire') {
      _drop(frame, 'state command is not a fire');
      return;
    }
    final value = frame.value;
    if (value is! BusString) {
      _drop(frame, 'state.fire needs a string target');
      return;
    }
    final path = tail.sublist(
      0,
      tail.length - 1,
    ); // named machine, may be empty
    final machine = path.isEmpty
        ? null
        : EntityAddress(kind: 'state', segments: path);
    _states.fire(machine, value.value);
  }

  // ─── domain: `domain.x.tempo = bpm` ───────────────────────────────────────
  void _routeDomain(BusTapFrame frame, List<String> tail) {
    if (tail.isEmpty || tail.last != 'tempo') {
      // Only the tempo param is in scope for this issue; other domain params
      // (should any be added) degrade gracefully.
      _drop(frame, 'domain command is not a tempo set');
      return;
    }
    final path = tail.sublist(0, tail.length - 1);
    if (path.isEmpty) {
      _drop(frame, 'domain tempo needs a target domain');
      return;
    }
    _tempo.setTempo(
      EntityAddress(kind: 'domain', segments: path),
      _asDouble(frame.value),
    );
  }

  // ─── fx: `fx.<addr>.<param> = value` (host-mediated param set) ─────────────
  void _routeFx(BusTapFrame frame, List<String> tail) {
    // `phi.ctl.fx.<addr>.<param>` needs at least an fx address segment *and* a
    // trailing param name; a bare `fx.reverb` names no param and degrades.
    if (tail.length < 2) {
      _drop(frame, 'fx set needs an fx address and a param');
      return;
    }
    final param = tail.last;
    final path = tail.sublist(0, tail.length - 1); // the fx entity, may nest
    _fx.setParam(
      EntityAddress(kind: 'fx', segments: path),
      param,
      _asDouble(frame.value),
    );
  }

  // ─── value decoding ───────────────────────────────────────────────────────

  /// A bus value as a plain Dart object — `int` / `double` / `String` /
  /// `List<double>` — mirroring the four bus value types.
  Object? _decode(BusValue value) => switch (value) {
    BusInt(:final value) => value,
    BusFloat(:final value) => value,
    BusString(:final value) => value,
    BusFloatList(:final values) => values,
  };

  /// A numeric bus value as a `double`. Throws for a non-numeric value, which
  /// the outer guard turns into a notice.
  double _asDouble(BusValue value) => switch (value) {
    BusInt(:final value) => value.toDouble(),
    BusFloat(:final value) => value,
    _ => throw FormatException('expected a number, got $value'),
  };

  /// A truthiness flag from an `int`/`float` bus value (`loop` sends `1`/`0`).
  bool _asBool(BusValue value) => switch (value) {
    BusInt(:final value) => value != 0,
    BusFloat(:final value) => value != 0,
    _ => throw FormatException('expected an int flag, got $value'),
  };

  /// The `list[float]` args a note/off frame carries. Throws for a non-list
  /// value, which the outer guard turns into a notice.
  List<double> _asFloatList(BusValue value) => switch (value) {
    BusFloatList(:final values) => values,
    _ => throw FormatException('expected a float list, got $value'),
  };

  void _drop(BusTapFrame frame, String why) =>
      _notify('phi.ctl: dropped "${frame.address}" ($why)');

  void _notify(String message) {
    final notice = _onNotice;
    if (notice != null) {
      notice(message);
    } else {
      debugPrint(message);
    }
  }
}
