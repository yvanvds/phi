"""The cross-boundary contract: the exact ``phi._sync_*(...)`` scripts the Dart
``RegistryMirror`` emits (issue #231) drive the real library the way the mirror
intends — incremental ops, a bound proxy following a rename in place, the
full-sync **re-sync** onto a blank interpreter, and tolerance of kinds phi does
not model.

Each test ``exec``s the *string* the mirror pushes (not a direct call), so the
script form itself — quoting, argument order, the ``_sync_replace`` list — is
what CI verifies.
"""

import unittest

from _support import PhiTestCase

import phi


class MirrorScriptTest(PhiTestCase):
    """Runs the literal scripts ``RealRegistryMirror`` submits to the evaluator."""

    def run_script(self, script):
        """Exec one mirror-emitted line against a namespace exposing ``phi``,
        exactly as the embedded interpreter would."""
        exec(script, {'phi': phi})

    def test_create_script_populates_the_table(self):
        self.run_script("phi._sync_create('clip.drums.intro_fill')")
        self.assertIn('drums', phi.clip)
        self.assertIn('intro_fill', phi.clip.drums)

    def test_delete_script_removes_the_entry(self):
        self.run_script("phi._sync_create('clip.lead')")
        self.run_script("phi._sync_delete('clip.lead')")
        self.assertNotIn('lead', phi.clip)

    def test_rename_script_is_followed_by_a_bound_proxy(self):
        self.run_script("phi._sync_create('voice.bells')")
        pad = phi.voice.bells  # bound before the rename

        self.run_script("phi._sync_rename('voice.bells', 'voice.chimes')")

        pad.note(60)  # same proxy object, new address
        self.assertEqual(
            self.sent[-1],
            ('phi.ctl.voice.chimes.note', [60.0, 100.0]),
        )

    def test_regroup_script_moves_the_entry(self):
        self.run_script("phi._sync_create('clip.intro_fill')")
        self.run_script(
            "phi._sync_regroup('clip.intro_fill', 'clip.drums.intro_fill')"
        )
        self.assertIn('intro_fill', phi.clip.drums)
        self.assertNotIn('intro_fill', phi.clip)

    def test_replace_script_rebuilds_a_blank_interpreter(self):
        # The re-init re-sync: a `System` close/init blanks the table, then the
        # mirror re-pushes the whole tree as one `_sync_replace`.
        phi._reset()
        self.run_script(
            "phi._sync_replace(["
            "'clip.drums', 'clip.drums.intro_fill', 'voice.bells'])"
        )
        self.assertIn('intro_fill', phi.clip.drums)
        self.assertTrue(hasattr(phi.voice, 'bells'))

    def test_empty_replace_script_clears_the_table(self):
        self.run_script("phi._sync_create('clip.stale')")
        self.run_script('phi._sync_replace([])')
        self.assertNotIn('stale', phi.clip)


class UnknownKindToleranceTest(PhiTestCase):
    """The mirror forwards *every* registry kind; phi ignores the ones it does
    not model (``synth.``, …) rather than raising (issue #231)."""

    def run_script(self, script):
        exec(script, {'phi': phi})

    def test_create_of_an_unmodelled_kind_is_ignored(self):
        # Must not raise, and must not disturb a subsequent modelled create.
        self.run_script("phi._sync_create('synth.reface')")
        self.run_script("phi._sync_create('voice.bells')")
        self.assertTrue(hasattr(phi.voice, 'bells'))

    def test_delete_of_an_unmodelled_kind_is_ignored(self):
        self.run_script("phi._sync_delete('synth.reface')")  # no such root

    def test_rename_within_an_unmodelled_kind_is_ignored(self):
        self.run_script("phi._sync_rename('synth.a', 'synth.b')")

    def test_replace_skips_unmodelled_kinds(self):
        self.run_script(
            "phi._sync_replace(['synth.reface', 'voice.bells'])"
        )
        self.assertTrue(hasattr(phi.voice, 'bells'))
        self.assertFalse(hasattr(phi, 'synth'))


if __name__ == '__main__':
    unittest.main()
