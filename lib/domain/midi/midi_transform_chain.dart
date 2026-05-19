import 'package:flutter/foundation.dart';

import 'midi_clip.dart';
import 'midi_note.dart';
import 'midi_transform.dart';

/// Ordered pipeline of [MidiTransform]s applied to a source [MidiClip].
///
/// Mutates in place via [add] / [removeAt] / [replaceAt] / [reorder] /
/// [setActiveAt]; each mutation notifies listeners and bumps [version] so
/// painters that key on a counter (instead of list equality) repaint.
///
/// Inactive transforms are **skipped**, not called with a no-op `apply`.
/// That keeps the "does this transform contribute?" question a single
/// boolean read rather than an `apply` call returning unchanged input.
class MidiTransformChain extends ChangeNotifier {
  MidiTransformChain({
    required MidiClip source,
    List<MidiTransform> transforms = const [],
  }) : _source = source,
       _transforms = List<MidiTransform>.of(transforms);

  final MidiClip _source;
  final List<MidiTransform> _transforms;
  int _version = 0;

  MidiClip get source => _source;

  List<MidiTransform> get transforms => List.unmodifiable(_transforms);

  /// Monotonic counter that increases on every mutating call. Painters can
  /// pass it to `shouldRepaint` instead of diffing the note list.
  int get version => _version;

  /// Notes after every active transform has been applied in list order.
  /// Recomputed on every call — caching would invalidate on the same
  /// signal that bumps [version], so it isn't worth the bookkeeping yet.
  List<MidiNote> get output {
    var notes = List<MidiNote>.of(_source.notes);
    for (final t in _transforms) {
      if (!t.active) continue;
      notes = t.apply(notes);
    }
    return notes;
  }

  void add(MidiTransform t) {
    _transforms.add(t);
    _bump();
  }

  void removeAt(int index) {
    _transforms.removeAt(index);
    _bump();
  }

  void replaceAt(int index, MidiTransform t) {
    _transforms[index] = t;
    _bump();
  }

  void reorder(int from, int to) {
    if (from == to) return;
    final t = _transforms.removeAt(from);
    final target = to > from ? to - 1 : to;
    _transforms.insert(target, t);
    _bump();
  }

  void setActiveAt(int index, bool active) {
    final current = _transforms[index];
    if (current.active == active) return;
    _transforms[index] = current.copyWith(active: active);
    _bump();
  }

  void _bump() {
    _version++;
    notifyListeners();
  }
}
