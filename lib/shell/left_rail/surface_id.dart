/// Identity of the performer surfaces. Used by the left rail to pick
/// which surface the centre region renders.
enum SurfaceId {
  scene('Scene'),
  patcher('Patcher'),
  code('Code'),
  state('State'),
  midi('MIDI'),
  racks('Racks'),
  mix('Mix');

  const SurfaceId(this.label);

  final String label;
}
