"""Engine-direct verbs — the verification suite for issue #234.

The engine-direct plane (design ``docs/design/live-coding.md`` §4) publishes
straight to an engine-owned bus prefix, with **no host round-trip**:

* ``mix.<bus>`` volume  → ``channel.<address>.volume``  (yse ``channel.`` prefix,
  yse-soundengine #123);
* ``patch.<name>`` slots → ``patcher.<address>.<slot>`` (yse ``patcher.`` prefix,
  yse-soundengine #122).

Both prefixes were **verified live** against yse's authoritative DSL spec
(``docs/design/live_coding_dsl.md``, §"Address grammar"): the reserved prefixes
``channel.<name>.<prop>`` and ``patcher.<name>.<slot>`` shipped as spec'd, so
these verbs stay engine-direct (no ``phi.ctl`` fallback). This module is the
"Done when" of #234 — it asserts the emitted **addresses and values for both
``set`` and ``fade``**, and pins the two invariants that make the plane
engine-direct:

* the address carries the engine prefix, never ``phi.ctl`` (no host round-trip);
* ``fade`` is **control-rate** — it never publishes inline, only steps the value
  once per tick through ``yse.schedule`` (a publish at tick *t* lands at *t+1*,
  per the yse spec; no engine ramp API is assumed).

Run in CI through the Dart harness (``test/engine/python/phi_library_test.dart``,
issue #230).
"""

import unittest

from _support import PhiTestCase

import phi


class _EngineDirectAssertions(PhiTestCase):
    """Shared assertions for either engine-direct kind."""

    def assertEngineDirect(self):
        """No engine-direct verb may ever touch the host control plane."""
        for address, _ in self.sent:
            self.assertFalse(
                address.startswith(phi.CTL_PREFIX),
                'engine-direct verb leaked onto the host plane: %r' % address,
            )


class MixVolumeEngineDirectTest(_EngineDirectAssertions):
    """``mix.<bus>`` volume rides ``channel.<address>.volume``."""

    def setUp(self):
        super().setUp()
        phi._sync_create('mix.pads')

    def test_set_publishes_channel_volume(self):
        phi.mix.pads.set(0.6)
        self.assertEqual(self.sent[-1], ('channel.pads.volume', 0.6))
        self.assertEngineDirect()

    def test_attribute_assignment_publishes_channel_volume(self):
        phi.mix.pads.volume = 0.3
        self.assertEqual(self.sent[-1], ('channel.pads.volume', 0.3))
        self.assertEngineDirect()

    def test_value_is_coerced_to_float(self):
        phi.mix.pads.set(1)
        address, value = self.sent[-1]
        self.assertEqual(address, 'channel.pads.volume')
        self.assertIsInstance(value, float)
        self.assertEqual(value, 1.0)

    def test_grouped_bus_strips_only_the_kind(self):
        phi._sync_create('mix.drums.sub')
        phi.mix.drums.sub.set(0.5)
        # Only the leading ``mix.`` kind is dropped; the group path survives.
        self.assertEqual(self.sent[-1], ('channel.drums.sub.volume', 0.5))
        self.assertEngineDirect()

    def test_set_on_the_namespace_root_raises(self):
        with self.assertRaises(TypeError):
            phi.mix.set(0.5)

    def test_fade_is_control_rate_and_never_publishes_inline(self):
        phi.mix.pads.fade(0.8, 4)
        # Nothing on the bus yet: every step is deferred to a future tick.
        self.assertEqual(self.sent, [])
        self.assertEqual(len(self.scheduled), 4)
        self.assertEqual([r['beat'] for r in self.scheduled], [1, 2, 3, 4])

    def test_fade_ramps_channel_volume_up_to_the_target(self):
        phi.mix.pads.fade(0.8, 4)
        self.fire_due()
        addresses = {address for address, _ in self.sent}
        self.assertEqual(addresses, {'channel.pads.volume'})
        values = [value for _, value in self.sent]
        self.assertEqual(len(values), 4)
        self.assertTrue(all(a <= b for a, b in zip(values, values[1:])))
        self.assertAlmostEqual(values[-1], 0.8)
        self.assertEngineDirect()

    def test_fade_starts_from_the_last_set_value(self):
        phi.mix.pads.set(0.4)
        phi.mix.pads.fade(0.8, 2)
        self.fire_due()
        ramp = [value for _, value in self.sent[1:]]  # drop the initial set
        self.assertGreater(ramp[0], 0.4)  # first step lifts off 0.4, not 0.0
        self.assertAlmostEqual(ramp[-1], 0.8)

    def test_fade_rejects_a_non_positive_tick_count(self):
        with self.assertRaises(ValueError):
            phi.mix.pads.fade(0.8, 0)


class PatchSlotEngineDirectTest(_EngineDirectAssertions):
    """``patch.<name>`` slots ride ``patcher.<address>.<slot>``."""

    def setUp(self):
        super().setUp()
        phi._sync_create('patch.swirl')

    def test_send_publishes_the_named_slot(self):
        phi.patch.swirl.send('cutoff', 0.4)
        self.assertEqual(self.sent[-1], ('patcher.swirl.cutoff', 0.4))
        self.assertEngineDirect()

    def test_set_is_the_same_engine_direct_slot_publish(self):
        phi.patch.swirl.set('cutoff', 0.4)
        self.assertEqual(self.sent[-1], ('patcher.swirl.cutoff', 0.4))
        self.assertEngineDirect()

    def test_attribute_assignment_targets_the_slot(self):
        phi.patch.swirl.cutoff = 0.7
        self.assertEqual(self.sent[-1], ('patcher.swirl.cutoff', 0.7))
        self.assertEngineDirect()

    def test_grouped_patch_strips_only_the_kind(self):
        phi._sync_create('patch.fx.swirl')
        phi.patch.fx.swirl.send('cutoff', 0.2)
        self.assertEqual(self.sent[-1], ('patcher.fx.swirl.cutoff', 0.2))
        self.assertEngineDirect()

    def test_send_without_a_slot_raises(self):
        with self.assertRaises(TypeError):
            phi.patch.swirl.send(0.4)

    def test_fade_is_control_rate_and_never_publishes_inline(self):
        phi.patch.swirl.fade('cutoff', 1.0, 3)
        self.assertEqual(self.sent, [])
        self.assertEqual(len(self.scheduled), 3)
        self.assertEqual([r['beat'] for r in self.scheduled], [1, 2, 3])

    def test_fade_ramps_a_named_slot_up_to_the_target(self):
        phi.patch.swirl.fade('cutoff', 1.0, 2)
        self.fire_due()
        self.assertTrue(all(a == 'patcher.swirl.cutoff' for a, _ in self.sent))
        values = [value for _, value in self.sent]
        self.assertTrue(all(a <= b for a, b in zip(values, values[1:])))
        self.assertAlmostEqual(values[-1], 1.0)
        self.assertEngineDirect()

    def test_fade_without_a_slot_raises(self):
        with self.assertRaises(TypeError):
            phi.patch.swirl.fade(1.0, 2)


if __name__ == '__main__':
    unittest.main()
