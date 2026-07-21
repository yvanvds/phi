/// The seeded default state graph — `intro → verse` — as `state.` entity
/// documents (design `docs/design/state-graph.md` §3, issue #240).
///
/// Mirrors what the State surface has always seeded on first open: `intro` at
/// (160, 160) with one manual transition to `verse` at (400, 160). `intro` is
/// the *live* one today, but live-ness is performance state and never
/// persists — the registry-backed controller (issue #241) keys the seeded
/// live state, not the payload.
library;

import 'dart:ui';

import '../../project/entity_address.dart';
import '../../project/registry_kinds.dart';
import 'state_document.dart';
import 'state_transition_spec.dart';

/// The address of the seeded `state.intro` entity.
final EntityAddress introStateAddress = EntityAddress(
  kind: RegistryKinds.state,
  segments: const ['intro'],
);

/// The address of the seeded `state.verse` entity.
final EntityAddress verseStateAddress = EntityAddress(
  kind: RegistryKinds.state,
  segments: const ['verse'],
);

/// The seeded `state.intro` payload: the canvas position the surface has
/// always used, plus the one manual transition to `state.verse`.
StateDocument introStateDocument() => StateDocument(
  position: const Offset(160, 160),
  transitions: [StateTransitionSpec(to: verseStateAddress)],
);

/// The seeded `state.verse` payload — a bare node, no outbound transitions.
StateDocument verseStateDocument() =>
    const StateDocument(position: Offset(400, 160));
