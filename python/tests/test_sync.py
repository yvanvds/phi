"""The ``_sync`` protocol: create / rename / regroup / delete / replace, and
the headline property — **bound proxies follow a rename in place** (design
§3, "resolve once, bind the object")."""

import unittest

from _support import PhiTestCase

import phi


class SyncTableTest(PhiTestCase):
    def test_create_adds_entry_and_parent_groups(self):
        phi._sync_create('clip.drums.intro_fill')
        self.assertIn('drums', phi.clip)
        self.assertIn('intro_fill', phi.clip.drums)

    def test_delete_removes_entry(self):
        phi._sync_create('clip.drums.intro_fill')
        phi._sync_delete('clip.drums.intro_fill')
        self.assertNotIn('intro_fill', phi.clip.drums)

    def test_delete_removes_whole_subtree(self):
        phi._sync_create('clip.drums.intro_fill')
        phi._sync_create('clip.drums.outro')
        phi._sync_delete('clip.drums')
        self.assertNotIn('drums', phi.clip)


class RenameFollowingTest(PhiTestCase):
    def test_bound_proxy_follows_a_rename(self):
        phi._sync_create('voice.bells')
        pad = phi.voice.bells  # bound before the rename

        pad.note(60)
        self.assertEqual(
            self.sent[-1],
            ('phi.ctl.voice.bells.note', [60.0, 100.0]),
        )

        phi._sync_rename('voice.bells', 'voice.chimes')

        pad.note(60)  # same proxy object, new address
        self.assertEqual(
            self.sent[-1],
            ('phi.ctl.voice.chimes.note', [60.0, 100.0]),
        )

    def test_rename_preserves_entry_identity(self):
        phi._sync_create('voice.bells')
        before = phi.voice.bells._entry
        phi._sync_rename('voice.bells', 'voice.chimes')
        after = phi.voice.chimes._entry
        self.assertIs(before, after)

    def test_group_rename_cascades_to_children(self):
        phi._sync_create('clip.drums.intro_fill')
        leaf = phi.clip.drums.intro_fill  # bound to the child

        phi._sync_rename('clip.drums', 'clip.perc')

        leaf.play()  # child address rebased under the renamed group
        self.assertEqual(self.sent[-1], ('phi.ctl.clip.perc.intro_fill.play', 1))

    def test_regroup_moves_entry_to_a_new_parent(self):
        phi._sync_create('clip.intro_fill')
        clip_proxy = phi.clip.intro_fill

        phi._sync_regroup('clip.intro_fill', 'clip.drums.intro_fill')

        clip_proxy.play()
        self.assertEqual(
            self.sent[-1],
            ('phi.ctl.clip.drums.intro_fill.play', 1),
        )
        self.assertIn('intro_fill', phi.clip.drums)
        self.assertNotIn('intro_fill', phi.clip)

    def test_move_of_unknown_address_is_tolerated(self):
        # Best-effort resync: a move we never saw the source of just creates
        # the destination rather than raising.
        phi._sync_rename('clip.ghost', 'clip.real')
        self.assertIn('real', phi.clip)


class StateCurrentTest(PhiTestCase):
    """``state.current`` — the host-pushed live-state readable (issue #246)."""

    def test_current_defaults_to_none(self):
        self.assertIsNone(phi.state.current)

    def test_host_push_makes_current_readable(self):
        phi._sync_state_current('verse')
        self.assertEqual(phi.state.current, 'verse')

    def test_push_of_none_clears(self):
        phi._sync_state_current('verse')
        phi._sync_state_current(None)
        self.assertIsNone(phi.state.current)

    def test_reset_clears_current(self):
        phi._sync_state_current('verse')
        phi._reset()
        self.assertIsNone(phi.state.current)

    def test_current_appears_in_dir_of_the_state_root(self):
        self.assertIn('current', dir(phi.state))

    def test_current_feeds_fire(self):
        # ``state.fire(state.current)`` round-trips the pushed name.
        phi._sync_state_current('verse')
        phi.state.fire(phi.state.current)
        self.assertEqual(self.sent[-1], ('phi.ctl.state.fire', 'verse'))


class ReplaceTest(PhiTestCase):
    def test_replace_rebuilds_the_table(self):
        phi._sync_create('clip.old')
        phi._sync_replace(['clip.drums.intro_fill', 'voice.bells'])
        self.assertNotIn('old', phi.clip)
        self.assertIn('intro_fill', phi.clip.drums)
        self.assertTrue(hasattr(phi.voice, 'bells'))

    def test_replace_preserves_surviving_entry_identity(self):
        phi._sync_create('voice.bells')
        before = phi.voice.bells._entry
        phi._sync_replace(['voice.bells', 'voice.pad'])
        after = phi.voice.bells._entry
        self.assertIs(before, after)

    def test_bound_proxy_survives_a_replace_that_keeps_it(self):
        phi._sync_create('voice.bells')
        pad = phi.voice.bells
        phi._sync_replace(['voice.bells', 'clip.drums.intro_fill'])
        # Still bound, and still follows a later rename.
        phi._sync_rename('voice.bells', 'voice.chimes')
        pad.note(48)
        self.assertEqual(
            self.sent[-1],
            ('phi.ctl.voice.chimes.note', [48.0, 100.0]),
        )


if __name__ == '__main__':
    unittest.main()
