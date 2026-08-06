import '../../domain/project/entity_address.dart';
import '../../domain/runtime/runtime_variable_registry.dart';
import '../../domain/state_machine/slices/clip_slice_entry.dart';
import 'state_slice_applier.dart';

/// The production [StateSliceApplier] — journal-free application over the
/// engine's real controllers (design `docs/design/state-graph.md` §4, issue
/// #243).
///
/// Each category writes to its owning controller through closures, so a
/// project swap (`bindRegistry`) needs no rewiring — the same shape as
/// `EngineStateSliceSource` on the capture side:
///
/// - **variables** — the runtime-variable registry's live values; an undefined
///   name or a non-candidate value is reported unapplied, never thrown.
/// - **tempos** — the MIDI subsystem's per-domain live tempo overrides
///   (`EngineMidiController.applyDomainTempo`), re-pacing every subscribed
///   session's clock; a no-op without a MIDI subsystem.
/// - **mix** — the engine's live bus levels (`PhiEngine.applyLiveBusLevel`),
///   ramped by the gateway's fades, never persisted.
/// - **clips** — play/stop through the sessions to match the captured set;
///   a captured clip with no decodable document is reported skipped.
class EngineStateSliceApplier implements StateSliceApplier {
  EngineStateSliceApplier({
    required this._variables,
    required this._domainTempo,
    required this._mixLevel,
    required this._playingClips,
    required this._playClip,
    required this._stopClip,
  });

  final RuntimeVariableRegistry Function() _variables;
  final void Function(EntityAddress domain, double bpm) _domainTempo;
  final void Function(
    EntityAddress bus, {
    required double volume,
    required bool muted,
  })
  _mixLevel;

  /// The playing set the clips slice matches against — one entry per playing
  /// clip session (the capture seam's reader, reused).
  final List<ClipSliceEntry> Function() _playingClips;

  /// Bring one captured clip to play (opening its session if needed, setting
  /// its loop flag). Returns `false` when the clip could not be started — no
  /// session and no decodable document.
  final bool Function(ClipSliceEntry entry) _playClip;

  /// Stop the playing clip at the given address.
  final void Function(EntityAddress clip) _stopClip;

  @override
  bool applyVariable(String name, String value) {
    final registry = _variables();
    final variable = registry.byName(name);
    // `setValue` alone cannot be the answer: it reports `false` both for a
    // failure *and* for a value that is already current — only the former is
    // a degradation.
    if (variable == null || !variable.values.contains(value)) return false;
    registry.setValue(name, value);
    return true;
  }

  @override
  void applyTempo(EntityAddress domain, double bpm) =>
      _domainTempo(domain, bpm);

  @override
  void applyMix(
    EntityAddress bus, {
    required double volume,
    required bool muted,
  }) => _mixLevel(bus, volume: volume, muted: muted);

  @override
  Set<EntityAddress> applyClips(List<ClipSliceEntry> entries) {
    final wanted = {for (final entry in entries) entry.clip};
    // Stop first, then start: play/stop to match, in a stable order. A playing
    // clip the capture names is left sounding (its loop flag refreshed); a
    // clip neither captured nor playing is never touched.
    for (final playing in _playingClips()) {
      if (!wanted.contains(playing.clip)) _stopClip(playing.clip);
    }
    return {
      for (final entry in entries)
        if (!_playClip(entry)) entry.clip,
    };
  }
}
