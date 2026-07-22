import '../../domain/midi/store/clip_document.dart';
import '../../domain/project/entity_address.dart';
import '../bridge/clip_control_port.dart';
import 'engine_midi_controller.dart';

/// The [EngineMidiController] session manager as the control plane's
/// [ClipControlPort] — the receiving end of `phi.ctl.clip.*` (design
/// `docs/design/live-coding.md` §4, issue #233; production wiring #334).
///
/// A script `clip.phrase_a.play()` publishes `phi.ctl.clip.phrase_a.play`; the
/// [ControlPlaneDispatcher] decodes the target address and calls [play]. The
/// port drives the ordinary session path so a code-started clip is
/// indistinguishable from a panel-started one, with one addition the DSL needs:
/// the **open-from-registry** step. A clip a script plays may have no session
/// open yet (the library controller opens it on selection in the UI); [play] and
/// [loop] first materialise a session from the clip's stored [ClipDocument] —
/// resolved through the [_documentAt] seam the engine backs with its registry
/// decode — before acting on it.
///
/// A target that resolves to no clip session and no stored document is treated
/// as a **group** address (`clip.drums.play()`): the group verbs act on the
/// already-open sessions beneath it (opening every member from the registry is
/// the panel's concern, design §4). Unknown targets degrade to a silent no-op;
/// everything no-ops gracefully when no MIDI subsystem is wired.
class SessionClipControlPort implements ClipControlPort {
  SessionClipControlPort({
    required EngineMidiController? midi,
    required ClipDocument? Function(EntityAddress address) documentAt,
  }) : _midi = midi,
       _documentAt = documentAt;

  final EngineMidiController? _midi;
  final ClipDocument? Function(EntityAddress address) _documentAt;

  @override
  void play(EntityAddress target) {
    final midi = _midi;
    if (midi == null) return;
    _ensureOpen(midi, target);
    if (midi.sessionFor(target) != null) {
      midi.playSession(target);
    } else {
      midi.playGroup(target);
    }
  }

  @override
  void stop(EntityAddress target) {
    final midi = _midi;
    if (midi == null) return;
    if (midi.sessionFor(target) != null) {
      midi.stopSession(target);
    } else {
      midi.stopGroup(target);
    }
  }

  @override
  void pause(EntityAddress target) => _midi?.pauseSession(target);

  @override
  void loop(EntityAddress target, {required bool on}) {
    final midi = _midi;
    if (midi == null) return;
    _ensureOpen(midi, target);
    midi.setSessionLoop(target, on);
  }

  @override
  void stopAll() => _midi?.stopAll();

  /// Open a session for [target] from its stored document when none is open yet
  /// (the library-controller open-from-registry path) — a no-op when a session
  /// already exists or [target] names no clip entity (e.g. a group).
  void _ensureOpen(EngineMidiController midi, EntityAddress target) {
    if (midi.sessionFor(target) != null) return;
    final document = _documentAt(target);
    if (document != null) midi.ensureSession(target, document);
  }
}
