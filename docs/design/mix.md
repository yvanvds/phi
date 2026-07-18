# Mix — the bus tree, sends, and returns

> Detail doc #3 of [phase2-direction.md](../phase2-direction.md) §4.3.
> Design record, 2026-07-18 — reviewed; decisions in §10. Leads to the
> "mix" epic on `yvanvds/phi`.

## 1. The problem

The registry and settings epics already moved the Mix surface past the
direction doc's snapshot: strips are `mix.` registry entities, rename and
remove work, and volume/mute/solo persist through gesture-coalesced
commands. What remains is everything that makes it a *mixing console*
rather than a row of faders:

- **No grouping.** The registry supports groups; the gateway API is flat
  (every channel parents to master); the surface renders one row.
- **No sends and no return buses** — the engine has both, unexposed.
- **Master state is not persisted** — a reload forgets the master fader.
- **Metering is one post-fader mono peak per strip** — the engine meters
  pre/post per speaker output.
- The direction doc's surround question is unanswered.

## 2. What the engine offers (confirmed against the bridge)

Substantially more than the direction doc assumed:

- **A real channel tree.** `Channel.create(name, parent:)` and
  `moveTo(parent)` — children's audio flows through their parent; the
  tree is rooted at master.
- **Return buses.** `Channel.createReturn(name, sendSlots:)` — aux buses
  *outside* the tree; their output folds into master after the source
  tree. Returns may send onward (delay → reverb); the engine rejects
  cycles, self-sends, and sends into non-returns by construction (logged
  no-op, never a crash).
- **Aux sends.** Four slots per channel by default
  (`createWithSends` for more; the count is fixed at creation).
  `send(slot, returnBus, level:, preFader:)` — post-fader by default;
  `setSendLevel` is ramped and safe to write every control tick;
  `clearSend` detaches.
- **Metering.** Pre- and post-fader peaks, linear or dB, whole-channel
  or **per speaker output** (`numOutputs`, indexable).
- **Insert DSP per channel** (`Channel.dsp`, pre-fader) and a single
  movable global reverb (`attachReverb`) — both stay with the racks &
  voices epic; noted here as existing seams only.
- **No native mute/solo** — stays collapsed to effective volumes in
  Dart, as today.

No engine issues needed for this epic.

## 3. The tree — groups are buses

The `mix.` namespace realises the "hierarchy = routing" decision
(direction §4.3): **a registry group in `mix.` is a bus.** `mix.drums`
is a real engine channel; `mix.drums.kick` parents to it; moving a strip
between groups (`rename = refactor`) re-parents the engine channel with
`moveTo`. The tree stays small and hand-authored — families and stems,
not one strip per identity (the hundreds of identities live in the scene
and share buses many-to-one).

Representation: the registry gains **kind-declared group payloads** — a
kind may declare that its groups carry an entity payload in
`_group.json` (alongside the existing ordering/color metadata). For
`mix.`, that payload is the same shape as a strip's (volume / mute /
solo / voice / sends), so a group bus has a fader like any strip. Other
kinds (`clip.`, …) declare nothing and are unaffected.

**Master stays implicit** — it is not an entity: always present, cannot
be renamed, removed, grouped, or sent anywhere. Its live state (volume,
mute) moves into the **project manifest** (`project.json`), closing the
persistence gap. The alternative — a special-cased `mix.master` entity —
buys nothing but exclusion rules.

Depth is unrestricted (the engine tree nests freely), but the surface is
designed for one to two levels; deeper nesting renders but isn't
optimised for.

## 4. Returns and sends

- A return is a `mix.` entity with `"return": true` in its payload,
  allowed **only at top level** (the engine excludes returns from the
  tree, so nesting one under a group would lie about routing). The
  surface renders returns in their own section beside master.
- A strip's (or group bus's) sends live in its payload:

  ```json
  "sends": [
    { "to": "mix.verb", "level": 0.4, "preFader": false }
  ]
  ```

  Slot index = list index. Targets must be returns — validated at edit
  time (the engine would reject the wiring anyway; the UI never offers a
  non-return target). More than four sends on one channel materialises
  it via `createWithSends` automatically — no user-facing knob.
- Send targets register in the **back-reference index**: deleting a
  return warns with the list of strips still sending to it; confirming
  clears those sends. Renaming a return rewrites every `"to"` — the
  ordinary refactor.
- Send levels are performance controls: level drags are
  **gesture-coalesced** exactly like fader drags (one command on gesture
  end), applied live through the ramped `setSendLevel`.

## 5. Mute and solo in a tree

Semantics, computed Dart-side as effective volumes (as today):

- **Mute** a node → its whole subtree is silent (audio flows through the
  parent, so zeroing the group's effective volume is sufficient and
  cheap).
- **Solo** any set of nodes → audible = the soloed nodes, their
  descendants, and their ancestors (the path to master must stay open);
  every other tree node is effectively muted. Soloing a group solos the
  family; soloing a leaf inside a muted group stays silent (mute wins on
  the path — console convention).
- **Returns are exempt from solo** in v1: they carry sends from whatever
  is audible, and muting them independently is one click. Revisit only
  if practice disagrees.

## 6. Surround and multichannel

The answer to the direction doc's open question is that the mix tree is
**layout-agnostic and has no pan controls**:

- Spatial placement is the scene's job (sounds and agents position
  themselves; the engine renders them into the device's speaker layout,
  chosen in settings §4.2). A bus neither knows nor cares how many
  speakers exist — it carries the layout-wide signal transparently.
- What the mix surface *does* owe the performer is **visibility**: the
  master strip gains one meter bar per speaker output
  (`numOutputs` × `peakDbPost(output:)`) — on stereo that's the familiar
  two bars; on 5.1 it's six. User strips keep a single post-fader meter
  (per-output metering is a master-level diagnostic; strips stay
  compact). Pre-fader metering is exposed through the gateway but gets
  no UI toggle in v1.

## 7. Surface UX

- The rack renders **groups as framed sections**: group header (name,
  fader, mute/solo, meter) with its child strips inside; top-level
  strips and groups flow left-to-right; master pinned right with the
  returns section beside it.
- The header `+` becomes a small menu: **add channel · add group · add
  return** (names validated by the registry rule, as today).
- **Drag a strip into / out of a group** to re-route it (regroup =
  refactor = `moveTo`); drag within a section to reorder
  (`_group.json` order, as the registry already supports).
- Each strip gains a compact **SENDS** area: one row per send — target
  picker (`PhiSelect`, returns only), level mini-fader, pre/post toggle
  — plus an add-send row while slots remain.
- Delete goes through the registry's delete-impact dialog when
  back-references exist (a return with active senders).

## 8. Runtime architecture

- **Gateway** (`YseGateway`) grows the tree surface, ids stay opaque
  ints: `createChannel(name, {parentId})`, `moveChannel(id, parentId?)`,
  `createReturnChannel(name, {sendSlots})`, `setSend(id, slot, returnId,
  level, preFader)`, `setSendLevel`, `clearSend`,
  `channelOutputCount(id)` + per-output/pre peak variants, and the
  master equivalents. Fake fabricates all of it — the surface stays
  fully testable without audio hardware.
- **Engine sync** (`_syncChannelsFromRegistry`) becomes tree
  reconciliation: materialise groups before children, re-parent moved
  nodes with `moveChannel`, create returns, then wire sends in a second
  pass (targets must exist first). Solo/mute recompute walks the tree.
  Channel identity stays keyed by address, so live meters and gestures
  survive a re-sync, as today.
- **Domain**: `MixStrip` payload grows `return` + `sends`; the codec
  and command layer extend accordingly; group-payload support lands in
  the registry (`kind-declared group payloads`, §3).

## 9. Out of scope

- **Insert effects and reverb UI** — racks & voices epic; the `dsp` and
  `attachReverb` seams wait there.
- **Voice → bus binding** — racks & voices epic (`voice.` entities).
- **Pan / spatial controls on strips** — deliberately never (§6); the
  scene owns space.
- **Pre-fader meter UI, channel virtualisation (`Channel.virtual`)** —
  exposed by the engine, no v1 UI.
- **VCA-style groups, mix snapshots/scenes** — post-Phase-2 candidates;
  the state-machine epic may subsume snapshots.

## 10. Review decisions (2026-07-18)

1. **One name, re-aligned.** `MixStrip`'s free-form display name had
   quietly diverged from the registry's one-name rule (registry doc §3);
   it is **removed outright** — the strip header shows the address leaf
   (`kick_drum`), and live code (`mix.kick_drum`) and the console never
   disagree. **No backwards compatibility**: divergent code and stored
   payloads are discarded, not migrated — nothing pre-dating this
   decision needs to keep loading.
2. **Group payloads live in `_group.json`** — one file per node, the
   path stays the address.
3. **Returns are exempt from solo** in v1 (§5).
4. **Send slots auto-upgrade** via `createWithSends` when a payload
   wants more than four — no user-facing knob, no UI cap.

## 11. Proposed epic breakdown

Roughly seven issues, in dependency order:

1. Registry: kind-declared group payloads (`_group.json`), delete-impact
   and rename-refactor coverage for payload references (pure domain,
   TDD).
2. Mix domain: `MixStrip` growth (`return`, `sends`), codec, drop the
   display-name field (decision 1 — no compat shim), master state into
   the manifest.
3. Gateway: tree / returns / sends / per-output + pre metering surface
   (Real + Fake).
4. Engine: tree reconciliation, second-pass send wiring, tree mute/solo
   semantics, master persistence wiring.
5. Surface: grouped rack rendering, add-menu (channel/group/return),
   drag-to-group, reorder.
6. Surface: returns section + per-strip SENDS area (target picker,
   level, pre/post), gesture-coalesced send commands.
7. Master per-output meters (layout-aware); delete-impact dialog wiring
   for returns.
