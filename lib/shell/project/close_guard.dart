import 'dart:ui' show AppExitResponse;

import 'close_decision.dart';

/// Decides whether the app may close, guarding against losing unsaved work
/// (design `docs/design/project-registry.md` §9).
///
/// The shell hands this to an `AppLifecycleListener.onExitRequested`. When the
/// project is clean it exits immediately; when dirty it asks [confirm] and maps
/// the [CloseDecision] to an [AppExitResponse] — saving first if asked, and
/// vetoing the exit on cancel. Kept free of widgets so the decision logic is
/// unit-testable without a window.
class CloseGuard {
  /// Builds a guard. [isDirty] reports the pending-changes state, [confirm]
  /// asks the performer what to do, and [save] persists the project when they
  /// choose to save.
  const CloseGuard({
    required this.isDirty,
    required this.confirm,
    required this.save,
  });

  /// Whether the open project has unsaved changes right now.
  final bool Function() isDirty;

  /// Asks the performer how to handle unsaved changes on close.
  final Future<CloseDecision> Function() confirm;

  /// Persists the project — invoked when the performer chooses to save.
  final Future<void> Function() save;

  /// The response to an exit request: [AppExitResponse.exit] when clean or the
  /// performer chose save/discard, [AppExitResponse.cancel] when they chose to
  /// keep working. Saving completes before the exit is allowed.
  Future<AppExitResponse> onExitRequested() async {
    if (!isDirty()) return AppExitResponse.exit;
    switch (await confirm()) {
      case CloseDecision.save:
        await save();
        // A save that was itself cancelled (e.g. the location picker dismissed
        // for a never-saved project) leaves the work dirty — veto rather than
        // exit and lose it.
        return isDirty() ? AppExitResponse.cancel : AppExitResponse.exit;
      case CloseDecision.discard:
        return AppExitResponse.exit;
      case CloseDecision.cancel:
        return AppExitResponse.cancel;
    }
  }
}
