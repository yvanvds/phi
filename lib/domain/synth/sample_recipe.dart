/// A single-sample sampler recipe — the "one sample, no `.sfz`" path of a
/// [SamplerSynth] (design `docs/design/racks-and-voices.md` §4, mirroring the
/// engine's `SfzInstrument.fromSample`).
///
/// Wraps one audio [file] (a project-relative asset path, per §4) in a one-region
/// instrument: [root] is the key that plays it untransposed, [low]/[high] bound
/// the playable range, and [attack]/[release] are the amplitude envelope times in
/// seconds. A plain, immutable value type that (de)serialises to a JSON map.
class SampleRecipe {
  /// Builds a recipe around [file]. Defaults span the full keyboard rooted at
  /// middle C with an instant attack and a short release.
  const SampleRecipe({
    required this.file,
    this.root = 60,
    this.low = 0,
    this.high = 127,
    this.attack = 0.0,
    this.release = 0.1,
  });

  /// Reads a recipe from a decoded map, defaulting any missing key. Throws a
  /// [FormatException] if `file` is absent — a sample recipe with no file is
  /// meaningless.
  factory SampleRecipe.fromJson(Map<String, Object?> json) {
    final file = json['file'] as String?;
    if (file == null) {
      throw const FormatException('A sample recipe needs a "file" path.');
    }
    return SampleRecipe(
      file: file,
      root: (json['root'] as num?)?.toInt() ?? 60,
      low: (json['low'] as num?)?.toInt() ?? 0,
      high: (json['high'] as num?)?.toInt() ?? 127,
      attack: (json['attack'] as num?)?.toDouble() ?? 0.0,
      release: (json['release'] as num?)?.toDouble() ?? 0.1,
    );
  }

  /// The sample's project-relative asset path.
  final String file;

  /// The MIDI note that plays the sample untransposed, in `[0, 127]`.
  final int root;

  /// The lowest playable MIDI note, in `[0, 127]`.
  final int low;

  /// The highest playable MIDI note, in `[0, 127]`.
  final int high;

  /// Amplitude attack time in seconds.
  final double attack;

  /// Amplitude release time in seconds.
  final double release;

  SampleRecipe copyWith({
    String? file,
    int? root,
    int? low,
    int? high,
    double? attack,
    double? release,
  }) => SampleRecipe(
    file: file ?? this.file,
    root: root ?? this.root,
    low: low ?? this.low,
    high: high ?? this.high,
    attack: attack ?? this.attack,
    release: release ?? this.release,
  );

  /// The recipe as its JSON map, keys in a stable order.
  Map<String, Object?> toJson() => {
    'file': file,
    'root': root,
    'low': low,
    'high': high,
    'attack': attack,
    'release': release,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SampleRecipe &&
          other.file == file &&
          other.root == root &&
          other.low == low &&
          other.high == high &&
          other.attack == attack &&
          other.release == release;

  @override
  int get hashCode => Object.hash(file, root, low, high, attack, release);

  @override
  String toString() =>
      'SampleRecipe(file: $file, root: $root, low: $low, high: $high, '
      'attack: $attack, release: $release)';
}
