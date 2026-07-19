import 'dart:convert';

import '../../domain/midi/clip_editor.dart';
import '../../domain/midi/midi_clip_mode.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/store/clip_document.dart';
import '../../domain/project/commands/update_entity_payload_command.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/project_command.dart';
import '../../domain/project/project_registry.dart';
import 'midi_graph_controller.dart';

/// Publishes the live MIDI clip's edits into the registry's `clip.` entity —
/// the clip-edit dirty-tracking seam #123 deferred and issue #135 lands.
///
/// The engine owns the working clip as three live objects — the source clip and
/// linear pipeline in a [MidiTransformChain], the piano-roll edits in a
/// [ClipEditor], and the branching interpretation in a [MidiGraphController]. A
/// project's persistence, though, reads the `clip.` **registry entity**. This
/// binder bridges the two: it listens to all three and, whenever a note edit, a
/// chip toggle, a parameter change or a graph edit changes the clip, snapshots
/// the whole [ClipDocument] and records an [UpdateEntityPayloadCommand] through
/// [ProjectController.recordCommand] — so the edit marks the clip dirty, is
/// journaled for crash recovery, and is written on the next save (persisting the
/// *edited* clip, not the seeded one).
///
/// Snapshots are de-duplicated by their JSON form, so selection-only editor
/// notifications and graph *layout* (position) changes — which don't alter the
/// persisted document — never spuriously dirty the project.
class ClipRegistryPublisher {
  /// Binds to the engine's live clip objects. [graphController] is optional —
  /// setups without a graph editor (a bare chain) publish a chain-only document.
  ClipRegistryPublisher({
    required this.chain,
    required this.editor,
    this.graphController,
    bool Function()? loop,
  }) : _loop = loop;

  /// The linear pipeline + source clip. Notifies on chip add/remove/toggle/edit.
  final MidiTransformChain chain;

  /// The piano-roll authoring controller. Notifies on every note edit.
  final ClipEditor editor;

  /// The branching-graph editor, or `null` when none is wired.
  final MidiGraphController? graphController;

  /// Reads the edited clip's live loop flag (issue #190). `null` falls back to
  /// `true`, matching a fresh clip's default. The loop flag is not carried by any
  /// of the observed listenables, so a toggle persists via [republish].
  final bool Function()? _loop;

  ProjectRegistry? _registry;
  EntityAddress? _address;
  void Function(ProjectCommand)? _recordCommand;
  String? _lastPushedJson;
  bool _listening = false;

  /// Whether this publisher is currently bound to a registry entity.
  bool get isBound => _address != null;

  /// The `clip.` entity this publisher currently writes to, or `null`.
  EntityAddress? get boundAddress => _address;

  /// Start publishing the live clip into the entity at [clipAddress] in
  /// [registry], recording each change through [recordCommand]. A `null`
  /// [clipAddress] (or one absent from the registry) leaves the publisher
  /// unbound — there is nothing to publish into.
  ///
  /// The current live state seeds the de-dupe baseline, so binding never pushes
  /// on its own: a freshly loaded document survives untouched until the performer
  /// actually edits the clip.
  void bind({
    required ProjectRegistry registry,
    EntityAddress? clipAddress,
    void Function(ProjectCommand)? recordCommand,
  }) {
    unbind();
    if (clipAddress == null || !registry.contains(clipAddress)) return;
    _registry = registry;
    _address = clipAddress;
    _recordCommand = recordCommand;
    _lastPushedJson = jsonEncode(_snapshot());
    chain.addListener(_onChanged);
    editor.addListener(_onChanged);
    graphController?.addListener(_onChanged);
    _listening = true;
  }

  /// Refresh the record callback without re-binding — used when the project
  /// controller re-hands its (stable) registry with a fresh callback.
  void updateRecordCommand(void Function(ProjectCommand)? recordCommand) {
    if (_address != null) _recordCommand = recordCommand;
  }

  /// Stop publishing and detach every listener. Idempotent.
  void unbind() {
    if (_listening) {
      chain.removeListener(_onChanged);
      editor.removeListener(_onChanged);
      graphController?.removeListener(_onChanged);
      _listening = false;
    }
    _registry = null;
    _address = null;
    _recordCommand = null;
    _lastPushedJson = null;
  }

  /// Force a re-snapshot + record when the persistable document changed outside
  /// a chain / editor / graph notification — today, a loop-flag toggle (issue
  /// #190), which none of the observed listenables signals. A no-op while
  /// unbound, and de-duplicated like any other change.
  void republish() => _onChanged();

  void _onChanged() {
    final registry = _registry;
    final address = _address;
    if (registry == null || address == null) return;
    if (!registry.contains(address)) return;
    final snapshot = _snapshot();
    final encoded = jsonEncode(snapshot);
    if (encoded == _lastPushedJson) return; // selection / layout only — skip.
    _lastPushedJson = encoded;
    final command = UpdateEntityPayloadCommand(registry, address, snapshot);
    command.apply();
    _recordCommand?.call(command);
  }

  Map<String, Object?> _snapshot() {
    final gc = graphController;
    return ClipDocument(
      source: chain.source,
      mode: gc?.mode ?? MidiClipMode.chain,
      chain: chain.transforms,
      graph: gc?.graph,
      loop: _loop?.call() ?? true,
    ).toJson();
  }
}
