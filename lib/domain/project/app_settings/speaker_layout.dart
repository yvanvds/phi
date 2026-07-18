/// The speaker layout an audio device is opened with (design
/// `docs/design/settings-and-devices.md` §3).
///
/// A domain-owned mirror of yse's `ChannelType`: the domain layer stays pure
/// Dart (it must never import `package:yse`), so the setting is stored as one of
/// these cases and mapped to the engine's `ChannelType` at `openDevice` time in
/// the engine layer (out of scope for the schema issue). Each case carries the
/// stable [wireName] written to `settings.json` — chosen to read naturally in a
/// hand-edited file (`5.1`, `7.1`) rather than the Dart identifier.
enum SpeakerLayout {
  /// Let the engine pick — stereo when the device allows it. The default.
  auto('auto'),

  /// A single output channel.
  mono('mono'),

  /// Two channels, left/right.
  stereo('stereo'),

  /// Four channels.
  quad('quad'),

  /// 5.1 surround.
  surround51('5.1'),

  /// 5.1-side variant.
  surround51Side('5.1side'),

  /// 6.1 surround.
  surround61('6.1'),

  /// 7.1 surround.
  surround71('7.1');

  const SpeakerLayout(this.wireName);

  /// The token persisted to `settings.json` for this layout.
  final String wireName;

  /// The layout a fresh install uses (design §3 — `auto`).
  static const SpeakerLayout defaultLayout = auto;

  /// Resolves a stored [wireName] back to a layout, tolerating a missing or
  /// unknown token (an older or hand-edited file) by falling back to
  /// [defaultLayout].
  static SpeakerLayout fromWire(Object? wireName) {
    for (final layout in values) {
      if (layout.wireName == wireName) return layout;
    }
    return defaultLayout;
  }
}
