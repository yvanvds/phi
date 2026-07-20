// FFI-free descriptors mirroring the engine's `PatcherRegistry` metadata.
//
// The patcher gateway hands these back from `objectTypes()` so the palette
// and reference panel (later epic issues) can render the engine's own
// object catalogue — categories, per-inlet / per-outlet docs, and creation
// parameters — without ever importing `package:yse`. Each type mirrors one
// `package:yse` metadata type by value; the bridge is the only place the
// mapping from the FFI enums happens (see `real_patcher_gateway.dart`).

/// Documentation category an object type is filed under. Mirrors yse's
/// `PCategory`; drives the section headings on the object reference.
enum PatchObjectCategory {
  unset,
  oscillator,
  filter,
  math,
  generic,
  gui,
  time,
  midi,
}

/// Data type an outlet emits. Mirrors yse's `OutType`; the cable layer
/// colours a wire by its source outlet's type.
enum PatchOutletType { invalid, bang, float, integer, buffer, list, any }

/// One message kind an inlet accepts. Mirrors yse's `InletAccepts`; the set
/// on an inlet drives drag-time compatibility (which inlets light up for a
/// given outlet). `buffer` marks an audio-rate (DSP) inlet.
enum PatchInletAccept { buffer, float, integer, bang, list }

/// Documentation for one inlet of a [PatchObjectDescriptor].
class PatchInletDescriptor {
  const PatchInletDescriptor({
    required this.label,
    required this.doc,
    required this.range,
    required this.accepts,
  });

  final String label;
  final String doc;
  final String range;
  final Set<PatchInletAccept> accepts;

  /// Whether this inlet takes an audio-rate signal — the `isDspInput`
  /// projection the cable layer colours by. An audio inlet accepts a buffer.
  bool get isDspInput => accepts.contains(PatchInletAccept.buffer);
}

/// Documentation for one outlet of a [PatchObjectDescriptor].
class PatchOutletDescriptor {
  const PatchOutletDescriptor({
    required this.label,
    required this.doc,
    required this.range,
    required this.type,
  });

  final String label;
  final String doc;
  final String range;
  final PatchOutletType type;
}

/// Documentation for one creation parameter of a [PatchObjectDescriptor].
class PatchParamDescriptor {
  const PatchParamDescriptor({
    required this.name,
    required this.doc,
    required this.defaultValue,
    required this.range,
  });

  final String name;
  final String doc;
  final String defaultValue;
  final String range;
}

/// Full metadata for one registered patcher object type — the FFI-free
/// projection of a `package:yse` `PatcherObjectType`.
class PatchObjectDescriptor {
  const PatchObjectDescriptor({
    required this.type,
    required this.description,
    required this.category,
    required this.isDsp,
    required this.inlets,
    required this.outlets,
    required this.params,
  });

  /// The type identifier (one of the engine's `Obj.*` constants).
  final String type;

  /// One-line human-readable description of the object.
  final String description;

  /// The category the object is filed under.
  final PatchObjectCategory category;

  /// Whether this is a DSP / audio-rate object (the `~` prefix convention).
  final bool isDsp;

  final List<PatchInletDescriptor> inlets;
  final List<PatchOutletDescriptor> outlets;
  final List<PatchParamDescriptor> params;
}
