/// Which of a `.preset`'s slots hold a snapshot, read from what the object
/// saves with the patch (issue #477).
///
/// The object's GUI value is only the active slot (`-1` when none), so the
/// occupancy a slot grid shows comes from its saved contents instead: the
/// `state` its patch-dump record carries (`gPreset::DumpState`),
/// `{"active": n, "slots": [{"slot": n, "objects": [...]}, ...]}`. A slot is
/// listed there only while it holds at least one captured control, and an
/// untouched object saves no `state` at all.
class PresetSlots {
  const PresetSlots(this.stored);

  /// Read the [state] an object's dump record carries; null (nothing saved)
  /// is a bank with every slot empty. Malformed entries are skipped, the way
  /// the engine's `RestoreState` drops them.
  factory PresetSlots.fromState(Map<String, Object?>? state) {
    final slots = state?['slots'];
    if (slots is! List) return empty;
    return PresetSlots({
      for (final entry in slots)
        if (entry is Map)
          if (entry['slot'] case final num slot)
            if (entry['objects'] case final List<Object?> objects)
              if (slot >= 0 && objects.isNotEmpty) slot.toInt(),
    });
  }

  /// No slot stored.
  static const PresetSlots empty = PresetSlots({});

  /// The numbers of the slots that hold a snapshot.
  final Set<int> stored;

  /// Whether [slot] holds a snapshot.
  bool isStored(int slot) => stored.contains(slot);
}
