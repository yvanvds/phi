/// Where a GPU-backed Scene renderer is in bringing its 3D view up.
enum SceneViewStatus {
  /// Not started: `init` has not run (or `dispose` reset it).
  idle,

  /// Loading the engine's static resources (shaders, built-in textures).
  starting,

  /// The 3D view draws.
  ready,

  /// The 3D view cannot draw here — typically Flutter GPU is off or the
  /// backend lacks Impeller (the headless `flutter test` runner, for one). The
  /// view shows a notice instead; everything else keeps working.
  unavailable,
}
