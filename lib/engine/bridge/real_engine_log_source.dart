import 'package:yse/yse.dart';

import 'engine_log_source.dart';

/// The production [EngineLogSource]: yse's `Log.messages` broadcast stream
/// (design `docs/design/diagnostics.md` §2).
///
/// Subscribing installs the in-process callback that replaces yse's default
/// file sink — from then on the engine's messages flow into the unified log and
/// our own session file, not `YSElog.txt`. The `package:yse` import is confined
/// to the bridge, per the engine-façade boundary.
class RealEngineLogSource implements EngineLogSource {
  /// A const production source over the borrowed [Log] singleton.
  const RealEngineLogSource();

  @override
  Stream<String> get messages => Log.instance.messages;
}
