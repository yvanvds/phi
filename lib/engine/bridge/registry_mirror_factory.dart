import 'package:yse/yse.dart';

import 'code_evaluator.dart';
import 'no_op_registry_mirror.dart';
import 'real_registry_mirror.dart';
import 'registry_mirror.dart';

/// Builds the production [RegistryMirror] for the engine (design
/// `docs/design/live-coding.md` §3, issue #314): a [RealRegistryMirror] that
/// pushes `phi._sync_*` scripts through [evaluator] when the library was built
/// with Python (`LiveCoding.enabled`), and the [NoOpRegistryMirror] otherwise —
/// so a Python-less engine build still boots with the name-table seam wired but
/// silent, exactly as [buildCodeEvaluator] keeps the Code surface useful.
///
/// Pass the *same* [evaluator] the Code surface runs user blocks on. Registry
/// pushes then share one ordered queue with user evaluations, so a block
/// evaluated right after a rename already sees the renamed `phi` table — the
/// ordering guarantee the [RealRegistryMirror] doc describes. (`LiveCoding` is a
/// static/global façade, so this matters for queue ordering, not for which
/// interpreter the pushes reach.)
///
/// The gate lives here, in the bridge, so nothing above `lib/engine/bridge/`
/// touches `package:yse` (the engine-façade boundary): the app composition root
/// calls this and stays yse-free.
///
/// [pythonEnabled] overrides the compile-time probe for tests (which cannot
/// load the native library headlessly); production leaves it null to query
/// `LiveCoding.enabled`.
RegistryMirror buildRegistryMirror(
  CodeEvaluator evaluator, {
  bool? pythonEnabled,
}) => (pythonEnabled ?? LiveCoding.enabled)
    ? RealRegistryMirror(evaluator)
    : const NoOpRegistryMirror();
