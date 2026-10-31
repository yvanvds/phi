# Settings & Devices — per-machine configuration and the hardware seam

> Detail doc #2 of [phase2-direction.md](../phase2-direction.md) §4.2.
> Design record, 2026-07-18 — reviewed; decisions in §9. Leads to the
> "settings & devices" epic on `yvanvds/phi`.

## 1. The problem

Phi has no settings surface of any kind. The engine opens the platform
default audio device (`RealYseGateway.init()` → `System.init()`), MIDI
output is hard-wired to port 0, sample rate and buffer size are whatever
the device defaults to, and the autosave cadence the registry epic
introduced can only be changed by hand-editing `settings.json`. A
performer must be able to point Phi at the right interface, at the right
buffer size, and trust it to come back after a device hiccup — before any
other surface work makes sense to polish.

The registry epic already seeded the foundation: `AppSettings` (recents +
autosave cadence), the `AppSettingsStore` seam, and
`RealAppSettingsStore` writing `%APPDATA%/phi/settings.json`. This design
grows that seed into the full per-machine configuration layer plus the
settings window over it.

## 2. What is a setting — the scope rule

One litmus test, applied to every candidate: **would this value be wrong
on another machine?** If yes, it is a setting (per-machine,
`settings.json`). If no, it belongs to the project (portable, inside the
`.phi` folder) and must never appear here.

v1 contents:

| Section | Values |
|---------|--------|
| audio | output device (host + name), sample-rate override, buffer-size override, speaker layout |
| midi | output port (by name), enabled input ports (by name) |
| projects | autosave cadence *(exists)*, recent projects *(exists)* — managed in the window (remove / clear / pin), consumed by the File menu |
| diagnostics | read-only: libYSE version, resolved `YSE_DLL_PATH`, active device/host, active sample rate, buffer, output latency |

Explicitly *not* settings: tempo, mix state, voice bindings, window
layout per project (manifest, later), anything an entity file owns.

## 3. Storage — growing `settings.json`

The existing tolerant-parse pattern (`AppSettings.fromJson` falls back
per key) is the migration strategy; a `version` field is added now for
the day tolerance isn't enough:

```json
{
  "version": 1,
  "recentProjects": ["d:/sets/my_set.phi"],
  "pinnedProjects": [],
  "autosaveSeconds": 60,
  "audio": {
    "outputHost": "ASIO",
    "outputDevice": "Fireface UCX",
    "sampleRate": 48000,
    "bufferSize": 256,
    "layout": "auto"
  },
  "midi": {
    "outputPort": "loopMIDI Port",
    "inputPorts": ["Keystation 61"]
  }
}
```

- `audio` and `midi` become nested value types (`AudioSettings`,
  `MidiSettings`) inside `AppSettings` — same immutable/value-equality
  style, each with its own tolerant `fromJson`.
- `pinnedProjects`: paths the performer pinned in the settings window —
  listed first in the File menu and never dropped by the recents cap.
- **Devices are identified by name (+ host), never by index.** Device
  indices shift with every reboot and USB replug; names are the stable
  identity. The same physical interface appearing under two hosts (WASAPI
  *and* ASIO) is two distinct choices — hence the pair.
- `sampleRate` / `bufferSize` are **optional overrides**: absent means
  "device default". Values are validated against the selected device's
  reported `sampleRates` / `bufferSizes` lists at apply time; a stored
  value the device no longer reports falls back to default with a notice.
- `layout` maps to yse's `ChannelType` (`auto`, `mono`, `stereo`, `quad`,
  `5.1`, `5.1side`, `6.1`, `7.1`). The *setting* lives here because the
  layout is passed at `openDevice`; the *strategy* for how the mix tree
  meets a surround layout stays with the Mix detail doc (direction §4.3).
  Default `auto` (engine picks stereo when possible).

## 4. Devices — what the engine already offers

Confirmed against the bridge; no engine work is required for v1:

- **Enumeration:** `System.devices` → `Device` descriptors: name, host
  name, input/output channel names, supported sample rates and buffer
  sizes, default buffer size, latencies. Two calls enumerate: `init()`, as
  a side effect of opening the default device, and — since yse 0.2.0 —
  `System.refreshDevices()`, which lists the devices **without opening a
  stream**, also on an offline session. `initOffline()` on its own lists
  nothing (re-measured against libYSE 3.1.0: 0 devices offline, 19 after a
  refresh, nothing opened — issues #403, #445). Phi boots with
  `initOffline()` + `refreshDevices()` and never calls `init()` (§5, issue
  #449); `YseGateway` no longer exposes it.
- **Open/close:** `System.initOffline()` boots the engine with *no*
  device, and no device *list* until a refresh; `openDevice(DeviceSetup,
  layout:)` opens a chosen one; `closeCurrentDevice()` + `openDevice`
  swaps live — no engine restart. `System.defaultDevice` names the
  platform default.
- **The session rate is locked** from `init()` / `initOffline()` to
  `close()`, so a stored
  rate override cannot reach an open session (dart-yse #53). (libYSE 2.4
  also reported a refused `openDevice` only as a log line, so the bridge
  read the live state back to confirm an open — dart-yse #52. yse 0.2.0
  throws instead, proven by the real-engine contract test, and the
  read-back is gone — issue #445.) Since
  yse 0.2.0 (issue #443) Phi sets `System.requestedSampleRate` from
  `settings.json` *before* the engine starts, so the stored rate is the
  session rate. A rate picked while Phi runs restarts the session in place
  at it (§5 "Live change", issue #448); the read-back shows
  `sessionSampleRate`.
- **Live state:** `activeSampleRate`, `activeBufferSize`, output latency
  in samples — the diagnostics section reads these, not the stored
  settings (they can legitimately differ).
- **Resilience:** the engine's `setAutoReconnect` watchdog is **off**, and
  Phi supervises recovery itself (§5). Under libYSE 2.4 that was forced
  (issue #410): the watchdog reopened `Pa_GetDefaultOutputDevice()` rather
  than the lost device, dropped the chosen buffer size, read `delayMs` as a
  tick count and, once armed, retried on every 16 ms tick with no backoff
  (dart-yse #54). yse 0.2.0 fixed all of that — wall-clock `delayMs`, it
  reopens the session's last-opened device, `maxAttempts` bounds it,
  `reconnectState` / `activeDevice` report the outcome. Re-evaluated in
  issue #445, it **still stays off**: Phi's run reaches for the chosen
  device and then settles on the default *with a notice* (#413), where the
  watchdog does one or the other and falls back silently; the watchdog
  runs inside `update()` and would be a second supervisor contending with
  the coordinator's own opens; and it does not refresh the device list, so
  a replugged device is only found if the host calls `refreshDevices()`
  anyway — which is what each of Phi's attempts already is. Handing over
  would add a timer and lose the notice.
- **No device-change signal at all.** There is no add/remove event on any
  desktop backend, so recovery **polls**: `activeSampleRate == 0` is the
  engine's documented "nothing is open" sentinel, read on Phi's telemetry
  tick.
- **The device list is a snapshot, not a view of the machine** (issues
  #412, #445). It changes only when the engine enumerates, and nothing can
  rescan PortAudio while a stream is open, so:
  - while audio runs, a device unplugged **keeps its entry** — the
    dropdown goes on offering it, and the only way Phi finds out it is gone
    is that opening it fails — and a device plugged in **does not appear**
    until the performer presses **Rescan devices** in Settings › Audio
    (issue #450): `closeCurrentDevice()` — only the stream; the session, its
    rate and everything built on it stay, so this is not the #448 session
    restart — then `refreshDevices()` with nothing open, then the same device
    reopened. A brief, deliberate dropout, announced next to the button. It
    changes no choice: if the open device is gone it lands on the default
    with a notice (the stored preference intact), every device gone is the
    total loss below, and with nothing open it is one recovery attempt run
    now;
  - once nothing is open (a total loss), `refreshDevices()` restarts the
    backend and reads the machine as it is now. Every recovery attempt
    starts with one, so an interface that came back — under a new index or
    not — or one first connected after Phi started is found, and one that
    is gone drops out of the list.
  Under libYSE 2.4 the list was frozen at the first `init()` for the whole
  process, so an empty list meant "restart Phi"; that notice is gone.
  `FakeYseGateway` models both halves: its `devices` is the hardware, and
  `audioDevices()` is the snapshot the last `init()` / `refreshDevices()`
  took of it — re-read on a refresh only when no stream is open.
- **Recovery is cheap, re-init is not.** `closeCurrentDevice()` tears down
  only the stream — every channel, sound and clock survives — so a refresh
  plus `openDevice` right afterwards is the designed flow from a closed
  device.
  `System.close()` is a different animal (it joins the worker pools and
  destroys every channel), so recovery never goes near it.
- **MIDI:** input/output device counts + names by index
  (`midiInDeviceName` / `midiOutDeviceName`); `MidiIn.open` /
  `MidiOut.open` take the index — Phi resolves stored *names* to current
  indices at open time.

## 5. Apply semantics

**Boot** (issue #449). One step, straight onto the stored device:

1. The composition root (`PhiApp.initState`) reads the `audio` section
   synchronously (`AppSettingsController.readStoredSync`) and hands it to
   `PhiEngine.requestBootAudio` before `start()`.
2. `start()` → `AudioDeviceCoordinator.boot(stored)`:
   `requestedSampleRate = stored.sampleRate` → `initOffline()` →
   `refreshDevices()` → resolve host+name → `openDevice` on **exactly that
   device**, with overrides and layout. Nothing else is ever opened first,
   so the session rate is never negotiated against a device the performer
   did not ask for. If the device cannot run the session rate (no stored
   rate, a 44.1 kHz-only interface on a 48 kHz session), the still-empty
   session is restarted at a rate it offers before the open. Engine
   auto-reconnect off; Phi's own recovery supervisor takes over (below).

If the stored device is **missing or fails to open**, boot opens the
platform default instead, shows a non-blocking notice ("… — using the
default device"), and **keeps the stored preference intact** — a performer
whose interface wasn't plugged in yet must not lose their configuration to a
helpful fallback. Boot runs before the shell exists, so its notices are
retained (`PhiEngine.bootAudioNotices`) and toasted when the shell mounts.
The shell no longer re-applies the stored device after settings load.

The "start a session and open this device in it" step is a reusable piece
of the coordinator (`_startSession`); the live restart for a rate change
(`restartTo`, #448, below) is `close()` + the same steps.

> **History.** Before #449 boot was two steps: `init()` opened the platform
> default, then the shell applied the stored device as a live switch once
> settings had loaded. The note below is why.
>
> This originally read `initOffline()` → resolve → `openDevice`, so that
> boot never opened a device the performer didn't ask for. It cannot work:
> an offline engine has no device list to resolve against (§4), so *every*
> stored device fell through to "not available" and then to "no audio" —
> the stored-device boot was silent on real hardware while green in every
> test (#403). The cost of `init()` first is that the platform default is
> open for a moment before the swap; nothing is playing at boot, so it is
> inaudible.
>
> With the offline boot gone, a settings-carrying `PhiEngine.start()` was
> just this same two-step sequence spelled inside the engine — and, since
> the shell never called it, an unrun copy of it, which is exactly where
> #403's defect survived. It was deleted (#405): boot-from-settings is the
> live switch above, and the path that ships is the path that is tested.
> Revisit if the engine grows an enumerate-without-opening call
> (dart-yse #51) — then, and only then, is an offline boot worth a second
> entry point. *Since yse 0.2.0 it has one* (`refreshDevices()`, issue
> #445), and #449 made the offline boot the one boot path again — replacing
> the two-step sequence rather than adding a second entry point next to it.

**Live change.** Picking a device / rate / buffer in the window applies
immediately (`closeCurrentDevice` + `openDevice`) through that same
`switchAudioDevice`. A brief audio dropout during the swap is accepted;
selecting a device in a dropdown *is* the deliberate act, no separate Apply
button. Failure reverts to the previous working device, raises a notice,
and updates the stored choice only on success.

**Live rate change — restarting the session in place** (issue #448). The
session rate is locked from init to close (§4), so two picks cannot be a
plain swap: a different sample rate, and a device that cannot run the
session's rate (yse 0.2.0 refuses the open). `AudioDeviceCoordinator.
needsSessionRestart` spots both; `PhiEngine.switchAudioDevice` then runs
`_restartAudioSession` instead of `switchTo`:

1. Release every native object built on the session, **keeping every Phi
   controller**: flush patch dumps into their payloads; the trigger
   scheduler's clocks (armed counts remembered), every clip transport and
   the count-in clock (`EngineMidiController.releaseTransports`, which also
   closes the MIDI-out port), the metronome transport, the click voice, the
   patch editors, then the racks, patchers and channels
   (`_teardownChannels`).
2. `AudioDeviceCoordinator.restartTo(desired)`: `close()` →
   `requestedSampleRate` → `initOffline()` → `refreshDevices()` → open the
   device. A refusal reopens the previous device at the previous rate
   (`switchReverted`), else the default, else nothing (`noAudioDevice` +
   recovery) — `switchTo`'s contract.
3. Re-materialise from the registry the way a project open does — channels,
   sends, racks, patchers, the open patch's editor — and bring the
   performance back: master level and test signal re-pushed, running patch
   sources remounted, playing clips restarted (from the top), a running
   click resumed, armed timed transitions continuing their count, the
   control plane and the Python name table rebuilt.

**Why below the controllers, not `stop()` → `start()`.** A full engine
restart rebuilds the engine-side controllers, and the shell holds them from
its own `initState` — `midi.chain` / `midi.editor` and their undo scope, the
clip library, the voice audition, the record arm, every surface. Rebinding
all of those is a change across the whole shell; keeping the controllers and
swapping only the native handles under them is a change inside the engine,
along the teardown / re-sync seams a project open already exercises. The
one shell-side touch is the patcher canvas, now keyed on its editor so a
fresh editor for the same open patch rebuilds it.

A device picked with no rate that cannot run the session's raises its own
notice (`sessionRateUnsupported`: "… cannot run at 48000 Hz — the audio
engine restarted at 44100 Hz"); a performer-picked rate needs none.

**Device loss and recovery** (issue #410). Any moment Phi ends up with *no*
device open — an interface unplugged mid-set, a switch whose target refused
and whose revert found the previous device gone, or a boot on a machine
that came up device-less — it arms a **bounded recovery run**:

- **Trigger.** The telemetry tick (`AudioDeviceCoordinator.observeLiveState`)
  watches for `activeAudioState()` going empty while `current` still names a
  device — the only detection available (§4) — and the failure exits of
  `switchTo` arm it directly. A failed manual pick re-arms with a *fresh*
  budget: a deliberate act deserves another go.
- **Cadence.** Eight attempts at 1 s, 2 s, 4 s, 8 s, 15 s, 30 s, 30 s, 30 s
  — about two minutes. Each attempt refreshes the device list (nothing is
  open, so this reads the machine afresh — §4) and re-opens through the
  gateway: the device the performer asked for first, the platform default
  second.
  Attempts are silent about rate/buffer fallbacks; eight repetitions of a
  warning would bury the one message that matters.
- **Giving up.** When the budget is spent it **stops** and raises a
  `noAudioDevice` notice naming the attempt count and pointing at Settings ›
  Audio. A retry loop nobody can see and nothing can stop is its own bug.
- **What the performer sees.** The status chip reads **RECONNECTING** while
  a run is live and **NO AUDIO** only once it has given up, so NO AUDIO has
  exactly one meaning: recovery is manual now. The DIAGNOSTICS row and the
  pasted report say the same in words — "(retrying — attempt 3 of 8)" or
  "(gave up after 8 attempts — choose one in Settings › Audio)".
- **What it does not do.** Once recovery has settled for the platform
  default, it does not keep watching for the preferred interface to come
  back — a background poll that hot-swaps the output would mean an
  unannounced dropout mid-set. Instead it **says so, once**: settling on
  the default while a named device is still wanted raises a
  `recoveredOnDefault` notice ("Audio came back on the default device —
  "Alpha" is still unavailable…"), so the green chip never hides a set
  finishing on the wrong output (issue #413). The stored preference is
  untouched, so re-picking the device is one click in Settings › Audio.
- **What it now can do** (issue #445). Under libYSE 2.4 a run could only
  re-open devices the engine saw at startup, so a boot with no hardware
  armed nothing and said "restart Phi" (#412). Since every attempt
  refreshes, a boot with no device arms a run like any other loss, and an
  interface first connected after Phi started is picked up by it.
- **Not verified on hardware.** The offline-refresh half is re-measured on
  the real engine (contract test); hot-plugging during a run is modelled
  from the yse 0.2.0 documentation and has not been exercised by hand.

**MIDI.** The chosen output port replaces the hard-coded port 0 in
`EngineMidiController`; stored name resolves to an index each time the
port is (re)opened, so replugging keeps working. Enabled input ports are
opened and their activity shown (a receive indicator), but **nothing is
routed anywhere yet** — consuming MIDI-in belongs to the racks & voices
epic (direction §4.5); this epic only remembers and opens the hardware.

**Cadence.** Autosave-interval changes take effect on the next timer arm
— no restart.

## 6. The settings window

A **modal overlay dialog** inside the main window — not a surface (it is
not a performance tool, it gets no rail button) and not a separate OS
window (that waits for multi-window, direction §4.9). Opened from the
File/app menu and the command palette later.

- Left: section list (AUDIO · MIDI · PROJECTS · DIAGNOSTICS). Right: the
  section's fields. The dialog is large enough to never scroll a section.
- Every control applies immediately (§5); the dialog needs no OK/Cancel —
  just close.
- AUDIO: output device dropdown (grouped by host), sample-rate and
  buffer-size dropdowns (populated from the *selected* device's reported
  lists, "device default" as first entry), speaker-layout dropdown,
  live read-back line (active rate / buffer / latency in ms), and a
  **Rescan devices** button under the device dropdown (§4, issue #450).
- MIDI: output-port dropdown, input-port checklist with per-port activity
  dot.
- PROJECTS: autosave cadence (number field, seconds; 0 disables) and
  recents management — the recent-projects list with per-entry remove,
  clear-all, and pin (pinned entries float to the top of the File menu
  and never age out).
- DIAGNOSTICS: read-only rows — libYSE version (`System.version`),
  resolved `YSE_DLL_PATH`, active device + host, drop counter. Copy
  button for bug reports.
- **Design-system gap:** there is no dropdown/select widget yet.
  `PhiSelect` (and a checklist row) are new `lib/design/widgets/` work,
  built token-first like the existing widgets — they'll be reused by
  every surface after this (transform pickers, voice pickers, …).

## 7. Runtime architecture

- `AudioSettings` / `MidiSettings` value types join `AppSettings` in
  `lib/domain/project/app_settings/` — pure Dart, TDD.
- An `AppSettingsController` (ChangeNotifier) owns the live value: loads
  once at boot, exposes `update(AppSettings)` which saves through the
  store immediately (writes are tiny) and notifies. The lifecycle
  controller (recents) and the settings dialog both go through it — the
  file is never written from two owners.
- `YseGateway` grows the device surface: `audioDevices()` returning
  **pure descriptors** (name, host, rates, buffers — no FFI types above
  the bridge), `openAudioDevice(descriptor?, {rate, buffer, layout})`,
  `activeAudioState()`. `FakeYseGateway` fabricates a device list —
  the whole window is testable without hardware.
- `MidiGateway` already enumerates outputs; it grows input enumeration +
  open/close and an activity callback, same Real/Fake split.
- The engine façade (`PhiEngine`) exposes `requestBootAudio(AudioSettings)`
  + `start()` (boot straight onto the stored device, §5) and
  `switchAudioDevice(AudioSettings)` for live picks. One boot path, not
  two — see the note in §5.

## 8. Out of scope

- **MIDI-in → voice routing** — racks & voices epic; this epic only
  opens ports and shows activity.
- **Surround strategy in the mix** — Mix detail doc; this epic only
  stores and passes the layout enum.
- **Input audio devices** — nothing in Phi records or monitors audio
  input yet (direction §4.10); the `Device` API covers it when that
  lands.
- **Performance mode** (suspending autosave etc.) — deferred as per the
  registry review decisions.
- **Log panel / log file** — diagnostics section shows static facts only;
  the live log is direction §4.11.

## 9. Review decisions (2026-07-18)

1. **MIDI inputs are in v1** — enumerate + persist + activity dot, so
   the racks & voices epic consumes working plumbing.
2. **Recents management ships with the window** — per-entry remove,
   clear-all, and pin (hence `pinnedProjects` in §3).
3. **A failed live device switch reverts to the previous device**, never
   the platform default — the performer's last working state wins.
4. **Rate/buffer dropdowns always show**, "device default" as the first
   option — no override toggle, fewer states.

## 10. Proposed epic breakdown

Roughly seven issues, in dependency order:

1. `AudioSettings` + `MidiSettings` value types, `pinnedProjects`,
   `version` field, tolerant parse + round-trip tests (pure domain, TDD).
2. `AppSettingsController` — single owner of the live settings value;
   fold the lifecycle controller's recents writes through it.
3. Gateway device surface: pure audio-device descriptors +
   `openAudioDevice` + active state on `YseGateway` (Real/Fake); MIDI
   input enumeration/open on `MidiGateway`.
4. Boot-from-settings in `PhiEngine`: stored device → `init` +
   `openDevice` (see the §5 note on why not `initOffline`), fallback +
   notice, auto-reconnect on; keep-preference rule tested.
5. Design system: `PhiSelect` dropdown + checklist row, token-first.
6. Settings dialog shell + AUDIO section (device/rate/buffer/layout,
   live read-back, immediate apply).
7. MIDI + PROJECTS (cadence + recents remove/clear/pin) + DIAGNOSTICS
   sections; replace the hard-coded MIDI output port 0 with the stored
   choice.
