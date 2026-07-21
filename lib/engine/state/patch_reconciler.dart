import 'dart:convert';

import '../../domain/patcher/patch_payload.dart';
import '../../domain/project/commands/update_entity_payload_command.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/project_command.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_entity.dart';
import '../../domain/project/registry_group.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/project/registry_node.dart';
import '../bridge/patcher_gateway.dart';
import 'patch_placement_notice.dart';

/// Resolves a `mix.` bus [address] a patcher is placed on to the live gateway
/// channel its source `Sound` mounts on.
///
/// Returns `null` when no such bus exists in the live mix (a stale placement →
/// graceful degradation). Otherwise the record's [channelId] is `null` for the
/// master bus and the opaque channel id (`YseGateway.createChannel`'s) for a user
/// bus — exactly what [PatcherGateway.mountAsSource] takes.
typedef PatchBusResolver = ({int? channelId})? Function(EntityAddress address);

/// Reconciles the engine's live **patchers** — one native patcher per open
/// `patch.` entity — against the project registry (design
/// `docs/design/patcher.md` §3, §4, §8; issue #220).
///
/// The patcher counterpart of [PhiEngine]'s `mix.` channel sync and the
/// [RackMaterialiser]'s voice/fx sync: it materialises one [PatcherGateway]
/// instance per `patch.` entity — **parsing the payload dump on open** — keyed by
/// address so a survivor keeps its live native graph across an unrelated re-sync,
/// and tears the instance down when the entity is deleted or the project closes.
///
/// **Source placement lifecycle.** A patch's payload carries a [PatchPayload.placement]
/// bus. Placement persists; whether the source is *running* does not, so a loaded
/// project starts silent (consistent with clips) and the source is [start]ed /
/// [stop]ped explicitly. A running source is kept mounted on its current placement
/// bus across re-syncs; a placement naming a bus that is not in the live mix
/// **degrades gracefully** — the source is left unplaced and a [PatchPlacementNotice]
/// is surfaced, never blocking anything.
///
/// **Dump-to-payload on save.** Edits go through journaled gesture commands that
/// dirty the `patch.` entity; the *content* is the live native dump, refreshed
/// into the entity payload by [flushToPayloads] on save / autosave (a no-op for a
/// patch whose dump is unchanged, so a clean save writes nothing spurious).
class PatchReconciler {
  PatchReconciler({
    required PatcherGateway gateway,
    required PatchBusResolver resolveBus,
    required void Function(PatchPlacementNotice notice) onNotice,
    int mainOutputs = 1,
  }) : _gateway = gateway,
       _resolveBus = resolveBus,
       _onNotice = onNotice,
       _mainOutputs = mainOutputs;

  final PatcherGateway _gateway;
  final PatchBusResolver _resolveBus;
  final void Function(PatchPlacementNotice notice) _onNotice;
  final int _mainOutputs;

  /// The live native patcher for each open `patch.` entity, keyed by address so
  /// identity (and the parsed graph + running state) survives an unrelated sync.
  final Map<EntityAddress, _OpenPatch> _open = {};

  /// The addresses of every currently-open patch.
  Iterable<EntityAddress> get openPatches => _open.keys;

  /// Whether the `patch.` entity at [address] has a live native instance.
  bool isOpen(EntityAddress address) => _open.containsKey(address);

  /// The gateway instance id backing the open patch at [address], or `null` when
  /// it is not open — the seam the surface (a later epic issue) drives edits on.
  int? instanceIdOf(EntityAddress address) => _open[address]?.instanceId;

  /// Whether the patch at [address] is currently mounted + sounding as a source.
  bool isRunning(EntityAddress address) => _open[address]?.running ?? false;

  /// The source-placement bus the patch at [address] currently carries, or `null`
  /// when it is unplaced / not open.
  EntityAddress? placementOf(EntityAddress address) =>
      _open[address]?.placement;

  /// Reconcile every native patcher against [registry]. Safe to call on any
  /// registry change: it materialises newly-added patches (parsing their dump),
  /// tears down removed ones, refreshes each survivor's placement, and keeps every
  /// running source mounted on its current bus (degrading a stale placement).
  ///
  /// The full pass, for standalone callers. The engine's channel sync instead
  /// drives [materialise] and [teardownRemoved] as **two phases** around the
  /// [RackMaterialiser]'s fx-chain sync (issue #225): new patchers must exist
  /// *before* a chain builds a `DspObject.patcherInsert` borrowing one, and a
  /// removed patch's native patcher must be freed *after* the chains that borrow
  /// it have been detached — so a wrapper never links a freed patcher.
  void sync(ProjectRegistry registry) {
    teardownRemoved(registry);
    materialise(registry);
  }

  /// Materialise newly-added patches (open = parse the dump), refresh each
  /// survivor's placement, and keep every running source mounted on its current
  /// bus — **without** tearing down removed patches (that is [teardownRemoved]).
  /// A removed patch's `_open` entry therefore survives until [teardownRemoved],
  /// so a chain still borrowing its patcher stays valid until it is detached.
  void materialise(ProjectRegistry registry) {
    final desired = <EntityAddress, PatchPayload>{};
    _walkPatches(registry, (address, payload) => desired[address] = payload);

    // Materialise new patches (open = parse the dump); refresh placement on the
    // survivors **without** re-parsing — the live native graph is the source of
    // truth for an open patch, the payload is refreshed from it on save.
    desired.forEach((address, payload) {
      final open = _open[address];
      if (open == null) {
        final instanceId = _gateway.createInstance(mainOutputs: _mainOutputs);
        _gateway.parseJson(instanceId, jsonEncode(payload.dump));
        _open[address] = _OpenPatch(instanceId, payload.placement);
      } else {
        open.placement = payload.placement;
      }
    });

    // Keep every running source mounted on its current placement bus.
    for (final entry in _open.entries) {
      if (entry.value.running) _remountRunning(entry.key, entry.value);
    }
  }

  /// Tear down the native patchers of patches whose entity is gone (delete /
  /// close) — unmounting any running source first. Run *after* the fx-chain sync
  /// so no insert still borrows the patcher being freed (issue #225).
  void teardownRemoved(ProjectRegistry registry) {
    final desired = <EntityAddress>{};
    _walkPatches(registry, (address, _) => desired.add(address));
    for (final address in _open.keys.toList()) {
      if (!desired.contains(address)) _teardownOne(address);
    }
  }

  /// Start the patch at [address] as a source: mount it as a `Sound` on its
  /// placement bus and begin sounding. Returns whether it started.
  ///
  /// A no-op (returns `false`) when the patch is not open or is **unplaced**; when
  /// its placement names a bus absent from the live mix, the source is left
  /// unplaced and a [PatchPlacementNotice] is surfaced (graceful degradation).
  bool start(EntityAddress address) {
    final open = _open[address];
    if (open == null) return false;
    final placement = open.placement;
    if (placement == null) return false;
    final resolution = _resolveBus(placement);
    if (resolution == null) {
      _degrade(address, placement);
      return false;
    }
    _gateway.mountAsSource(open.instanceId, busChannelId: resolution.channelId);
    open.running = true;
    open.mountedChannelId = resolution.channelId;
    return true;
  }

  /// Stop the source at [address] — unmount its `Sound`, silencing it. A no-op
  /// when the patch is not open or not running.
  void stop(EntityAddress address) {
    final open = _open[address];
    if (open == null || !open.running) return;
    _gateway.unmountSource(open.instanceId);
    open.running = false;
    open.mountedChannelId = null;
  }

  /// Refresh each open patch's entity payload from its live native dump — the
  /// dump-to-payload step run on save / autosave (design §3, §8). Records an
  /// [UpdateEntityPayloadCommand] through [recordCommand] for every patch whose
  /// dump actually changed (so the edit is dirty-tracked + journaled like any
  /// other), and nothing for the rest. Placement is carried through untouched.
  void flushToPayloads(
    ProjectRegistry registry,
    void Function(ProjectCommand command)? recordCommand,
  ) {
    _open.forEach((address, open) {
      final entity = registry.entityAt(address);
      if (entity == null) return; // gone; a later sync tears it down.
      final current = _payloadOf(entity.payload);
      final next = current.withDump(
        _decodeDump(_gateway.dumpJson(open.instanceId)),
      );
      if (next == current) return; // unchanged — no spurious command.
      final command = UpdateEntityPayloadCommand(
        registry,
        address,
        next.toJson(),
      );
      command.apply();
      recordCommand?.call(command);
    });
  }

  /// Dispose every native patcher and reset — the patcher counterpart of the
  /// channel / rack teardown, run when the engine rebinds a different project or
  /// stops. Leaves the registry untouched.
  void teardown() {
    for (final open in _open.values) {
      if (open.running) _gateway.unmountSource(open.instanceId);
      _gateway.disposeInstance(open.instanceId);
    }
    _open.clear();
  }

  // ─── internals ──────────────────────────────────────────────────────────────

  /// Re-resolve a running source's placement and keep it mounted on the right
  /// bus: unmount when the placement was cleared, degrade (unplaced + notice) when
  /// the bus vanished, or re-mount when the resolved channel changed.
  void _remountRunning(EntityAddress address, _OpenPatch open) {
    final placement = open.placement;
    if (placement == null) {
      stop(address);
      return;
    }
    final resolution = _resolveBus(placement);
    if (resolution == null) {
      _gateway.unmountSource(open.instanceId);
      open.running = false;
      open.mountedChannelId = null;
      _degrade(address, placement);
      return;
    }
    if (open.mountedChannelId != resolution.channelId) {
      _gateway.mountAsSource(
        open.instanceId,
        busChannelId: resolution.channelId,
      );
      open.mountedChannelId = resolution.channelId;
    }
  }

  void _degrade(EntityAddress address, EntityAddress bus) {
    _onNotice(
      PatchPlacementNotice(
        patch: address,
        bus: bus,
        message:
            'Bus "${bus.format()}" is no longer in the mix — '
            '"${address.format()}" is unplaced.',
      ),
    );
  }

  void _teardownOne(EntityAddress address) {
    final open = _open.remove(address);
    if (open == null) return;
    if (open.running) _gateway.unmountSource(open.instanceId);
    _gateway.disposeInstance(open.instanceId);
  }

  /// Visit every `patch.` entity (recursing through groups so a grouped patch is
  /// reached at its real address), handing each its decoded [PatchPayload].
  void _walkPatches(
    ProjectRegistry registry,
    void Function(EntityAddress address, PatchPayload payload) onPatch,
  ) {
    void visit(RegistryNode node, EntityAddress address) {
      if (node is RegistryEntity) onPatch(address, _payloadOf(node.payload));
      if (node is RegistryGroup) {
        for (final child in node.children) {
          visit(child, address.child(child.name));
        }
      }
    }

    for (final child in registry.childrenOfKind(RegistryKinds.patch)) {
      visit(
        child,
        EntityAddress(kind: RegistryKinds.patch, segments: [child.name]),
      );
    }
  }

  PatchPayload _payloadOf(Object? payload) {
    if (payload is PatchPayload) return payload;
    if (payload is Map) {
      return PatchPayload.fromJson(payload.cast<String, Object?>());
    }
    return PatchPayload.empty;
  }

  Map<String, Object?> _decodeDump(String content) {
    if (content.isEmpty) return const {};
    final decoded = jsonDecode(content);
    return decoded is Map ? decoded.cast<String, Object?>() : const {};
  }
}

/// One open `patch.` entity's live native state: the gateway [instanceId], its
/// current source [placement] bus, and — when running — the channel its `Sound`
/// is mounted on ([mountedChannelId], `null` = master).
class _OpenPatch {
  _OpenPatch(this.instanceId, this.placement);

  final int instanceId;
  EntityAddress? placement;
  bool running = false;
  int? mountedChannelId;
}
