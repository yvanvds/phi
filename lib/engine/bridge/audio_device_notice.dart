/// A non-blocking notice raised while applying an audio-device choice — the
/// stored one at launch, or a live change from the settings window, which since
/// issue #405 are the same code path (design
/// `docs/design/settings-and-devices.md` §5, §9.3).
///
/// The switch logic never blocks and never rewrites the stored
/// preference: when a chosen device is missing, refuses to open, or reports a
/// sample rate / buffer the stored value no longer matches, it falls back (to the
/// default device, or the device's own default rate / buffer) and raises one of
/// these so the shell can surface a passing message. A pure value type — no FFI,
/// no Flutter — carried out of `lib/engine/bridge/` to whichever surface shows it
/// (bottom status today, the settings dialog later).
class AudioDeviceNotice {
  /// Builds a notice of [kind] with a human-readable [message] safe to show.
  const AudioDeviceNotice(this.kind, this.message);

  /// What happened — lets a consumer branch on the cause without parsing
  /// [message].
  final AudioNoticeKind kind;

  /// A short, human-readable description of the fallback that was applied.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is AudioDeviceNotice &&
      other.kind == kind &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'AudioDeviceNotice(${kind.name}: $message)';
}

/// The cause behind an [AudioDeviceNotice] (design §5, §9.3).
enum AudioNoticeKind {
  /// The stored sample-rate override is not among the device's reported rates —
  /// the device's own default rate was used instead.
  unsupportedSampleRate,

  /// The stored buffer-size override is not among the device's reported buffers —
  /// the device's own default buffer was used instead.
  unsupportedBufferSize,

  /// A device switch failed (target missing or refused) — the previous working
  /// device was kept / restored and the stored choice left unchanged. Covers the
  /// launch-time apply of the stored preference too, since that runs through the
  /// same switch (issue #405): a device that isn't plugged in leaves the app on
  /// the platform default `init()` opened, with the preference intact.
  switchReverted,

  /// No audio device could be opened at all, not even the platform default — the
  /// engine is running without audio output.
  noAudioDevice,

  /// A recovery run brought audio back on the **platform default** while the
  /// device the performer chose is still missing (issue #413). Raised exactly
  /// once, when the run settles: recovery stands down at that point and nothing
  /// keeps watching for the preferred interface (design §5), so without this
  /// notice the chip would simply go green and a set could finish on the
  /// built-in speakers with nobody told. The stored preference is untouched —
  /// re-picking the device in Settings › Audio once it returns is the way back.
  recoveredOnDefault,
}
