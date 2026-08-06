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
  sizes, default buffer size, latencies. **Only `init()` enumerates** —
  the engine builds the list while opening a device and never on its own,
  so `System.devices` is empty for the whole of an `initOffline()` session
  (measured against libyse 2.4.0: 0 devices offline, 19 after `init()` —
  issue #403, dart-yse #51).
- **Open/close:** `System.initOffline()` boots the engine with *no*
  device — and, per the point above, no device *list* either, so it is a
  headless-rendering path, not a boot path; `openDevice(DeviceSetup,
  layout:)` opens a chosen one; `closeCurrentDevice()` + `openDevice`
  swaps live — no engine restart. `System.defaultDevice` names the
  platform default.
- **Two engine limits to design around** (both measured, both filed):
  a refused `openDevice` is reported as a log line, not a status, so the
  bridge confirms an open by reading back the live state (dart-yse #52);
  and the session sample rate is locked at `init()`, so a stored rate
  override cannot reach the device (dart-yse #53).
- **Live state:** `activeSampleRate`, `activeBufferSize`, output latency
  in samples — the diagnostics section reads these, not the stored
  settings (they can legitimately differ).
- **Resilience:** `setAutoReconnect(on:, delayMs:)` is **off**, and Phi
  supervises recovery itself (issue #410). This entry used to read "the
  engine re-opens a device that disappears. Enabled always (1 s delay)".
  Measured against the engine sources, it does something else:
  `system::update()` counts control ticks with no audio callback and, past
  the threshold, runs `pause()` + `resume()` — which is
  `managerObject::close()` followed by `addCallback()`, and `addCallback()`
  hardcodes `Pa_GetDefaultOutputDevice()`. So it reopens the *platform
  default*, not the device that was lost, dropping the chosen buffer size
  and channel count; the counter is reset only by a callback that arrives,
  never by an attempt, so once armed it retries on **every 16 ms tick with
  no backoff, indefinitely**; and `delayMs` is compared against a tick
  count, making the specified 1 s really ~16 s. A silent migration onto the
  built-in output is exactly the lie #408 closed, so it stays off
  (dart-yse #54).
- **No device-change signal at all.** There is no add/remove event on any
  desktop backend (`serviceReconnect()` is a no-op outside Oboe), and
  `System.devices` is a cache filled inside `init()` — `closeCurrentDevice()`
  leaves it untouched, and since `Pa_Terminate()` is never called before
  process exit even `close()` + `init()` re-reads PortAudio's original
  snapshot. Recovery therefore **polls**: `activeSampleRate == 0` is the
  engine's documented "nothing is open" sentinel, read on Phi's telemetry
  tick. (One consequence for the dropdown: a device removed or added
  mid-session is invisible to enumeration — issue #412, dart-yse #51.)
- **Recovery is cheap, re-init is not.** `closeCurrentDevice()` tears down
  only the stream — PortAudio stays initialised, and every channel, sound
  and clock survives — so `openDevice` right afterwards is the designed
  flow and the one recovery libyse genuinely supports from a closed engine.
  `System.close()` is a different animal (it joins the worker pools and
  destroys every channel), so recovery never goes near it.
- **MIDI:** input/output device counts + names by index
  (`midiInDeviceName` / `midiOutDeviceName`); `MidiIn.open` /
  `MidiOut.open` take the index — Phi resolves stored *names* to current
  indices at open time.

## 5. Apply semantics

**Boot.** Two steps, in this order, because the engine gives no other:

1. `PhiEngine.start()` → `init()`, which opens the platform default and is
   the *only* call that enumerates hardware (§4). Engine auto-reconnect
   off; Phi's own recovery supervisor takes over (below).
2. Once the settings store has loaded, the shell
   (`Workstation._startProject`) applies `audio` as a **live switch** —
   `switchAudioDevice(stored)`, resolving host+name against `devices` and
   opening it with overrides and layout. A no-op when no device is stored.

If the stored device is **missing or fails to open**, the app stays on the
default opened in step 1, shows a non-blocking notice, and **keeps the
stored preference intact** — a performer whose interface wasn't plugged in
yet must not lose their configuration to a helpful fallback.

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
> entry point.

**Live change.** Picking a device / rate / buffer in the window applies
immediately (`closeCurrentDevice` + `openDevice`) through that same
`switchAudioDevice`. A brief audio dropout during the swap is accepted;
selecting a device in a dropdown *is* the deliberate act, no separate Apply
button. Failure reverts to the previous working device, raises a notice,
and updates the stored choice only on success.

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
  — about two minutes. Each attempt re-opens through the gateway: the
  device the performer asked for first, the platform default second.
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
  back; the stored preference is untouched, so re-picking it is one click
  (issue #413).

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
  live read-back line (active rate / buffer / latency in ms).
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
- The engine façade (`PhiEngine`) exposes `start()` (default device up) and
  `switchAudioDevice(AudioSettings)`; the shell applies the stored choice
  through the latter once settings have loaded (§5). One device path, not
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
