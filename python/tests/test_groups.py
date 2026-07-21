"""Group proxies: iteration + group verbs (design §3)."""

import unittest

from _support import PhiTestCase

import phi


class GroupIterationTest(PhiTestCase):
    def test_group_is_iterable_over_its_members(self):
        phi._sync_create('clip.drums.intro_fill')
        phi._sync_create('clip.drums.outro')
        addresses = sorted(child._entry.address for child in phi.clip.drums)
        self.assertEqual(
            addresses,
            ['clip.drums.intro_fill', 'clip.drums.outro'],
        )

    def test_iteration_yields_proxies_you_can_drive(self):
        phi._sync_create('clip.drums.a')
        phi._sync_create('clip.drums.b')
        for member in phi.clip.drums:
            member.play()
        addresses = sorted(address for address, _ in self.sent)
        self.assertEqual(
            addresses,
            ['phi.ctl.clip.drums.a.play', 'phi.ctl.clip.drums.b.play'],
        )

    def test_nested_groups_iterate_at_each_level(self):
        phi._sync_create('clip.drums.fills.a')
        phi._sync_create('clip.drums.fills.b')
        phi._sync_create('clip.drums.main')
        top = sorted(child._entry.address for child in phi.clip.drums)
        self.assertEqual(top, ['clip.drums.fills', 'clip.drums.main'])
        fills = sorted(child._entry.address for child in phi.clip.drums.fills)
        self.assertEqual(fills, ['clip.drums.fills.a', 'clip.drums.fills.b'])


class GroupVerbTest(PhiTestCase):
    def test_group_verb_publishes_the_group_address(self):
        phi._sync_create('clip.drums.intro_fill')
        phi.clip.drums.stop()
        # The library emits the *group* address; the host fans it out to the
        # members (issue #233).
        self.assertEqual(self.sent[-1], ('phi.ctl.clip.drums.stop', 1))

    def test_namespace_root_verb_addresses_the_whole_kind(self):
        phi.clip.stop()
        self.assertEqual(self.sent[-1], ('phi.ctl.clip.stop', 1))


if __name__ == '__main__':
    unittest.main()
