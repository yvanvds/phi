import 'package:vector_math/vector_math_64.dart';

import '../../domain/scene/pick_ray.dart';

/// The pick / select / grab operations the Scene surface's pointer drives.
///
/// Renderer-agnostic — pure `vector_math_64` and domain [PickRay], with no 3D
/// engine types — so the macbear input controller can call into it without
/// knowing where the live agents come from, and the Scene surface can
/// implement it without importing macbear. The surface forwards the pick /
/// grab half to `EngineMidiController` (the same field code drives, so mouse
/// and code share grab state) and keeps the selection itself.
abstract interface class ScenePickHandler {
  /// The key of the live agent under [ray], or `null` when it hits none.
  int? pick(PickRay ray);

  /// The current world position of the agent under [key], or `null` when no
  /// such agent is alive. Used to anchor a drag at the grabbed agent's depth
  /// and to keep the selection highlight on the moving agent.
  Vector3? agentPosition(int key);

  /// Begin grabbing the agent under [key] — the start of a pointer pull.
  void grab(int key);

  /// Move the held target the grabbed agent is pulled toward.
  void moveGrabTo(Vector3 target);

  /// Release the current grab, handing motion back to the field.
  void releaseGrab();

  /// Record the selected agent ([key]), or clear the selection with `null`.
  /// The surface reflects this as a highlight on the agent.
  void select(int? key);
}
