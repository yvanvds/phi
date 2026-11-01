import 'package:flutter/services.dart';

import 'patch_tutorial_source.dart';

/// The production [PatchTutorialSource]: the app's asset bundle, where
/// `pubspec.yaml` declares `assets/tutorials/patcher/` (issue #489).
class BundlePatchTutorialSource implements PatchTutorialSource {
  const BundlePatchTutorialSource();

  @override
  Future<String?> read(String path) async {
    try {
      return await rootBundle.loadString(path, cache: false);
    } catch (_) {
      // Not bundled, or no asset bundle at all (a headless engine test with
      // no binding) — either way read as "no such tutorial", never a crash.
      return null;
    }
  }
}
