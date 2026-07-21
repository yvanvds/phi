"""Namespaces, dot-access resolution, and ``dir()`` reflection (design §3)."""

import unittest

from _support import PhiTestCase

import phi


class NamespaceTest(PhiTestCase):
    def test_all_eight_namespaces_exist(self):
        for name in ('voice', 'clip', 'mix', 'fx', 'patch', 'domain', 'var', 'state'):
            self.assertTrue(hasattr(phi, name), name)

    def test_getattr_resolves_a_table_entry(self):
        phi._sync_create('voice.bells')
        proxy = phi.voice.bells
        self.assertEqual(proxy._entry.address, 'voice.bells')
        self.assertEqual(proxy._entry.kind, 'voice')

    def test_nested_group_resolution(self):
        phi._sync_create('clip.drums.intro_fill')
        leaf = phi.clip.drums.intro_fill
        self.assertEqual(leaf._entry.address, 'clip.drums.intro_fill')

    def test_unknown_member_raises_attribute_error(self):
        with self.assertRaises(AttributeError):
            _ = phi.voice.nope

    def test_dir_reflects_table_plus_verbs(self):
        phi._sync_create('clip.drums')
        phi._sync_create('clip.bass')
        listed = dir(phi.clip)
        self.assertIn('drums', listed)
        self.assertIn('bass', listed)
        # Verb names are surfaced too, so in-script exploration matches the
        # editor's completion table.
        self.assertIn('play', listed)
        self.assertIn('stop', listed)

    def test_contains_and_len(self):
        phi._sync_create('clip.drums.a')
        phi._sync_create('clip.drums.b')
        self.assertEqual(len(phi.clip.drums), 2)
        self.assertIn('a', phi.clip.drums)
        self.assertNotIn('c', phi.clip.drums)

    def test_dunder_lookups_do_not_resolve_as_entries(self):
        # A copy/pickle probe for a dunder must raise AttributeError cleanly,
        # not try to resolve a child named "__deepcopy__".
        with self.assertRaises(AttributeError):
            _ = phi.clip.__deepcopy__


if __name__ == '__main__':
    unittest.main()
