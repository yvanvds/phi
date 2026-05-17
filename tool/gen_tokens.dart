/// Generate the Dart design-token files from `design system/colors_and_type.css`.
///
/// The CSS is the source of truth. This script parses the `:root` variables
/// and the `.phi-*` class declarations, then rewrites the marked region in
/// each of the five token files under `lib/design/tokens/`.
///
/// Run without flags to regenerate. Run with `--check` for CI / pre-commit:
/// the script exits non-zero if any token file would change.
library;

import 'dart:io';

const _cssPath = 'design system/colors_and_type.css';

const _regionStart = '// region: generated-from-css';
const _regionEnd = '// endregion: generated-from-css';

const _checkFlag = '--check';

const _generatedHeader = [
  'Auto-generated from `design system/colors_and_type.css`.',
  'Run `dart run tool/gen_tokens.dart` to refresh; `--check` to verify drift.',
];

void main(List<String> args) {
  final check = args.contains(_checkFlag);

  final cssFile = File(_cssPath);
  if (!cssFile.existsSync()) {
    stderr.writeln('error: $_cssPath not found (run from repo root)');
    exit(2);
  }
  final css = cssFile.readAsStringSync();
  final root = _parseRoot(css);
  final classes = _parseClasses(css);

  final updates = <String, String>{
    'lib/design/tokens/phi_colors.dart': _emitColors(root),
    'lib/design/tokens/phi_spacing.dart': _emitSpacing(root),
    'lib/design/tokens/phi_motion.dart': _emitMotion(root),
    'lib/design/tokens/phi_radii.dart': _emitRadii(root),
    'lib/design/tokens/phi_type.dart': _emitType(root, classes),
  };

  var drift = 0;
  for (final entry in updates.entries) {
    final path = entry.key;
    final region = entry.value;
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('error: $path not found');
      exit(2);
    }
    final current = file.readAsStringSync();
    final updated = _replaceRegion(current, region, path);
    final formatted = _dartFormat(updated, path);

    if (formatted == current) continue;
    drift++;
    if (check) {
      stderr.writeln('drift: $path');
    } else {
      file.writeAsStringSync(formatted);
      stdout.writeln('updated: $path');
    }
  }

  if (check) {
    if (drift > 0) {
      stderr.writeln(
        '\n$drift file(s) need regeneration. '
        'Run: dart run tool/gen_tokens.dart',
      );
      exit(1);
    }
    stdout.writeln('tokens in sync with CSS.');
    return;
  }
  if (drift == 0) {
    stdout.writeln('no changes — tokens already match CSS.');
  }
}

// ─── parsing ─────────────────────────────────────────────────────────────────

Map<String, String> _parseRoot(String css) {
  final rootMatch = RegExp(r':root\s*\{([\s\S]*?)\n\}').firstMatch(css);
  if (rootMatch == null) throw StateError('no :root in CSS');
  final body = _stripComments(rootMatch.group(1)!);
  final vars = <String, String>{};
  final varRe = RegExp(r'--([\w-]+)\s*:\s*([^;]+);');
  for (final m in varRe.allMatches(body)) {
    vars[m.group(1)!] = m.group(2)!.trim();
  }
  return vars;
}

Map<String, Map<String, String>> _parseClasses(String css) {
  final stripped = _stripComments(css);
  final out = <String, Map<String, String>>{};
  final classRe = RegExp(r'\.phi-([\w-]+)\s*\{([^}]*)\}');
  for (final m in classRe.allMatches(stripped)) {
    final name = m.group(1)!;
    final body = m.group(2)!;
    final props = <String, String>{};
    final propRe = RegExp(r'([\w-]+)\s*:\s*([^;]+);');
    for (final p in propRe.allMatches(body)) {
      props[p.group(1)!] = p.group(2)!.trim();
    }
    out[name] = props;
  }
  return out;
}

String _stripComments(String s) => s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

// ─── dart format wrapper ────────────────────────────────────────────────────

/// Pipe [content] through `dart format` so the regenerated region matches the
/// canonical style of files developers commit. The temp file lives next to
/// the target so the formatter resolves the same package config.
String _dartFormat(String content, String nearPath) {
  final tempPath = '$nearPath.gen.tmp';
  final temp = File(tempPath);
  try {
    temp.writeAsStringSync(content);
    final result = Process.runSync('dart', [
      'format',
      '--output=write',
      tempPath,
    ], runInShell: true);
    if (result.exitCode != 0) {
      stderr.writeln('dart format failed for $nearPath:\n${result.stderr}');
      exit(2);
    }
    return temp.readAsStringSync();
  } finally {
    if (temp.existsSync()) temp.deleteSync();
  }
}

// ─── region replacement ─────────────────────────────────────────────────────

String _replaceRegion(String current, String body, String path) {
  final startRe = RegExp(
    r'^([ \t]*)' + RegExp.escape(_regionStart) + r'.*\r?\n',
    multiLine: true,
  );
  final start = startRe.firstMatch(current);
  if (start == null) {
    throw StateError('no `$_regionStart` marker in $path');
  }
  final indent = start.group(1)!;
  final tail = current.substring(start.end);
  final endRe = RegExp(
    r'^[ \t]*' + RegExp.escape(_regionEnd) + r'.*\r?\n',
    multiLine: true,
  );
  final end = endRe.firstMatch(tail);
  if (end == null) {
    throw StateError('no `$_regionEnd` marker in $path');
  }
  final after = tail.substring(end.end);

  final indented = body
      .split('\n')
      .map((l) => l.isEmpty ? '' : '$indent$l')
      .join('\n');
  return '${current.substring(0, start.end)}'
      '$indented\n'
      '$indent$_regionEnd\n'
      '$after';
}

// ─── colors ─────────────────────────────────────────────────────────────────

String _emitColors(Map<String, String> root) {
  final b = _Buf()..header(_generatedHeader);
  b.section('Substrate');
  b.line('static const Color voidField = ${_cssHex(root["void"]!)};');
  for (var i = 0; i <= 4; i++) {
    b.line('static const Color bg$i = ${_cssHex(root["bg-$i"]!)};');
  }
  b.section('Foreground');
  for (var i = 0; i <= 4; i++) {
    b.line('static const Color fg$i = ${_cssHex(root["fg-$i"]!)};');
  }
  b.section('Borders (rgba on white)');
  for (var i = 0; i <= 2; i++) {
    b.line('static const Color line$i = ${_cssRgba(root["line-$i"]!)};');
  }
  b.line('static const Color lineHot = ${_cssRgba(root["line-hot"]!)};');
  b.section('Voices');
  for (var i = 1; i <= 6; i++) {
    b.line('static const Color voice$i = ${_cssHex(root["voice-$i"]!)};');
  }
  b.section('Voice glow shells');
  for (var i = 1; i <= 6; i++) {
    b.line(
      'static const Color voice${i}Soft = ${_cssRgba(root["voice-$i-soft"]!)};',
    );
  }
  b.section('Semantic');
  for (final name in ['hot', 'warm', 'cool', 'live']) {
    b.line('static const Color $name = ${_cssHex(root[name]!)};');
  }
  b.section('Grid');
  b.line('static const Color grid = ${_cssRgba(root["grid-color"]!)};');
  b.line('static const Color gridStrong = ${_cssRgba(root["grid-strong"]!)};');
  return b.toString();
}

String _cssHex(String css) {
  final hex = css.replaceFirst('#', '').toUpperCase();
  if (hex.length != 6) throw StateError('expected #rrggbb, got: $css');
  return 'Color(0xFF$hex)';
}

String _cssRgba(String css) {
  final m = RegExp(
    r'rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)',
  ).firstMatch(css);
  if (m == null) throw StateError('expected rgba(): $css');
  final r = int.parse(m.group(1)!);
  final g = int.parse(m.group(2)!);
  final bl = int.parse(m.group(3)!);
  final a = double.parse(m.group(4)!);
  final ai = (a * 255).round();
  String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  return 'Color(0x${h(ai)}${h(r)}${h(g)}${h(bl)})';
}

// ─── spacing ────────────────────────────────────────────────────────────────

String _emitSpacing(Map<String, String> root) {
  final b = _Buf()
    ..header(_generatedHeader)
    ..line();
  for (var i = 0; i <= 9; i++) {
    b.line('static const double s$i = ${_pxNum(root["s-$i"]!)};');
  }
  b.line()
    ..line(
      '/// 16px backdrop grid cell, used in 3D viewport / patcher / state graph.',
    )
    ..line('static const double gridCell = ${_pxNum(root["grid-cell"]!)};');
  return b.toString();
}

String _pxNum(String css) {
  final m = RegExp(r'^(-?[\d.]+)(?:px)?$').firstMatch(css.trim());
  if (m == null) throw StateError('expected Npx: $css');
  return m.group(1)!;
}

// ─── motion ─────────────────────────────────────────────────────────────────

String _emitMotion(Map<String, String> root) {
  final b = _Buf()
    ..header(_generatedHeader)
    ..line();
  const eases = [
    ('easeOut', 'ease-out'),
    ('easeIn', 'ease-in'),
    ('easeInOut', 'ease-inout'),
  ];
  for (final (dart, css) in eases) {
    b.line('static const Cubic $dart = Cubic(${_cubic(root[css]!)});');
  }
  b.line();
  for (var i = 1; i <= 4; i++) {
    b.line(
      'static const Duration dur$i = '
      'Duration(milliseconds: ${_ms(root["dur-$i"]!)});',
    );
  }
  return b.toString();
}

String _cubic(String css) {
  final m = RegExp(
    r'cubic-bezier\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)',
  ).firstMatch(css);
  if (m == null) throw StateError('expected cubic-bezier(): $css');
  return [1, 2, 3, 4].map((i) => _ensureDecimal(m.group(i)!)).join(', ');
}

String _ensureDecimal(String s) => s.contains('.') ? s : '$s.0';

int _ms(String css) {
  final m = RegExp(r'^(\d+)ms$').firstMatch(css.trim());
  if (m == null) throw StateError('expected Xms: $css');
  return int.parse(m.group(1)!);
}

// ─── radii ──────────────────────────────────────────────────────────────────

String _emitRadii(Map<String, String> root) {
  final b = _Buf()
    ..header(_generatedHeader)
    ..line();
  for (var i = 0; i <= 3; i++) {
    final v = _pxNum(root['r-$i']!);
    final rhs = v == '0' ? 'Radius.zero' : 'Radius.circular($v)';
    b.line('static const Radius r$i = $rhs;');
  }
  b.line(
    'static const Radius rPill = Radius.circular(${_pxNum(root["r-pill"]!)});',
  );
  return b.toString();
}

// ─── type ───────────────────────────────────────────────────────────────────
//
// Each `.phi-*` class becomes a TextStyle factory. The classes drive
// font family (which selects a private `_glitch / _sans / _mono` helper kept
// outside the generated region), font weight, size, line-height, letter
// spacing, color, and optional text-shadow.
//
// Line-height is read from the `--lh-*` :root variables when the class uses
// `var(--lh-*)` — that's the agreed source of truth (see issue #2).
//
// `.phi-glitch` and `.phi-code` exist in the CSS but have no Dart counterpart;
// the allowlist below names every factory the generator should emit.

const _typeFactories = [
  ('displayXl', 'display-xl'),
  ('displayL', 'display-l'),
  ('displayM', 'display-m'),
  ('h1', 'h1'),
  ('h2', 'h2'),
  ('h3', 'h3'),
  ('body', 'body'),
  ('small', 'small'),
  ('caption', 'caption'),
  ('mono', 'mono'),
  ('monoL', 'mono-l'),
  ('monoS', 'mono-s'),
  ('readout', 'readout'),
];

/// Doc strings the generator should emit above the matching factory. Kept
/// here (not in CSS) because they describe Dart usage, not type metrics.
const _typeFactoryDocs = <String, List<String>>{
  'caption': [
    '/// Section headers, panel titles. Mono, uppercase, widened tracking.',
  ],
  'readout': [
    '/// Glowing fuchsia readouts for live values. Apply the glow as a',
    '/// `Shadow` in `Text` widgets — this style only provides the colour.',
  ],
};

String _emitType(
  Map<String, String> root,
  Map<String, Map<String, String>> classes,
) {
  final b = _Buf()
    ..header(_generatedHeader)
    ..line();

  // Tracking constants, in fixed order.
  final tracking = {
    'tight': root['tracking-tight'],
    'wide': root['tracking-wide'],
    'mono': root['tracking-mono'],
  };
  final used = <String>{};
  for (final (_, cls) in _typeFactories) {
    final ls = classes[cls]?['letter-spacing'];
    if (ls == null) continue;
    final m = RegExp(r'var\(--tracking-(\w+)\)').firstMatch(ls);
    if (m != null) used.add(m.group(1)!);
  }
  for (final entry in tracking.entries) {
    if (!used.contains(entry.key)) continue;
    final v = _emValue(entry.value!);
    b.line('static const double _tracking${_cap(entry.key)} = $v;');
  }
  b.line();

  for (final (dart, cls) in _typeFactories) {
    final props = classes[cls];
    if (props == null) throw StateError('CSS missing class .phi-$cls');
    b.lines(_typeFactory(dart, props, root));
    b.line();
  }
  return b.toString().trimRight();
}

List<String> _typeFactory(
  String name,
  Map<String, String> props,
  Map<String, String> root,
) {
  final family =
      props['font-family'] ?? (throw StateError('$name: no font-family'));
  final helper = switch (family) {
    'var(--font-glitch)' => '_glitch',
    'var(--font-display)' || 'var(--font-ui)' => '_sans',
    'var(--font-mono)' => '_mono',
    _ => throw StateError('$name: unknown font-family $family'),
  };

  final args = <String>[];
  // size
  final size = _resolveSize(props['font-size'], root);
  args.add('size: $size');
  // height
  final height = _resolveHeight(props, root, helper);
  if (height != null) args.add('height: $height');
  // weight
  final weight = _resolveWeight(props['font-weight'], helper);
  if (weight != null) args.add('weight: $weight');
  // color
  final color = _resolveColor(props['color'], helper);
  if (color != null) args.add('color: $color');
  // tracking
  final tracking = _resolveTracking(props['letter-spacing'], helper);
  if (tracking != null) args.add('trackingEm: $tracking');

  final body = '$helper(${args.join(', ')})';

  // Optional text-shadow → `.copyWith(shadows: ...)`.
  final shadow = props['text-shadow'];
  final core = shadow == null
      ? ['static TextStyle $name() => $body;']
      : [
          'static TextStyle $name() => $body',
          '    .copyWith(',
          '      shadows: const [${_shadow(shadow)}],',
          '    );',
        ];
  final doc = _typeFactoryDocs[name];
  return doc == null ? core : [...doc, ...core];
}

String _resolveSize(String? css, Map<String, String> root) {
  if (css == null) throw StateError('no font-size');
  final m = RegExp(r'var\(--(t-[\w-]+)\)').firstMatch(css);
  if (m != null) return _pxNum(root[m.group(1)!]!);
  return _pxNum(css);
}

String? _resolveHeight(
  Map<String, String> props,
  Map<String, String> root,
  String helper,
) {
  final css = props['line-height'];
  if (css == null) {
    // `_glitch` requires height; fall back to 1.0 (won't happen for current
    // CSS — both glitch classes set line-height — but keep the check honest).
    return helper == '_glitch' ? '1.0' : null;
  }
  // var(--lh-*) → look up.
  final m = RegExp(r'var\(--(lh-[\w-]+)\)').firstMatch(css);
  final raw = m != null ? root[m.group(1)!]! : css;
  return _ensureDecimal(raw.trim());
}

String? _resolveWeight(String? css, String helper) {
  if (css == null) return null;
  final n = int.tryParse(css.trim());
  if (n == null) throw StateError('non-numeric font-weight: $css');
  // Each helper's default. _glitch has no weight arg; _sans/_mono default 400.
  if (helper == '_glitch') return null;
  if (n == 400) return null;
  return 'FontWeight.w$n';
}

String? _resolveColor(String? css, String helper) {
  if (css == null) return null;
  final m = RegExp(r'var\(--([\w-]+)\)').firstMatch(css);
  if (m == null) throw StateError('non-var color: $css');
  final name = m.group(1)!;
  final dart = _colorVarToDart(name);
  // Suppress when matching helper default.
  if (helper == '_glitch' && dart == 'PhiColors.fg0') return null;
  if (helper == '_sans' && dart == 'PhiColors.fg0') return null;
  if (helper == '_mono' && dart == 'PhiColors.fg1') return null;
  return dart;
}

String _colorVarToDart(String cssVar) {
  // --fg-0 → PhiColors.fg0, --voice-1 → PhiColors.voice1, --fg-1 → fg1, etc.
  // Handle special cases first.
  if (cssVar == 'void') return 'PhiColors.voidField';
  if (cssVar == 'grid-color') return 'PhiColors.grid';
  // Generic: kebab → camel, digits attach to previous segment.
  final parts = cssVar.split('-');
  final buf = StringBuffer(parts.first);
  for (var i = 1; i < parts.length; i++) {
    final p = parts[i];
    if (RegExp(r'^\d+$').hasMatch(p)) {
      buf.write(p);
    } else {
      buf.write(p[0].toUpperCase() + p.substring(1));
    }
  }
  return 'PhiColors.${buf.toString()}';
}

String? _resolveTracking(String? css, String helper) {
  if (css == null) return null;
  final v = css.trim();
  // Var reference → use the `_trackingX` constant.
  final m = RegExp(r'var\(--tracking-(\w+)\)').firstMatch(v);
  if (m != null) {
    final name = m.group(1)!;
    if (name == 'normal') return null; // default
    if (helper == '_mono' && name == 'mono') return null; // default
    return '_tracking${_cap(name)}';
  }
  // Literal `0` → suppress (default for _sans / _glitch is 0).
  if (v == '0' || v == '0em') {
    return helper == '_mono' ? '0' : null;
  }
  // Literal `Xem` → numeric.
  final em = _emValue(v);
  if (helper == '_glitch' && em == '0.01') return null; // _glitch default
  return em;
}

String _emValue(String css) {
  final m = RegExp(r'^(-?[\d.]+)em$').firstMatch(css.trim());
  if (m == null) throw StateError('expected Nem: $css');
  return m.group(1)!;
}

String _shadow(String css) {
  // `0 0 8px var(--voice-1-soft)` → `Shadow(color: PhiColors.voice1Soft, blurRadius: 8)`
  final m = RegExp(
    r'(\d+)\s+(\d+)\s+(\d+)px\s+var\(--([\w-]+)\)',
  ).firstMatch(css.trim());
  if (m == null) throw StateError('unsupported text-shadow: $css');
  final blur = m.group(3)!;
  final color = _colorVarToDart(m.group(4)!);
  return 'Shadow(color: $color, blurRadius: $blur)';
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

// ─── tiny string builder ────────────────────────────────────────────────────

class _Buf {
  final _b = StringBuffer();
  bool _first = true;

  _Buf line([String s = '']) {
    if (!_first) _b.write('\n');
    _b.write(s);
    _first = false;
    return this;
  }

  _Buf lines(Iterable<String> ls) {
    for (final l in ls) {
      line(l);
    }
    return this;
  }

  _Buf header(List<String> notes) {
    for (final n in notes) {
      line('// $n');
    }
    return this;
  }

  /// Blank line + a heading rule, matching the existing hand-written style.
  ///
  /// Visual width is 74 chars (region content) so that the replacer's 2-space
  /// indent brings each rule to the 76-char convention used elsewhere.
  _Buf section(String label) {
    line();
    final rule = '─' * (67 - label.length);
    line('// ── $label $rule');
    return this;
  }

  @override
  String toString() => _b.toString();
}
