import '../../domain/code/code_script_seed.dart';

/// Seed source loaded into the Code surface when no script library is wired
/// (the bare, project-less Phase-1 path). With a project, the library panel
/// opens the seeded `code.scratch` entity instead — this and that share one
/// canonical source ([codeScratchSource]), so the fallback and the seeded
/// script read identically.
const String codeSurfaceSeed = codeScratchSource;
