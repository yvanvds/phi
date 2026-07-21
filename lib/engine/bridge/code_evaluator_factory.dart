import 'package:yse/yse.dart';

import 'code_evaluator.dart';
import 'no_op_code_evaluator.dart';
import 'real_code_evaluator.dart';

/// Builds the production [CodeEvaluator] for the Code surface (design
/// `docs/design/live-coding.md` §5, issue #232): a [RealCodeEvaluator] over the
/// engine's embedded CPython when the library was built with Python
/// (`LiveCoding.enabled`), and the [NoOpCodeEvaluator] otherwise — so the
/// surface still ships and stays useful on a Python-less engine build.
///
/// The gate lives here, in the bridge, so nothing above `lib/engine/bridge/`
/// touches `package:yse` (the engine-façade boundary): the app layer calls this
/// and stays yse-free.
///
/// [pythonEnabled] overrides the compile-time probe for tests (which cannot
/// load the native library headlessly); production leaves it null to query
/// `LiveCoding.enabled`.
CodeEvaluator buildCodeEvaluator({bool? pythonEnabled}) =>
    (pythonEnabled ?? LiveCoding.enabled)
    ? RealCodeEvaluator()
    : NoOpCodeEvaluator();
