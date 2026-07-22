import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../design/widgets/state_machine/state_canvas_constants.dart';
import '../../domain/project/commands/create_entity_command.dart';
import '../../domain/project/commands/move_entity_command.dart';
import '../../domain/project/commands/remove_entity_command.dart';
import '../../domain/project/commands/update_entity_payload_command.dart';
import '../../domain/project/delete_impact.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/name_slug.dart';
import '../../domain/project/project_command.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_event.dart';
import '../../domain/project/registry_group.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/project/registry_node.dart';
import '../../domain/state_machine/slices/state_slice_category.dart';
import '../../domain/state_machine/slices/state_slice_resolution.dart';
import '../../domain/state_machine/slices/state_slices.dart';
import '../../domain/state_machine/state_node_data.dart';
import '../../domain/state_machine/state_transition.dart';
import '../../domain/state_machine/store/state_document.dart';
import '../../domain/state_machine/store/state_transition_spec.dart';
import 'state_slice_source.dart';

/// The registry-backed state machine (design `docs/design/state-graph.md` §3,
/// issue #241): reads and writes `state.` entities, so the canvas renders
/// from the registry and every structural edit is a journaled command.
///
/// **Authored state lives in the registry.** Nodes are `state.` entities
/// whose [StateDocument] payload carries the canvas position and the ordered
/// outbound transitions; [addState] / [duplicateState] / [rename] /
/// [removeState] / [connect] / [disconnect] / [endMove] thread through the
/// ordinary command layer ([CreateEntityCommand], [MoveEntityCommand],
/// [RemoveEntityCommand], [UpdateEntityPayloadCommand]) recorded via
/// `recordCommand`, so they dirty + journal like any other project change.
/// Node drags stay transient while the pointer is down and commit **one**
/// position command on release (16px snap as before).
///
/// **Performance state stays here.** Which state is *live*
/// ([activeStateAddress]) and which transitions are *armed* are keyed by
/// entity address and never persist (§8 decision 2) — a loaded project seeds
/// the live state from the first `state.` entity in registry order.
///
/// **Rename = refactor.** A [rename] is a registry move: the typed
/// [StateDocument] payloads (a `ReferenceSource`) let the registry rewrite
/// every sibling's transition target in the same command, MIDI-graph guards
/// are repointed through [onStateMoved], and the live / armed / drag
/// references are remapped in place — rename mid-arm keeps the arm. Loaded
/// and journal-replayed payloads arrive map-native (the journal contract);
/// the controller normalises them back to typed documents on every registry
/// change so the refactor machinery always has a `ReferenceSource` to
/// rewrite.
class StateMachineController extends ChangeNotifier {
  /// Builds a controller over [registry] (creating and owning a private
  /// scratch registry when none is given — the bare-test path), recording
  /// structural commands through [recordCommand].
  StateMachineController({
    ProjectRegistry? registry,
    void Function(ProjectCommand)? recordCommand,
  }) : _registry = registry ?? ProjectRegistry(),
       _ownsRegistry = registry == null,
       _recordCommand = recordCommand {
    _attach();
  }

  ProjectRegistry _registry;
  bool _ownsRegistry;
  void Function(ProjectCommand)? _recordCommand;
  StreamSubscription<RegistryEvent>? _eventsSub;

  /// Called after a `state.` entity moved from one address to another — the
  /// seam the engine wires to repoint live MIDI-graph guards
  /// (`MidiTransformGraph.repointGuardState`) so a state rename re-routes
  /// guard evaluation without touching the stored clip (issue #241). May be
  /// called more than once per move; repointing is idempotent.
  void Function(EntityAddress from, EntityAddress to)? onStateMoved;

  /// Called after a state is *entered* — an explicit [fire] or [setLive] made
  /// it live. The seam the engine wires to the application engine (issue
  /// #243), so entering a state applies its captured slices and on-enter
  /// script. Passive re-seeding (a project load, a deleted live state falling
  /// back to the first survivor) is **not** an entry: recovery lands on the
  /// authored state without replaying performance (§8 decision 2).
  void Function(EntityAddress state)? onStateEntered;

  /// Pan/zoom state for the `InteractiveViewer` in the canvas.
  final TransformationController transform = TransformationController();

  // ─── performance state (never persisted) ────────────────────────────────

  EntityAddress? _liveState;
  final Set<StateTransition> _armed = {};
  EntityAddress? _dragSourceState;
  final Map<EntityAddress, Offset> _dragPositions = {};

  // ─── caches ─────────────────────────────────────────────────────────────

  Map<EntityAddress, StateDocument>? _documents;
  int _version = 0;
  bool _normalising = false;

  /// The registry whose `state.` namespace this controller fronts.
  ProjectRegistry get registry => _registry;

  /// Bumps on every notify so painters can do a cheap int comparison in
  /// `shouldRepaint`.
  int get version => _version;

  /// Re-point the controller at a fresh [registry] (a project New / Open
  /// swaps the instance) and refresh [recordCommand]. Performance state
  /// (live, arms, drags) is reset — it belongs to the previous performance —
  /// and the live state re-seeds from the new registry's first `state.`
  /// entity. Idempotent when [registry] is already bound.
  void rebind({
    required ProjectRegistry registry,
    void Function(ProjectCommand)? recordCommand,
  }) {
    if (identical(registry, _registry)) {
      _recordCommand = recordCommand;
      return;
    }
    _detach();
    if (_ownsRegistry) _registry.dispose();
    _registry = registry;
    _ownsRegistry = false;
    _recordCommand = recordCommand;
    _liveState = null;
    _armed.clear();
    _dragSourceState = null;
    _dragPositions.clear();
    _attach();
    _bumpAndNotify();
  }

  void _attach() {
    _registry.addListener(_onRegistryChanged);
    _eventsSub = _registry.events.listen(_onRegistryEvent);
    _normalisePayloads();
    _invalidate();
    _ensureLive();
  }

  void _detach() {
    _registry.removeListener(_onRegistryChanged);
    _eventsSub?.cancel();
    _eventsSub = null;
  }

  // ─── view (derived from the registry) ───────────────────────────────────

  /// Every state node in registry order (groups flattened, pre-order), with
  /// in-flight drag positions overriding the persisted ones. Voice accents
  /// are assigned from that order — cosmetic, like the seeded intro/verse
  /// pair has always been coloured.
  List<StateNodeData> get states {
    var index = 0;
    return [
      for (final entry in _docs.entries)
        StateNodeData(
          address: entry.key,
          voice: (index++ % 6) + 1,
          position: _dragPositions[entry.key] ?? entry.value.position,
        ),
    ];
  }

  /// Every renderable transition — one per persisted [StateTransitionSpec]
  /// whose target still exists — with the transient armed flag folded in.
  List<StateTransition> get transitions {
    final docs = _docs;
    final result = <StateTransition>[];
    for (final entry in docs.entries) {
      for (final spec in entry.value.transitions) {
        if (!docs.containsKey(spec.to)) continue; // dangling — not renderable
        final transition = StateTransition(
          source: entry.key,
          target: spec.to,
          armed: _armed.contains(
            StateTransition(source: entry.key, target: spec.to),
          ),
          fireOn: spec.label ?? spec.trigger.kind,
        );
        if (!result.contains(transition)) result.add(transition);
      }
    }
    return result;
  }

  /// The node at [address], or `null` when no `state.` entity sits there.
  StateNodeData? nodeAt(EntityAddress address) {
    for (final node in states) {
      if (node.address == address) return node;
    }
    return null;
  }

  /// The decoded document of the state at [address], or `null` when absent.
  StateDocument? documentOf(EntityAddress address) => _docs[address];

  /// The live state's entity address, or `null` while the registry holds no
  /// states — what MIDI-graph `GraphEvalContext.activeState` guards evaluate
  /// against, and what keys the fuchsia `● LIVE` capsule.
  EntityAddress? get activeStateAddress => _liveState;

  /// The state currently being dragged *from* to author a new transition,
  /// if any.
  EntityAddress? get dragSourceState => _dragSourceState;

  // ─── state lifecycle ────────────────────────────────────────────────────

  /// Create a state named [name] (slugged, uniqued among its siblings) at
  /// [position] — snapped to the 16px grid — as one journaled create
  /// command. Returns the new entity's address.
  EntityAddress addState({String name = 'state', required Offset position}) {
    final address = _freshUnder(const [], NameSlug.of(name, fallback: 'state'));
    final document = StateDocument(position: _snap(position));
    _apply(
      CreateEntityCommand(
        _registry,
        address,
        payload: document,
        references: document.references,
      ),
    );
    return address;
  }

  /// Duplicate the state at [source] to `<name>_copy` beside it — same
  /// transitions, slices and on-enter script, offset one grid cell down and
  /// right. Returns the copy's address, or `null` when [source] is unknown.
  EntityAddress? duplicateState(EntityAddress source) {
    final document = _docs[source];
    if (document == null) return null;
    final address = _freshUnder(source.groupPath, '${source.name}_copy');
    final copy = document.copyWith(
      position: _snap(
        document.position +
            const Offset(
              StateCanvasConstants.snapStep * 2,
              StateCanvasConstants.snapStep * 2,
            ),
      ),
    );
    _apply(
      CreateEntityCommand(
        _registry,
        address,
        payload: copy,
        references: copy.references,
      ),
    );
    return address;
  }

  /// What deleting the state at [address] would strand — the inbound
  /// transitions and MIDI-graph guards left dangling. The surface raises the
  /// delete-impact dialog when this [DeleteImpact.hasReferrers].
  DeleteImpact impactOf(EntityAddress address) =>
      _registry.impactOfRemoving(address);

  /// Remove the state at [address], first clearing the inbound transitions
  /// other states hold toward it (each a journaled payload update — deleting
  /// a state clears the edges into it, the mix-delete precedent). MIDI-graph
  /// guards on the state are left dangling — the impact dialog warned — and
  /// simply never match again.
  void removeState(EntityAddress address) {
    final docs = _docs;
    if (!docs.containsKey(address)) return;
    for (final entry in docs.entries) {
      if (entry.key == address) continue;
      if (!entry.value.transitions.any((s) => s.to == address)) continue;
      final updated = entry.value.copyWith(
        transitions: [
          for (final spec in entry.value.transitions)
            if (spec.to != address) spec,
        ],
      );
      _apply(UpdateEntityPayloadCommand(_registry, entry.key, updated));
    }
    // Drop the transients touching the state *before* the removal notifies,
    // so no listener observes a dangling arm; the live state re-seeds from
    // the survivors in the removal's own change pass. The async Deleted
    // event repeats this, idempotently.
    _armed.removeWhere(
      (t) => _isOrUnder(t.source, address) || _isOrUnder(t.target, address),
    );
    if (_liveState != null && _isOrUnder(_liveState!, address)) {
      _liveState = null;
    }
    _apply(RemoveEntityCommand(_registry, address));
  }

  /// Rename the state at [address] to [newName] — a registry move, so the
  /// address follows the name and every referent (sibling transitions,
  /// declared guard edges) is rewritten in the same command. Live / armed /
  /// drag references and MIDI-graph guards follow synchronously: rename
  /// mid-arm keeps the arm, and a rename of the live state keeps it live.
  /// Returns the new address, or `null` for a blank name or an unknown
  /// state; the address itself when the slug is unchanged.
  EntityAddress? rename(EntityAddress address, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || !_docs.containsKey(address)) return null;
    final slug = NameSlug.of(trimmed, fallback: 'state');
    if (slug == address.name) return address;
    final to = _freshUnder(address.groupPath, slug);
    // Remap the transient references *before* the move notifies, so no
    // listener ever observes the arm or the LIVE capsule dropping.
    _remapTransients(address, to);
    _apply(MoveEntityCommand(_registry, address, to));
    onStateMoved?.call(address, to);
    return to;
  }

  /// Move the node at [address] by [delta] (canvas-local pixels) as an
  /// in-flight drag: the next position is snapped to the 16px grid — the
  /// node "jumps" between grid cells, matching the dot grid backdrop — and
  /// stays transient until [endMove] commits it.
  void moveState(EntityAddress address, Offset delta) {
    final document = _docs[address];
    if (document == null) return;
    final current = _dragPositions[address] ?? document.position;
    final next = _snap(current + delta);
    if (_dragPositions[address] == next) return;
    _dragPositions[address] = next;
    _bumpAndNotify();
  }

  /// Commit the in-flight drag of [address] as one journaled position
  /// command. A no-op when nothing moved.
  void endMove(EntityAddress address) {
    final pending = _dragPositions.remove(address);
    final document = _docs[address];
    if (pending == null || document == null) return;
    if (pending == document.position) {
      _bumpAndNotify();
      return;
    }
    _apply(
      UpdateEntityPayloadCommand(
        _registry,
        address,
        document.copyWith(position: pending),
      ),
    );
  }

  // ─── transition lifecycle ───────────────────────────────────────────────

  void beginTransitionDrag(EntityAddress from) {
    if (!_docs.containsKey(from)) return;
    _dragSourceState = from;
    _bumpAndNotify();
  }

  void endTransitionDrag() {
    if (_dragSourceState == null) return;
    _dragSourceState = null;
    _bumpAndNotify();
  }

  /// Connect [source] → [target] by appending a manual-trigger
  /// [StateTransitionSpec] to the source's payload — one journaled command.
  /// Rejects self-loops, duplicates, and unknown endpoints. Returns whether
  /// the transition was made.
  bool connect(EntityAddress source, EntityAddress target) {
    final docs = _docs;
    final sourceDocument = docs[source];
    if (source == target) return false;
    if (sourceDocument == null || !docs.containsKey(target)) return false;
    if (sourceDocument.transitions.any((s) => s.to == target)) return false;
    _apply(
      UpdateEntityPayloadCommand(
        _registry,
        source,
        sourceDocument.copyWith(
          transitions: [
            ...sourceDocument.transitions,
            StateTransitionSpec(to: target),
          ],
        ),
      ),
    );
    return true;
  }

  /// Remove every [source] → [target] transition from the source's payload.
  /// No-op if no such transition exists.
  void disconnect(EntityAddress source, EntityAddress target) {
    final sourceDocument = _docs[source];
    if (sourceDocument == null) return;
    if (!sourceDocument.transitions.any((s) => s.to == target)) return;
    _armed.remove(StateTransition(source: source, target: target));
    _apply(
      UpdateEntityPayloadCommand(
        _registry,
        source,
        sourceDocument.copyWith(
          transitions: [
            for (final spec in sourceDocument.transitions)
              if (spec.to != target) spec,
          ],
        ),
      ),
    );
  }

  // ─── captured slices (issue #242) ───────────────────────────────────────

  /// The live-performance reader capture-from-live pulls each category from
  /// (design `docs/design/state-graph.md` §4) — wired by the engine to the
  /// real controllers (`EngineStateSliceSource`), faked in tests. `null` (the
  /// bare default) makes [captureSlice] report `false`; clearing and per-entry
  /// editing need no source.
  StateSliceSource? sliceSource;

  /// Capture [category] from the live performance into the state at
  /// [address] — one journaled payload update, so a capture dirties, saves
  /// and undoes like any other authored edit. (Capturing is authorship;
  /// *applying* a state is performance and journals nothing — issue #243.)
  ///
  /// Recapturing replaces the category wholesale. A live-empty category
  /// captures as empty — meaningfully distinct from uncaptured ("no clips
  /// playing" stops everything the state knows about). Returns whether the
  /// capture happened — `false` without a [sliceSource] or for an unknown
  /// state; `true` (with no journal write) when the capture matches what is
  /// already stored.
  bool captureSlice(EntityAddress address, StateSliceCategory category) {
    final source = sliceSource;
    final document = _docs[address];
    if (source == null || document == null) return false;
    final slices = switch (category) {
      StateSliceCategory.clips => document.slices.copyWith(
        clips: source.captureClips(),
      ),
      StateSliceCategory.mix => document.slices.copyWith(
        mix: source.captureMix(),
      ),
      StateSliceCategory.variables => document.slices.copyWith(
        variables: source.captureVariables(),
      ),
      StateSliceCategory.tempos => document.slices.copyWith(
        tempos: source.captureTempos(),
      ),
    };
    if (slices != document.slices) _updateSlices(address, document, slices);
    return true;
  }

  /// Clear [category] on the state at [address] back to uncaptured — entering
  /// the state then leaves that category untouched (design §4). One journaled
  /// payload update; a no-op when the state is unknown or the category is
  /// already uncaptured.
  void clearSlice(EntityAddress address, StateSliceCategory category) {
    final document = _docs[address];
    if (document == null || !document.slices.isCaptured(category)) return;
    _updateSlices(address, document, document.slices.cleared(category));
  }

  /// Remove the captured clips entry for [clip] from the state at [address]
  /// without recapturing — removing the last entry keeps the category
  /// captured-but-empty. One journaled payload update; a no-op when the state
  /// is unknown, the category is uncaptured, or the entry is absent.
  void removeClipSliceEntry(EntityAddress address, EntityAddress clip) =>
      _editSlices(address, (slices) => slices.withoutClip(clip));

  /// Remove the captured mix entry for [bus] — see [removeClipSliceEntry].
  void removeMixSliceEntry(EntityAddress address, EntityAddress bus) =>
      _editSlices(address, (slices) => slices.withoutBus(bus));

  /// Remove the captured variable [name] — see [removeClipSliceEntry].
  void removeVariableSliceEntry(EntityAddress address, String name) =>
      _editSlices(address, (slices) => slices.withoutVariable(name));

  /// Remove the captured tempo entry for [domain] — see
  /// [removeClipSliceEntry].
  void removeTempoSliceEntry(EntityAddress address, EntityAddress domain) =>
      _editSlices(address, (slices) => slices.withoutTempo(domain));

  /// The apply-time resolution of the captured slices of the state at
  /// [address] against the current registry (issue #242): entries whose
  /// referents still exist are applicable, deleted referents are dropped and
  /// surfaced as missing — the graceful-degradation partition the application
  /// engine (#243) applies and raises its notice from. Resolves the empty
  /// slices for an unknown state.
  StateSliceResolution resolveSlicesOf(EntityAddress address) =>
      StateSliceResolution.of(
        _docs[address]?.slices ?? StateSlices.empty,
        exists: _registry.contains,
      );

  void _editSlices(
    EntityAddress address,
    StateSlices Function(StateSlices) edit,
  ) {
    final document = _docs[address];
    if (document == null) return;
    final edited = edit(document.slices);
    if (edited == document.slices) return;
    _updateSlices(address, document, edited);
  }

  /// Write [slices] into [document] at [address] as one journaled payload
  /// update. The typed [StateDocument] is a `ReferenceSource`, so the new
  /// slice entries' clip / bus / domain addresses enter the back-reference
  /// index with the same command — rename-refactor rewrites them and
  /// delete-impact lists the state.
  void _updateSlices(
    EntityAddress address,
    StateDocument document,
    StateSlices slices,
  ) => _apply(
    UpdateEntityPayloadCommand(
      _registry,
      address,
      document.copyWith(slices: slices),
    ),
  );

  // ─── arming + firing ────────────────────────────────────────────────────

  /// Toggle the arm on the persisted transition matching [transition]'s
  /// endpoints. Arming is performance state — nothing journals. No-op if no
  /// matching transition exists.
  void toggleArmed(StateTransition transition) {
    final reference = StateTransition(
      source: transition.source,
      target: transition.target,
    );
    if (!_transitionExists(reference)) return;
    if (!_armed.remove(reference)) _armed.add(reference);
    _bumpAndNotify();
  }

  /// Fire [transition]: the target goes live, every arm clears, and the entry
  /// is published through [onStateEntered] so the application engine applies
  /// the target's slices (issue #243). Firing is performance, not authorship
  /// — nothing journals (§8 decision 2). No-op if [transition] is unknown.
  void fire(StateTransition transition) {
    final reference = StateTransition(
      source: transition.source,
      target: transition.target,
    );
    if (!_transitionExists(reference)) return;
    _armed.clear();
    _liveState = transition.target;
    _bumpAndNotify();
    onStateEntered?.call(transition.target);
  }

  /// Mark the state at [address] live — an explicit entry, published through
  /// [onStateEntered] like a [fire]. No-op if [address] is unknown or already
  /// live. The live state is performance state — exactly one state is live
  /// whenever any exists, so there is no way to clear it, only to move it.
  void setLive(EntityAddress address) {
    if (_liveState == address || !_docs.containsKey(address)) return;
    _liveState = address;
    _bumpAndNotify();
    onStateEntered?.call(address);
  }

  @override
  void dispose() {
    _detach();
    if (_ownsRegistry) _registry.dispose();
    transform.dispose();
    super.dispose();
  }

  // ─── registry sync ──────────────────────────────────────────────────────

  void _onRegistryChanged() {
    if (_normalising) return; // our own normalisation write — outer pass runs
    _invalidate();
    _normalisePayloads();
    _ensureLive();
    _bumpAndNotify();
  }

  /// Handles the fine-grained lifecycle events the sync listener cannot
  /// infer: an *external* move (undo/redo, journal replay) remaps the
  /// transient references exactly as an interactive [rename] does, and a
  /// delete prunes the arms and re-seeds the live state. Events are
  /// delivered asynchronously; every handler here is idempotent, so the
  /// duplicate delivery after an interactive rename is a no-op.
  void _onRegistryEvent(RegistryEvent event) {
    switch (event) {
      case RegistryEntityMoved(:final from, :final to)
          when from.kind == RegistryKinds.state:
        _remapTransients(from, to);
        onStateMoved?.call(from, to);
      case RegistryEntityDeleted(:final address)
          when address.kind == RegistryKinds.state:
        _armed.removeWhere(
          (t) => _isOrUnder(t.source, address) || _isOrUnder(t.target, address),
        );
        if (_liveState != null && _isOrUnder(_liveState!, address)) {
          _liveState = null;
        }
        _ensureLive();
        _bumpAndNotify();
      default:
        break;
    }
  }

  /// Remap every transient (live, armed, drag) reference from [from] — or a
  /// descendant of it, for a group move — to the matching address under
  /// [to]. Idempotent; notifies only when something changed.
  void _remapTransients(EntityAddress from, EntityAddress to) {
    var changed = false;
    EntityAddress redirect(EntityAddress address) {
      final redirected = _redirect(address, from, to);
      if (redirected != address) changed = true;
      return redirected;
    }

    final live = _liveState;
    if (live != null) _liveState = redirect(live);
    final remappedArms = {
      for (final t in _armed)
        StateTransition(source: redirect(t.source), target: redirect(t.target)),
    };
    _armed
      ..clear()
      ..addAll(remappedArms);
    final dragSource = _dragSourceState;
    if (dragSource != null) _dragSourceState = redirect(dragSource);
    final drags = Map.of(_dragPositions);
    _dragPositions.clear();
    drags.forEach((address, offset) {
      _dragPositions[redirect(address)] = offset;
    });
    if (changed) _bumpAndNotify();
  }

  /// [address] itself when it is [from] or sits under it re-prefixed onto
  /// [to]; unchanged otherwise.
  static EntityAddress _redirect(
    EntityAddress address,
    EntityAddress from,
    EntityAddress to,
  ) {
    if (address == from) return to;
    if (!address.isDescendantOf(from)) return address;
    return EntityAddress(
      kind: address.kind,
      segments: [
        ...to.segments,
        ...address.segments.sublist(from.segments.length),
      ],
    );
  }

  static bool _isOrUnder(EntityAddress address, EntityAddress root) =>
      address == root || address.isDescendantOf(root);

  /// Replace any map-native `state.` payload (a load, a journal replay, a
  /// recovered project) with its typed [StateDocument] — the
  /// `ReferenceSource` the registry's rename-refactor rewrites. Encoding is
  /// unchanged either way (the codec accepts both forms), so this is a view
  /// normalisation, never a project edit: nothing journals, nothing
  /// dirties.
  void _normalisePayloads() {
    if (_normalising) return;
    _normalising = true;
    try {
      for (final address in _allStateAddresses()) {
        final payload = _registry.entityAt(address)?.payload;
        if (payload is Map) {
          _registry.updateEntityPayload(
            address,
            StateDocument.fromJson(payload.cast<String, Object?>()),
          );
        }
      }
    } finally {
      _normalising = false;
    }
  }

  /// Seed the live state when none is set (or the set one is gone) — the
  /// first `state.` entity in registry order, so a fresh or reloaded project
  /// goes live on its seeded `intro` (§8 decision 2: live-ness is never
  /// persisted, only re-seeded).
  void _ensureLive() {
    final docs = _docs;
    if (_liveState != null && docs.containsKey(_liveState)) return;
    if (_liveState != null && !_registry.contains(_liveState!)) {
      // Dangling after an external move or delete — the async Moved event
      // remaps it, and the Deleted event nulls + re-seeds it (both handled
      // in [_onRegistryEvent]); re-seeding here would race the remap.
      if (docs.isNotEmpty) return;
    }
    _liveState = docs.isEmpty ? null : docs.keys.first;
  }

  // ─── helpers ────────────────────────────────────────────────────────────

  Map<EntityAddress, StateDocument> get _docs {
    final cached = _documents;
    if (cached != null) return cached;
    final result = <EntityAddress, StateDocument>{};
    for (final address in _allStateAddresses()) {
      final payload = _registry.entityAt(address)?.payload;
      if (payload is StateDocument) {
        result[address] = payload;
      } else if (payload is Map) {
        result[address] = StateDocument.fromJson(
          payload.cast<String, Object?>(),
        );
      }
    }
    return _documents = result;
  }

  List<EntityAddress> _allStateAddresses() {
    final result = <EntityAddress>[];
    void walk(List<RegistryNode> nodes, List<String> prefix) {
      for (final node in nodes) {
        if (node is RegistryGroup) {
          walk(node.children.toList(), [...prefix, node.name]);
        } else {
          result.add(
            EntityAddress(
              kind: RegistryKinds.state,
              segments: [...prefix, node.name],
            ),
          );
        }
      }
    }

    walk(_registry.childrenOfKind(RegistryKinds.state), const []);
    return result;
  }

  bool _transitionExists(StateTransition reference) {
    final docs = _docs;
    if (!docs.containsKey(reference.target)) return false;
    final source = docs[reference.source];
    if (source == null) return false;
    return source.transitions.any((s) => s.to == reference.target);
  }

  /// A free `state.` address for [leaf] directly under [parentSegments]
  /// (empty = top level), suffixed until unused.
  EntityAddress _freshUnder(List<String> parentSegments, String leaf) {
    EntityAddress at(String name) => EntityAddress(
      kind: RegistryKinds.state,
      segments: [...parentSegments, name],
    );
    var segment = leaf;
    var n = 2;
    while (_registry.contains(at(segment))) {
      segment = '${leaf}_$n';
      n++;
    }
    return at(segment);
  }

  /// Apply a structural [command] and record it for dirty-tracking +
  /// journaling — the same path every other registry surface uses.
  void _apply(ProjectCommand command) {
    command.apply();
    _recordCommand?.call(command);
  }

  void _invalidate() => _documents = null;

  void _bumpAndNotify() {
    _version++;
    notifyListeners();
  }

  static Offset _snap(Offset p) {
    const step = StateCanvasConstants.snapStep;
    return Offset(
      (p.dx / step).roundToDouble() * step,
      (p.dy / step).roundToDouble() * step,
    );
  }
}
