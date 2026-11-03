import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;

import '../../domain/patcher/patch_abstraction.dart';
import '../../domain/patcher/patch_boundary.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_event.dart';
import '../../domain/project/registry_group.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/project/registry_node.dart';
import '../bridge/patcher_gateway.dart';
import 'patch_instance_materialiser.dart';
import 'patch_reconciler.dart';
import 'patcher_controller.dart';

/// Keeps every abstraction's instances equal to its definition (issue #553,
/// design `docs/design/patcher.md` §13).
///
/// A **definition** is any `patch.` entity. An **instance** is a subpatch box
/// named after that entity's address ([PatchAbstraction]), whose contents are a
/// copy in the parent's flat graph. [sync] reads the patches' mirrors and brings
/// each instance in line, definitions before the patches using them, so a change
/// runs through nested abstractions in one pass. It holds no record of what
/// changed: it compares, which also puts right an instance an undo or a paste
/// has brought back from an older definition, or a project saved half-way.
///
/// It also keeps the registry honest: a patch's references are the definitions
/// it uses, so deleting one lists its users ([ProjectRegistry.impactOfRemoving]),
/// and when a definition moves it rewrites the boxes that name it — the registry
/// repoints the reference, and the name in the live native object follows here.
///
/// A patch that reaches itself through its instances cannot be materialised. The
/// boxes involved keep what they hold and stop following, and the patch's canvas
/// says why, until the loop is taken out. A definition that does not exist leaves
/// its instances as they were, sounding, until it comes back.
class PatchAbstractionSync {
  PatchAbstractionSync({
    required this._registry,
    required this._patches,
    required this._gateway,
    required this._editorFor,
    required this._cachedEditor,
  }) {
    _events = _registry.events.listen(_onRegistryEvent);
  }

  final ProjectRegistry _registry;
  final PatchReconciler _patches;
  final PatcherGateway _gateway;

  /// The editor bound to a patch, made on demand; null when it has no instance.
  final PatcherController? Function(EntityAddress address) _editorFor;

  /// The editor bound to a patch if it has one yet.
  final PatcherController? Function(EntityAddress address) _cachedEditor;

  late final StreamSubscription<RegistryEvent> _events;

  /// What a patch that has no editor yet uses, read once per native instance:
  /// without an editor nobody can have changed it since it was parsed.
  final Map<int, Set<EntityAddress>> _usesByInstance = {};

  /// The references last found to close a loop, so each is said only once.
  Set<(EntityAddress, EntityAddress)> _refused = const {};

  bool _running = false;
  bool _pending = false;
  bool _scheduled = false;
  bool _disposed = false;

  /// Run [sync] once the current turn is over — for a change that notifies
  /// half-way through a compound operation (a rename re-materialising a patch).
  void schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) sync();
    });
  }

  /// Bring every instance of every definition in line. A no-op, touching
  /// nothing native, for a project that uses no abstractions.
  void sync() {
    if (_disposed) return;
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    try {
      // A pass that changed a patch may have changed what the patches using it
      // use, so it runs again; a loop cannot keep this going, since a refused
      // reference is left alone.
      var passes = 0;
      do {
        _pending = false;
      } while ((_pass() || _pending) && ++passes < _maxPasses);
    } finally {
      _running = false;
    }
  }

  /// More than any sane nesting needs: a guard, not a limit anyone should meet.
  static const int _maxPasses = 16;

  /// One pass over the project. Returns whether anything changed.
  bool _pass() {
    final patches = _patchAddresses();
    final uses = {for (final p in patches) p: _usesOf(p)};
    _publishReferences(uses);
    final refused = _refusedReferences(uses);
    _announceRefused(refused);
    var changed = false;
    for (final patch in _definitionsFirst(uses, refused)) {
      if (uses[patch]?.isEmpty ?? true) continue;
      final parent = _editorFor(patch);
      if (parent == null) continue;
      parent.numberInstances();
      for (final box in parent.outermostInstances) {
        final definition = parent.abstractionOf(box);
        if (definition == null) continue;
        if (refused.contains((patch, definition))) continue;
        if (_registry.entityAt(definition) == null) continue;
        final source = _editorFor(definition);
        if (source == null) continue;
        final run = PatchInstanceMaterialiser(
          source: source,
          sourceScope: null,
          target: parent,
          targetScope: box,
        )..run();
        changed = changed || run.changed;
        if (run.dropped > 0) {
          final cables = run.dropped == 1 ? 'cable' : 'cables';
          parent.announce(
            '${definition.format()} changed · '
            '${run.dropped} $cables dropped',
          );
        }
      }
    }
    return changed;
  }

  /// The definitions [patch] uses, at any depth.
  Set<EntityAddress> _usesOf(EntityAddress patch) {
    final editor = _cachedEditor(patch);
    if (editor != null) return editor.abstractionReferences;
    final instance = _patches.instanceIdOf(patch);
    if (instance == null) return const {};
    return _usesByInstance[instance] ??= {
      for (final object in _gateway.enumerate(instance).objects)
        if (PatchBoundary.isSubpatch(object.type))
          ?PatchAbstraction.referenceIn(object.args),
    };
  }

  /// Point each patch's registry references at the definitions it uses.
  void _publishReferences(Map<EntityAddress, Set<EntityAddress>> uses) {
    uses.forEach((patch, used) {
      if (setEquals(_registry.referencesOf(patch), used)) return;
      _registry.setReferences(patch, used);
    });
  }

  /// Every reference by which a patch reaches itself.
  Set<(EntityAddress, EntityAddress)> _refusedReferences(
    Map<EntityAddress, Set<EntityAddress>> uses,
  ) => {
    for (final MapEntry(key: patch, value: used) in uses.entries)
      for (final definition in used)
        if (reaches(uses, definition, patch)) (patch, definition),
  };

  /// Whether [from] is [to] or uses it, at any depth.
  static bool reaches(
    Map<EntityAddress, Set<EntityAddress>> uses,
    EntityAddress from,
    EntityAddress to,
  ) {
    final seen = <EntityAddress>{};
    final stack = [from];
    while (stack.isNotEmpty) {
      final at = stack.removeLast();
      if (at == to) return true;
      if (seen.add(at)) stack.addAll(uses[at] ?? const {});
    }
    return false;
  }

  void _announceRefused(Set<(EntityAddress, EntityAddress)> refused) {
    for (final pair in refused.difference(_refused)) {
      final (patch, definition) = pair;
      _cachedEditor(patch)?.announce(
        '${definition.format()} contains ${patch.format()} · not updated',
      );
    }
    _refused = refused;
  }

  /// [uses]' patches, each after the definitions it follows.
  List<EntityAddress> _definitionsFirst(
    Map<EntityAddress, Set<EntityAddress>> uses,
    Set<(EntityAddress, EntityAddress)> refused,
  ) {
    final order = <EntityAddress>[];
    final seen = <EntityAddress>{};
    void visit(EntityAddress patch) {
      if (!seen.add(patch)) return;
      for (final definition in uses[patch] ?? const <EntityAddress>{}) {
        if (!refused.contains((patch, definition))) visit(definition);
      }
      if (uses.containsKey(patch)) order.add(patch);
    }

    uses.keys.forEach(visit);
    return order;
  }

  /// What [patch] could take an instance of without reaching itself: every
  /// other patch that does not use it.
  List<EntityAddress> definitionsFor(EntityAddress patch) {
    final patches = _patchAddresses();
    final uses = {for (final p in patches) p: _usesOf(p)};
    return [
      for (final candidate in patches)
        if (!reaches(uses, candidate, patch)) candidate,
    ];
  }

  void _onRegistryEvent(RegistryEvent event) {
    if (event case RegistryEntityMoved(:final from, :final to)
        when from.kind == RegistryKinds.patch) {
      _follow(from, to);
    }
    sync();
  }

  /// A definition moved: every box naming it follows, in the live native patch
  /// and so in the next dump. Not journaled: undoing the move moves it back.
  void _follow(EntityAddress from, EntityAddress to) {
    for (final patch in _patchAddresses()) {
      if (_usesOf(patch).isEmpty) continue;
      final editor = _editorFor(patch);
      if (editor == null) continue;
      for (final node in editor.graph.nodes.toList()) {
        final definition = editor.abstractionOf(node.id);
        if (definition == null) continue;
        final next = PatchAbstraction.moved(definition, from, to);
        if (next != definition) editor.setNodeParams(node.id, next.format());
      }
    }
  }

  /// Every `patch.` entity, at its real address.
  List<EntityAddress> _patchAddresses() {
    final out = <EntityAddress>[];
    void visit(RegistryNode node, List<String> path) {
      final segments = [...path, node.name];
      if (node is RegistryGroup) {
        for (final child in node.children) {
          visit(child, segments);
        }
      } else {
        out.add(EntityAddress(kind: RegistryKinds.patch, segments: segments));
      }
    }

    for (final node in _registry.childrenOfKind(RegistryKinds.patch)) {
      visit(node, const []);
    }
    return out;
  }

  void dispose() {
    _disposed = true;
    unawaited(_events.cancel());
  }
}
