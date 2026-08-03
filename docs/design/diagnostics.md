# Diagnostics & Resilience — see what broke, the morning after

> Detail doc #11 of [phase2-direction.md](../phase2-direction.md)
> §4.11 — the last of the Phase 2 series. Design record, 2026-07-19 —
> reviewed; decisions in §8. Leads to the "diagnostics" epic on
> `yvanvds/phi`.
>
> **Depends on:** nothing blocking — `Log.messages`,
> `LiveCoding.errors`, the settings DIAGNOSTICS section, and the
> recovery dialog are shipped. The notice channel defined here is the
> shared home for the "surfaced notice" every other design referenced.

## 1. The problem

The engine logs (stream, levels, file sink — all shipped in the
bridge), Python tracebacks flow, and half the Phase 2 designs say
"degrades gracefully with a surfaced notice" — but Phi has nowhere to
*put* any of it. Notices would flash and vanish, engine messages go
nowhere, and when a set misbehaves live, the solo dev debugging it the
morning after has nothing to read. A crash also leaves no trace beyond
the journal's recovery dialog.

## 2. The unified log

One **log store** (Dart, ring buffer ~2000 entries) merging three
sources, each entry tagged (source, level, time):

- **Engine** — `Log.messages` (levels mapped from `LogLevel`; the
  stream replaces the engine's own file sink by design).
- **Python** — `LiveCoding.errors` tracebacks (still rendered inline
  in the Code surface; logged as well).
- **App** — Phi's own events: project open/save/recovery, device
  changes and fallbacks, degradation notices from every epic.

A **session log file** mirrors the store:
`%APPDATA%/phi/logs/phi-<timestamp>.log` — per-machine (diagnostics,
not project content), newest-first retention of the last 20 sessions.

## 3. The notice channel

The designs' recurring "surfaced notice" gets one implementation: a
`notice(...)` call that **shows a transient toast and writes a log
entry** — nothing user-facing ever vanishes without a trace. Epics
that shipped ad-hoc notices retrofit onto the channel here (a small
sweep, not a redesign). Errors do the same at error level; the status
bar badges unseen errors (§5).

## 4. The log panel

A **bottom drawer** above the status bar (status-bar toggle + palette
command; `Ctrl+J`-style shortcut via the command registry):

- Entries newest-last with auto-follow; scrolling up pauses follow
  (jump-to-newest button).
- Filters: level, source (engine / python / app), and a text search.
- Copy: selection or the visible filtered set, paste-ready.
- Not a surface — like settings, it is a tool, not a performance
  instrument; it gets no rail entry.

## 5. Status-bar health

- **Audio-device chip:** ok · reconnecting · lost — fed by
  `activeAudioState()` polling on the existing telemetry tick plus
  device-change notices; click opens settings AUDIO.
- The CPU / drops chips stay; the **log toggle badges** the count of
  error-level entries since the panel was last open; click opens the
  drawer filtered to errors.

## 6. Report bundle and crash surfacing

- **Copy diagnostics** (palette command + a button in the settings
  DIAGNOSTICS section, extending the copy that exists): one
  paste-ready block — app + libYSE versions, resolved `YSE_DLL_PATH`,
  device + active state, layout summary, the last 200 log lines, the
  open project path. For filing issues against yourself, efficiently.
- **Clean-shutdown marker:** written at orderly close, removed at
  boot. Missing at boot = the previous session crashed → a notice
  offers the *previous* session's log file (the journal recovery
  dialog already handles the project side; this covers the "what
  happened" side).

## 7. Out of scope

- **Engine watchdog / auto-restart** — auto-reconnect covers devices;
  the audio-stall count is visible (the interpreted `DROPS` metric of
  issue #350, not the engine's raw gauge); anything more is speculative.
- **Python `print()` capture** — the embedded interpreter's stdout is
  not captured (yse spec's deferred concern); a future yse enhancement
  if scripting practice demands it.
- **Remote/telemetry anything** — Phi is a personal instrument; logs
  stay on the machine.
- **Log viewing of *old* sessions in-app** — the folder is the
  interface; the crash notice deep-links the one file that matters.

## 8. Review decisions (2026-07-19)

1. **Logs are per-machine** — `%APPDATA%/phi/logs`, 20-session
   retention; diagnostics, not project content.
2. **The panel is a bottom drawer** — glanceable mid-set, no layout
   disturbance.
3. **Shipped notice sites are retrofitted** onto the channel in this
   epic — one sweep; nothing vanishes without a trace.

## 9. Proposed epic breakdown

Roughly five issues, in dependency order:

1. Log domain: store + ring buffer + entry model, session file writer
   with retention, clean-shutdown marker (pure Dart, seams + fakes).
2. Source wiring: engine stream (level mapping), Python tracebacks,
   the `notice()` channel (toast + log) — and the retrofit sweep of
   shipped notice sites.
3. Log panel drawer: follow/pause, filters, search, copy, shortcut;
   error badge on the status toggle.
4. Status health: audio-device chip (ok/reconnecting/lost) with
   click-through; badge behaviour.
5. Report bundle + crash surfacing: copy-diagnostics command, crashed-
   last-session notice linking the previous log.
