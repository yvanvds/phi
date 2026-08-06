import 'package:flutter/foundation.dart';

import 'midi_clip.dart';
import 'midi_note.dart';
import 'midi_transform.dart';

/// Ordered pipeline of [MidiTransform]s applied to a source [MidiClip].
///
/// Mutates in place via [add] / [insert] / [removeAt] / [replaceAt] /
/// [reorder] / [setActiveAt]; each mutation notifies listeners and bumps
/// [version] so painters that key on a counter (instead of list equality)
/// repaint.
///
/// Inactive transforms are **skipped**, not called with a no-op `apply`.
/// That keeps the "does this transform contribute?" question a single
/// boolean read rather than an `apply` call returning unchanged input.
class MidiTransformChain extends ChangeNotifier {
  MidiTransformChain({
    required this._source,
    List<MidiTransform> transforms = const [],
  }) : _transforms = List<MidiTransform>.of(transforms);

  final MidiClip _source;
  final List<MidiTransform> _transforms;
  int _version = 0;

  List<MidiNote>? _cache;
  int _cacheVersion = -1;
  int _cacheSourceRevision = -1;
  int _cacheTransformsRevision = -1;

  MidiClip get source => _source;

  List<MidiTransform> get transforms => List.unmodifiable(_transforms);

  /// Monotonic counter that increases on every mutating call. Painters can
  /// pass it to `shouldRepaint` instead of diffing the note list.
  int get version => _version;

  /// Notes after every active transform has been applied in list order.
  ///
  /// The player reads this live each tick (~60×/sec), so it is memoised: the
  /// pipeline only re-evaluates when the transform list changed (tracked by
  /// [version]), the source clip was edited (tracked by [MidiClip.revision]),
  /// or a transform hot-reloaded in place (tracked by [MidiTransform.revision]
  /// — a live-coded [CustomTransform] re-registered under the same name).
  /// Between edits, repeated reads return the same cached list instance — an
  /// O(1) hit, not a fresh recompute. Callers must treat the result as
  /// read-only; mutating it corrupts the cache.
  List<MidiNote> get output {
    final sourceRevision = _source.revision;
    final transformsRevision = _transformsRevision;
    if (_cache != null &&
        _cacheVersion == _version &&
        _cacheSourceRevision == sourceRevision &&
        _cacheTransformsRevision == transformsRevision) {
      return _cache!;
    }
    var notes = List<MidiNote>.of(_source.notes);
    for (final t in _transforms) {
      if (!t.active) continue;
      notes = t.apply(notes);
    }
    _cache = notes;
    _cacheVersion = _version;
    _cacheSourceRevision = sourceRevision;
    _cacheTransformsRevision = transformsRevision;
    return notes;
  }

  /// Sum of the transforms' own revisions — bumps when any chip's behaviour
  /// hot-reloads under a stable list. Cheap (one add per chip); folded into
  /// the [output] cache key. Revisions only ever increment, so any single
  /// hot-reload strictly increases the sum.
  int get _transformsRevision {
    var sum = 0;
    for (final t in _transforms) {
      sum += t.revision;
    }
    return sum;
  }

  void add(MidiTransform t) {
    _transforms.add(t);
    _bump();
  }

  /// Inserts [t] at [index] (clamped to `[0, length]`), shifting later
  /// transforms right. Used by the sidebar's "duplicate" action to drop the
  /// copy directly after its original rather than at the end of the chain.
  void insert(int index, MidiTransform t) {
    _transforms.insert(index.clamp(0, _transforms.length), t);
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

  /// Moves the transform at [from] so it ends up at index [to] in the
  /// resulting list — [to] is the item's **final position**, already adjusted
  /// for the removal at [from]. This matches `ReorderableListView.onReorderItem`
  /// (Flutter ≥ 3.44), so the sidebar wires the callback straight through
  /// (issue #427). [to] is clamped to `[0, length - 1]`.
  void reorder(int from, int to) {
    if (from == to) return;
    final t = _transforms.removeAt(from);
    _transforms.insert(to.clamp(0, _transforms.length), t);
    _bump();
  }

  /// Replace the whole transform list in one shot. Used when converting a
  /// branching graph clip back to a linear chain (issue #77): the graph's
  /// linear spine is written here wholesale, so the chain reflects the graph
  /// the moment the mode flips.
  void setTransforms(Iterable<MidiTransform> transforms) {
    _transforms
      ..clear()
      ..addAll(transforms);
    _bump();
  }

  /// Signals that the source clip's contents changed underneath the chain
  /// (e.g. a file import mutated it via [MidiClip.replaceWith]). Bumps
  /// [version] and notifies so bound painters recompute [output] and repaint.
  void notifySourceChanged() => _bump();

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
