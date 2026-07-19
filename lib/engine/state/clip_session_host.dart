import '../../domain/midi/graph/graph_eval_context.dart';
import '../../domain/scene/scene_field.dart';
import '../../domain/time_domains/tempo_source_stack.dart';
import '../bridge/midi_gateway.dart';
import '../bridge/scene_agent_sink.dart';

/// The shared engine pieces a [ClipSession] borrows for playback (issue #186).
///
/// A [ClipSession] bundles everything **per clip** — its chain, editor, graph
/// controller, engine transport and push-on-change memoisation. But playing a
/// clip still touches resources that are **singular** for the whole engine: the
/// one MIDI output, the one 3D scene field and its agent sink, the global
/// tempo-source stack (the hand fader), and the live graph-evaluation context
/// (the state machine + runtime variables). The session manager
/// ([EngineMidiController]) owns those and exposes them through this seam, so a
/// session drives playback without reaching into the manager's internals — and
/// N sessions can share them when concurrency lands (next issue).
abstract interface class ClipSessionHost {
  /// The shared MIDI output. A session mints its transport from it and silences
  /// its notes through it on stop.
  MidiGateway get gateway;

  /// The shared 3D scene field a playing session spawns/despawns agents into.
  SceneField get field;

  /// The shared scene sink, or `null` when no renderer is wired — spawning then
  /// no-ops.
  SceneAgentSink? get agentSink;

  /// The global tempo-source stack (the hand fader today) bent onto a session's
  /// base tempo.
  TempoSourceStack get tempoSources;

  /// Whether fractional pitches are voiced as pitch-bend (issue #36) — a global
  /// output mode, not a per-clip choice.
  bool get microtonal;

  /// The session (unsubscribed) tempo in BPM — the base rate a clip runs at when
  /// it carries no active domain subscription.
  double get sessionBpm;

  /// Resolve the chosen MIDI output port to a live device index, or `null` when
  /// none is available/visible (design §5).
  int? resolveOutputPort();

  /// The live graph-evaluation context — the state machine's active state and
  /// the runtime registry's current values mirrored in — so playback and the
  /// graph preview agree on which branches are open.
  GraphEvalContext liveContext();
}
