# Live Coding — the `phi` library, evaluation, and completion

> Detail doc #7 of [phase2-direction.md](../phase2-direction.md) §4.7.
> Design record, 2026-07-19 — reviewed; decisions in §8. Leads to the
> "live coding" epic on `yvanvds/phi`.
>
> **Depends on:** the racks & voices design ([racks-and-voices.md]
> (racks-and-voices.md), epic #203) for voice/fx addressing, the
> midi-clips sessions (epic #183) for clip control, and the patcher
> design ([patcher.md](patcher.md), epic #217) for patcher slots.
> References are to reviewed designs, not implementations. **This epic
> also files the first new engine issues of Phase 2** (§4).

## 1. The problem

The Code surface evaluates into a `NoOpCodeEvaluator` — real Python
never runs. The engine's embedded CPython (`LiveCoding.run`, the `yse`
bus module) is live and well-designed, but it is **primitives only**:
`yse.send("...", v)` strings everywhere, exactly the friction the
direction doc named. And the engine's DSL spec deliberately omits
introspection — scripts cannot list what exists. Phi holds the missing
piece: the registry knows every name, Dart-side, live.

## 2. What exists (confirmed against yse's DSL spec and module)

- **The bus DSL is real:** `send / on / unsubscribe / latch / schedule
  / tick / cancel_all / fresh_scope`, four value types (int, float,
  str, list[float]), generation-tagged hot-reload, one error callback
  delivering full tracebacks, batch-per-tick script thread (a publish
  at tick *t* lands at *t+1* — control-rate by construction).
- **Engine-owned prefixes exist by design** (yse spec §"Address
  grammar"): `sound.<name>.<prop>` (volume, speed, position),
  `channel.<name>.<prop>` (volume), `patcher.<name>.<slot>`
  (gSend/gReceive). Phi already names engine channels with entity
  addresses (`createChannel(name)`), so `channel.<bus>.volume` is
  addressable *today*; patcher instances must carry their entity name
  when epic #217 lands (noted there).
- **Namespace persists across evaluations**; `cancel_all` is
  deliberately explicit (layering is the default, per the spec).
- **Two gaps, both engine-side** (§4): no synth/note prefix, and no
  host-side bus tap (the C API's only outbound callback is the error
  channel).

## 3. The `phi` library

A pure-Python module, shipped as source in the Phi repo and exec'd
into the interpreter at boot (installed into `sys.modules`, so
`import phi` works). No engine build changes for the library itself.

- **Dot-access namespaces mirror the registry:** `voice`, `clip`,
  `mix`, `fx`, `patch`, `domain`, `var`, `state`. Groups nest
  (`clip.drums.intro_fill`); a group proxy is iterable and carries
  group verbs (`clip.drums.stop()`). `__getattr__` resolves against a
  name table; `dir()` works, so exploration in-script matches the
  editor's completion.
- **The mirror becomes real.** The `RegistryMirror` seam (no-op since
  the registry epic) pushes create / rename / regroup / delete into
  the interpreter as `phi._sync(...)` scripts. Proxies reference table
  *entries*, not address strings — so `pad = voice.bells` held in a
  running script **follows a rename** (the resolve-once idiom,
  enforced by construction rather than convention).
- **Verb-first vocabulary** (working set, grown with use): `play`,
  `stop`, `pause`, `loop`, `note`, `off`, `set`, `fade`, `fire`,
  `every`, `after` (`every`/`after` are sugar over `yse.schedule` in
  domain beats/ticks). Words from music, not CS — projected-view
  legibility is a design input, not an afterthought.

## 4. Two command planes (and the engine issues this epic files)

Every `phi` verb rides one of two paths:

1. **Engine-direct** — publishes to an engine-owned prefix; the engine
   consumes it with no host round-trip. Available now:
   `mix.pads.volume = 0.6` → `channel.<addr>.volume`;
   `patch.swirl.send("cutoff", 0.4)` → `patcher.<addr>.cutoff`.
2. **Host-mediated** — publishes to a reserved `phi.ctl.*` address;
   the **host taps the bus**, dispatches to the owning controller
   (clip sessions, voices, state machine, variables, tempo stack), and
   effects flow back through normal materialisation. Structural verbs
   live here: `clip.x.play()`, `voice.bells.note(60)` (v1),
   `var.section = "b"`, `state.fire(...)`, `domain.drum.tempo = 124`.
   Latency is one to two ticks — fine for structure, and for v1 note
   audition.

**Engine issues filed by this epic** (on `yvanvds/yse-soundengine` /
`dart-yse`, per the direction doc's rule — at the moment the area
starts):

- **Host bus tap:** a C API to subscribe the host to a bus prefix
  (mirroring the error-callback pattern — main-thread delivery during
  `update()`), wrapped in dart-yse. This is the one *blocking*
  dependency: the control plane needs it.
- **Synth bus prefix** (enhancement, non-blocking): `synth.<name>.*`
  note/controller addresses consumed engine-side, following the
  existing `sound.`/`channel.` pattern — upgrades `voice.note` from
  host-mediated to engine-direct *transparently* (the `phi` verb
  doesn't change).

> **Verification — engine-direct prefixes (2026-07-21, issue #234).**
> Both reserved prefixes the engine-direct plane rides were checked
> against yse's authoritative DSL spec (`docs/design/live_coding_dsl.md`
> §"Address grammar") and the shipped engine:
>
> - **`channel.<name>.volume` — live.** yse-soundengine #123 shipped
>   (closed via #131). Phi names every engine channel through
>   `createChannel(name)`, so `mix.<bus>.volume` set/fade publishes
>   engine-direct to `channel.<address>.volume` with no `phi.ctl`
>   fallback.
> - **`patcher.<name>.<slot>` — prefix live, instance naming pending.**
>   yse-soundengine #122 shipped (closed via #130), and `patch.<name>`
>   verbs emit the spec'd `patcher.<address>.<slot>` address. The spec
>   makes only *named* patcher instances bus-addressable, though, and
>   phi still creates patchers anonymously (dart-yse exposes no
>   `Patcher.name(...)`; #219 landed without threading it). The verb
>   stays engine-direct — forward-correct, it starts working the moment
>   the instance is named — and the naming gap (a gateway/FFI concern
>   outside the live-coding verb layer) is tracked in **#318**.
>
> Set and fade emitted addresses/values are asserted in
> `python/tests/test_engine_direct.py`; `fade` is control-rate — it steps
> the value once per tick through `yse.schedule`, assuming no engine ramp
> API.

## 5. Evaluation — the Code surface grows up

- **`RealCodeEvaluator`** over `LiveCoding.run` replaces the no-op
  behind the existing `CodeEvaluator` seam; Ctrl+Enter block dispatch
  stays exactly as-is.
- **Tracebacks inline:** the `LiveCoding.errors` stream renders as an
  error strip pinned under the editor (file/line parsed from the
  `"<script>"` traceback format), plus the existing eval flash turning
  red. No silent failures — the spec guarantees one error sink.
- **Layering is the default**, per the yse spec's deliberate stance; a
  header **`fresh` toggle** prefixes evaluations with
  `yse.cancel_all()` for replace-mode workflows, with a visible
  indicator so the mode is never ambient state you forgot.
- **`code.` entities:** scripts join the registry — groups, ordering,
  rename, the standard affordances — with a library panel mirroring
  the clip library's pattern. The seeded scratch script keeps the
  surface alive on a fresh project.

## 6. Completion — registry-driven, no LSP

As settled in the direction doc:

- Typing `voice.` (or any `phi` namespace + dot) pops a completion
  list **fed directly from the Dart registry** — live, accurate,
  Phi-flavored (voice colors, clip lengths, group nesting). One level
  deeper (`voice.bells.`) completes from a **static method table**
  shipped with the `phi` library (generated from its source, so the
  two never drift).
- `re_editor`'s autocomplete hooks host the popup; no language server,
  no stub generation, no Python analysis. A real LSP remains a
  possible later upgrade for user-defined-function completion — out of
  scope here.

## 7. Out of scope

- **Python-authored MIDI transforms** — the transform chain evaluates
  in Dart; calling into engine-side Python per evaluation is an
  unsolved cross-boundary problem. The `CustomTransformRegistry`
  handshake stays as-is (fake-driven in tests); its own design pass
  comes later.
- **Projected-view enhancements** (name expansion, change
  highlighting) — the audience-legibility subsystem is its own later
  wave; the existing projection keeps working.
- **Script-driven registry CRUD** (`voice.create(...)` from code) — v1
  scripts address what exists; minting entities from code arrives with
  the state-machine/scene wave when its undo/journal semantics are
  designed.
- **Sample-accurate scripting** — never (the yse spec's non-goal);
  sample-accurate sequencing is what clips and transports are for.

## 8. Review decisions (2026-07-19)

1. **Control-plane-first** (§4): every structural verb ships
   host-mediated over the new bus tap; engine-direct upgrades (the
   synth prefix) land later as transparent optimisations — the `phi`
   verbs never change.
2. **`code.` entities + library panel ship in v1** — minimal tree +
   open + evaluate.
3. **The `fresh` toggle defaults off** — layering by default, matching
   the yse spec's philosophy, with a visible mode indicator.
4. **The `phi` library ships as plain Python source in the Phi repo**
   — user-readable, eventually user-extensible.

## 9. Proposed epic breakdown

Roughly eight issues, in dependency order:

1. **Engine dependency filing + bridge:** file the host-bus-tap issue
   (yse + dart-yse) and the synth-prefix enhancement; wrap the tap in
   `LiveCoding`/gateway when it lands (Real/Fake — the fake tap makes
   everything below testable immediately).
2. `phi` library core: module bootstrap, namespaces + group proxies
   over a name table, entry-referencing proxies (rename-following),
   `_sync` protocol, verb skeleton — pure Python + Dart-side tests
   through the fake evaluator/tap.
3. `RegistryMirror` becomes real: registry → `_sync` push on
   create/rename/regroup/delete, boot-time full sync, generation-safe
   re-push after `System` re-init.
4. `RealCodeEvaluator` over `LiveCoding.run` + inline traceback strip
   + `fresh` toggle; the shell wires real Python end-to-end.
5. Control plane: `phi.ctl` dispatch — host tap → controller routing
   for clip play/stop/pause/loop (+ group verbs), voice note/off
   (audition path), var/state/domain-tempo verbs; graceful unknown-
   address handling.
6. Engine-direct verbs: mix volume + patcher slots over the existing
   prefixes (entity names threaded onto engine objects where missing).
7. `code.` entities + library panel (per review decision 2).
8. Completion: registry-driven namespace popup + static method table
   in `re_editor`; Phi-flavored rows (colors, lengths, groups).
