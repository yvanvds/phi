# Getting started

## Install and run

Phi runs on Windows and Linux (x64). There are no prebuilt downloads yet, so
you build it from source with [Flutter](https://docs.flutter.dev/get-started/install)
3.47.1 or later:

```powershell
git clone https://github.com/yvanvds/phi
cd phi
flutter pub get
flutter run -d windows   # or: flutter run -d linux
```

The audio engine (libYSE) needs no setup. The first build downloads it and
places it next to the app.

On Linux, also install Flutter's desktop toolchain (clang, cmake, ninja,
pkg-config, GTK 3 headers) and the libraries the engine uses at runtime:
libsndfile, PortAudio, RtMidi and JACK. On Fedora those are `libsndfile
portaudio rtmidi pipewire-jack-audio-connection-kit-libs`. On Ubuntu they are
`libsndfile1 libportaudio2 librtmidi6 libjack-jackd2-0`.

The root [README](../../README.md) has the developer details, such as running
against a local engine build with `YSE_DLL_PATH`.

### Where Phi keeps its files

- **Settings** (`settings.json`): `%APPDATA%\phi\` on Windows,
  `~/.config/phi/` on Linux (or `$XDG_CONFIG_HOME/phi/`).
- **Session logs**: under `%APPDATA%\phi\` on Windows, `~/.local/state/phi/logs/`
  on Linux (or `$XDG_STATE_HOME/phi/logs/`).
- **Projects** live wherever you save them (see below).

## First launch

Phi reopens the project you last worked on. On the very first launch there is
none, so you start with a fresh, unsaved project. It opens with the Mix
surface in a single pane. The [workstation page](workstation.md) explains the
window around it.

The engine starts on your system's default audio output. Audio health shows
in the bottom status bar. The `AUDIO` chip means a device is open.

## Audio setup

Open **Settings** from the project menu (click the project name at the left
of the top toolbar, then `Settings…`) or from the command palette
(`Ctrl+Shift+P`, type `settings`). Clicking the audio chip in the status bar
opens Settings directly on the AUDIO section.

Settings has four sections on the left: AUDIO, MIDI, PROJECTS and
DIAGNOSTICS. There is no OK or Cancel button. Every change applies at once and
is remembered for the next launch.

**AUDIO**

- **Output device**: the devices the engine found, grouped by audio host.
- **Sample rate** and **buffer size**: the values the selected device reports,
  with "device default" first.
- **Speaker layout**.
- A read-back of the rate, buffer and latency that are actually running.

If a device fails to open, Phi switches back to the one that was working, and
the picker shows that one again.

If the device disappears while you play (unplugged, driver reset), the status
chip turns amber and reads `RECONNECTING`. For about two minutes Phi keeps
trying your chosen device, then the system default. It turns red and reads
`NO AUDIO` only once it has given up. Then open Settings and pick a device.
The device list is a snapshot from when the engine last scanned. A device you
plug in while Phi is running does not appear in it until a reconnect attempt
has rescanned.

**MIDI**: choose the MIDI output port, and tick the input ports to listen to.
A dot beside each input port flashes on incoming MIDI.

**PROJECTS**: the autosave interval (`0` turns autosave off), and the recent
projects list. You can remove one entry, clear all of them, or pin a project
so it stays at the top of the menu.

**DIAGNOSTICS**: the engine version and library path, the active device and
host, and the audio-stall count. A copy button puts all of it on the clipboard,
ready to paste into a bug report.

## Projects

A project is a folder whose name ends in `.phi`. Inside it are a `project.json`
manifest and one small JSON file per item: clips, patches, scripts, voices and
so on. Imported files (samples, SFZ, DX7 banks) go into its `assets/` folder.
Copying or versioning the folder copies the whole project.

The project menu (the project name in the top toolbar) has:

| Item | What it does |
|---|---|
| `New` | Starts a fresh, unsaved project. |
| `Open…` | Picks an existing `.phi` folder. |
| `Open Recent` | Pinned projects first, then the recent ones. |
| `Save` (`Ctrl+S`) | Saves. A project that was never saved asks for a location first. |
| `Duplicate…` | Saves a copy to a new location and continues working in the copy. |
| `Rename…` | Renames the project. |
| `Settings…` | Opens Settings. |
| `Keyboard Shortcuts` (`Ctrl+/`) | Opens the shortcuts overlay. |

The same commands are in the command palette, as `New Project`, `Open Project…`,
`Save Project`, `Duplicate Project…` and `Rename Project…`.

A dot beside the project name means there are unsaved changes. If you switch
projects (New, Open) with unsaved changes, Phi asks before discarding them.
When you close the window with unsaved changes it offers `save`, `discard` or
`keep working`.

**Autosave.** Once a project has been saved somewhere, Phi saves it again
every 60 seconds while it has unsaved changes. Autosave keeps running while
the transport plays. You can change the interval, or turn autosave off, under
Settings › PROJECTS.

**What is saved.** Saving writes your authored content: clips, patches,
scripts, states, rack definitions, the mix and the pane arrangement.
Performance state is not saved. A loaded project starts with the transport
stopped, every patch stopped and every patcher in edit mode.

### Recovery after a crash

Every edit is also written to a journal inside the project folder as you
make it. If Phi closes without saving, the next time the project opens it
offers to recover:

- `replay all`: replays every unsaved edit onto the last save.
- `replay to previous`: replays all but the last edit. Use this when the last
  edit might be what crashed Phi. If an earlier recovery itself did not finish,
  the dialog says so and suggests this option.
- `open last save`: opens the last save without the unsaved edits.
