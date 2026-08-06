import 'dart:convert';

import 'package:flutter/foundation.dart';

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
  /// Creates an unbound publisher. [_loop] reads the edited clip's live loop flag
  /// (issue #190) — `null` falls back to `true`. The live clip objects are bound
  /// (and rebound as the edited session swaps, issue #197) through [bind].
  ClipRegistryPublisher({this._loop});

  /// Reads the edited clip's live loop flag (issue #190). `null` falls back to
  /// `true`, matching a fresh clip's default. The loop flag is not carried by any
  /// of the observed listenables, so a toggle persists via [republish].
  final bool Function()? _loop;

  /// The live clip objects the publisher currently observes — the edited session's
  /// (issue #197). `null` while unbound. [bind] swaps them, moving the listeners
  /// off the previously edited session and onto the newly opened one:
  /// - the linear pipeline + source clip ([_chain]) notifies on chip
  ///   add/remove/toggle/edit and length changes;
  /// - the piano-roll authoring controller ([_editor]) notifies on every note edit;
  /// - the branching-graph editor ([_graphController]), or `null` when none is
  ///   wired, notifies on mode + layout changes, and its **domain graph** on
  ///   structural edits (nodes, edges, guards — issue #240: a guard change must
  ///   publish immediately so the clip's state references stay declared).
  MidiTransformChain? _chain;
  ClipEditor? _editor;
  MidiGraphController? _graphController;

  ProjectRegistry? _registry;
  EntityAddress? _address;
  void Function(ProjectCommand)? _recordCommand;
  String? _lastPushedJson;
  bool _listening = false;

  /// Whether this publisher is currently bound to a registry entity.
  bool get isBound => _address != null;

  /// The `clip.` entity this publisher currently writes to, or `null`.
  EntityAddress? get boundAddress => _address;

  /// Start publishing the live clip objects — [chain], [editor], and optional
  /// [graphController], the edited session's — into the entity at [clipAddress] in
  /// [registry], recording each change through [recordCommand]. A `null`
  /// [clipAddress] (or one absent from the registry) leaves the publisher
  /// unbound — there is nothing to publish into.
  ///
  /// Rebinds cleanly when already bound (the edited session swapped, issue #197):
  /// the previously observed session's listeners are detached first, then the new
  /// ones attached. The current live state seeds the de-dupe baseline, so binding
  /// never pushes on its own — a freshly opened clip survives untouched until the
  /// performer actually edits it.
  void bind({
    required ProjectRegistry registry,
    required MidiTransformChain chain,
    required ClipEditor editor,
    MidiGraphController? graphController,
    EntityAddress? clipAddress,
    void Function(ProjectCommand)? recordCommand,
  }) {
    unbind();
    if (clipAddress == null || !registry.contains(clipAddress)) return;
    _registry = registry;
    _address = clipAddress;
    _chain = chain;
    _editor = editor;
    _graphController = graphController;
    _recordCommand = recordCommand;
    _lastPushedJson = jsonEncode(_snapshot());
    chain.addListener(_onChanged);
    editor.addListener(_onChanged);
    graphController?.addListener(_onChanged);
    graphController?.graph.addListener(_onChanged);
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
      _chain?.removeListener(_onChanged);
      _editor?.removeListener(_onChanged);
      _graphController?.removeListener(_onChanged);
      _graphController?.graph.removeListener(_onChanged);
      _listening = false;
    }
    _registry = null;
    _address = null;
    _chain = null;
    _editor = null;
    _graphController = null;
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
    if (registry == null || address == null || _chain == null) return;
    if (!registry.contains(address)) return;
    final document = _document();
    final snapshot = document.toJson();
    final encoded = jsonEncode(snapshot);
    if (encoded == _lastPushedJson) return; // selection / layout only — skip.
    _lastPushedJson = encoded;
    final command = UpdateEntityPayloadCommand(registry, address, snapshot);
    command.apply();
    _recordCommand?.call(command);
    // The payload is a JSON map (the journal contract), not a `ReferenceSource`,
    // so the registry keeps the *old* references on a payload edit. Re-point the
    // back-reference index at the clip's guarded `state.` addresses so
    // delete-impact on a state lists the clips branching on it and a rename can
    // refactor them (issue #240) — the mirror of `updateVoice` (design §4).
    final references = document.guardStateReferences;
    if (!setEquals(registry.referencesOf(address), references)) {
      registry.setReferences(address, references);
    }
  }

  Map<String, Object?> _snapshot() => _document().toJson();

  ClipDocument _document() {
    final chain = _chain!;
    final gc = _graphController;
    return ClipDocument(
      source: chain.source,
      mode: gc?.mode ?? MidiClipMode.chain,
      chain: chain.transforms,
      graph: gc?.graph,
      loop: _loop?.call() ?? true,
    );
  }
}
