import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/shell_layout/drop_edge.dart';
import 'package:phi/domain/shell_layout/shell_layout.dart';
import 'package:phi/shell/layout/shell_layout_controller.dart';

/// Unit tests for the shell-side layout owner: the summon semantics (design §2,
/// §3 — focus a placed surface, open a closed one in the active pane), the
/// active-pane bookkeeping, and change notification.
void main() {
  test('seeds one pane with Mix focused and that pane active', () {
    final controller = ShellLayoutController();
    addTearDown(controller.dispose);

    expect(controller.layout.placedSurfaces, {'mix'});
    expect(controller.focusedSurface, 'mix');
    expect(controller.activePaneId, controller.layout.panes.first.id);
  });

  test(
    'summoning a closed surface opens it in the active pane and focuses it',
    () {
      final controller = ShellLayoutController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.summon('midi');

      expect(controller.layout.placedSurfaces, {'mix', 'midi'});
      expect(controller.layout.paneIdOf('midi'), controller.activePaneId);
      expect(controller.focusedSurface, 'midi');
      expect(notified, 1);
    },
  );

  test(
    'summoning a placed surface just focuses it (no duplicate, no move)',
    () {
      final controller = ShellLayoutController();
      addTearDown(controller.dispose);
      controller.summon('midi'); // [mix, midi], midi active

      controller.summon('mix'); // re-focus mix, still one pane, two tabs

      expect(controller.layout.paneCount, 1);
      expect(controller.layout.paneById('p1')!.tabs, ['mix', 'midi']);
      expect(controller.focusedSurface, 'mix');
    },
  );

  test('summoning the already-focused surface is silent', () {
    final controller = ShellLayoutController();
    addTearDown(controller.dispose);
    var notified = 0;
    controller.addListener(() => notified++);

    controller.summon('mix'); // already focused → no change

    expect(notified, 0);
  });

  test('split moves the surface into a fresh active pane', () {
    final controller = ShellLayoutController();
    addTearDown(controller.dispose);

    controller.split('p1', 'midi', DropEdge.right);

    final midiPane = controller.layout.paneIdOf('midi');
    expect(midiPane, isNotNull);
    expect(controller.activePaneId, midiPane); // the new pane is active
    expect(controller.layout.paneCount, 2);
    expect(controller.focusedSurface, 'midi');
  });

  test('replaceLayout swaps the tree and repoints a stale active pane', () {
    final controller = ShellLayoutController();
    addTearDown(controller.dispose);

    controller.replaceLayout(ShellLayout.seed('scene'));

    expect(controller.layout.placedSurfaces, {'scene'});
    // Old 'p1' active id survives (the seed reuses it); focus is the new content.
    expect(controller.layout.paneById(controller.activePaneId), isNotNull);
    expect(controller.focusedSurface, 'scene');
  });
}
