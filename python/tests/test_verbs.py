"""Every verb's emitted address and value shape (issue #230 "Done when").

Two planes, invisible at the call site (design §4):

* host-mediated verbs publish to ``phi.ctl.*``;
* engine-direct verbs (mix / patch) publish to ``channel.*`` / ``patcher.*``.
"""

import unittest

from _support import PhiTestCase

import phi


class ClipVerbTest(PhiTestCase):
    def setUp(self):
        super().setUp()
        phi._sync_create('clip.drums.intro_fill')
        self.fill = phi.clip.drums.intro_fill

    def test_play(self):
        self.fill.play()
        self.assertEqual(self.sent[-1], ('phi.ctl.clip.drums.intro_fill.play', 1))

    def test_stop(self):
        self.fill.stop()
        self.assertEqual(self.sent[-1], ('phi.ctl.clip.drums.intro_fill.stop', 1))

    def test_pause(self):
        self.fill.pause()
        self.assertEqual(self.sent[-1], ('phi.ctl.clip.drums.intro_fill.pause', 1))

    def test_loop_on_and_off(self):
        self.fill.loop()
        self.assertEqual(self.sent[-1], ('phi.ctl.clip.drums.intro_fill.loop', 1))
        self.fill.loop(False)
        self.assertEqual(self.sent[-1], ('phi.ctl.clip.drums.intro_fill.loop', 0))


class VoiceVerbTest(PhiTestCase):
    def setUp(self):
        super().setUp()
        phi._sync_create('voice.bells')
        self.bells = phi.voice.bells

    def test_note_default_velocity(self):
        self.bells.note(60)
        self.assertEqual(self.sent[-1], ('phi.ctl.voice.bells.note', [60.0, 100.0]))

    def test_note_explicit_velocity(self):
        self.bells.note(60, 40)
        self.assertEqual(self.sent[-1], ('phi.ctl.voice.bells.note', [60.0, 40.0]))

    def test_off_specific_pitch(self):
        self.bells.off(60)
        self.assertEqual(self.sent[-1], ('phi.ctl.voice.bells.off', [60.0]))

    def test_off_all(self):
        self.bells.off()
        self.assertEqual(self.sent[-1], ('phi.ctl.voice.bells.off', []))


class MixVerbTest(PhiTestCase):
    def setUp(self):
        super().setUp()
        phi._sync_create('mix.pads')

    def test_set_is_engine_direct_volume(self):
        phi.mix.pads.set(0.6)
        self.assertEqual(self.sent[-1], ('channel.pads.volume', 0.6))

    def test_attribute_assignment_is_engine_direct(self):
        phi.mix.pads.volume = 0.3
        self.assertEqual(self.sent[-1], ('channel.pads.volume', 0.3))

    def test_group_bus_strips_only_the_kind(self):
        phi._sync_create('mix.drums.sub')
        phi.mix.drums.sub.set(0.5)
        self.assertEqual(self.sent[-1], ('channel.drums.sub.volume', 0.5))

    def test_set_on_namespace_root_raises(self):
        with self.assertRaises(TypeError):
            phi.mix.set(0.5)

    def test_fade_schedules_a_ramp_of_engine_sets(self):
        phi.mix.pads.fade(0.8, 4)
        self.assertEqual(len(self.scheduled), 4)
        self.assertEqual([r['beat'] for r in self.scheduled], [1, 2, 3, 4])
        self.fire_due()
        addresses = {address for address, _ in self.sent}
        self.assertEqual(addresses, {'channel.pads.volume'})
        values = [value for _, value in self.sent]
        self.assertEqual(len(values), 4)
        self.assertAlmostEqual(values[-1], 0.8)
        self.assertTrue(all(a <= b for a, b in zip(values, values[1:])))

    def test_fade_starts_from_the_last_set_value(self):
        phi.mix.pads.set(0.4)
        phi.mix.pads.fade(0.8, 2)
        self.fire_due()
        _, last = self.sent[-1]
        self.assertAlmostEqual(last, 0.8)
        # First ramp step is above the 0.4 starting point, not from zero.
        ramp = [value for _, value in self.sent[1:]]
        self.assertGreater(ramp[0], 0.4)


class PatchVerbTest(PhiTestCase):
    def setUp(self):
        super().setUp()
        phi._sync_create('patch.swirl')

    def test_set_slot_is_engine_direct(self):
        phi.patch.swirl.set('cutoff', 0.4)
        self.assertEqual(self.sent[-1], ('patcher.swirl.cutoff', 0.4))

    def test_send_is_an_alias_of_set(self):
        phi.patch.swirl.send('cutoff', 0.4)
        self.assertEqual(self.sent[-1], ('patcher.swirl.cutoff', 0.4))

    def test_attribute_assignment_targets_the_slot(self):
        phi.patch.swirl.cutoff = 0.7
        self.assertEqual(self.sent[-1], ('patcher.swirl.cutoff', 0.7))

    def test_fade_ramps_a_named_slot(self):
        phi.patch.swirl.fade('cutoff', 1.0, 2)
        self.assertEqual(len(self.scheduled), 2)
        self.fire_due()
        self.assertTrue(all(a == 'patcher.swirl.cutoff' for a, _ in self.sent))
        self.assertAlmostEqual(self.sent[-1][1], 1.0)


class FxVerbTest(PhiTestCase):
    def setUp(self):
        super().setUp()
        phi._sync_create('fx.reverb')

    def test_set_is_host_mediated(self):
        phi.fx.reverb.set('mix', 0.4)
        self.assertEqual(self.sent[-1], ('phi.ctl.fx.reverb.mix', 0.4))

    def test_attribute_assignment_is_host_mediated(self):
        phi.fx.reverb.mix = 0.25
        self.assertEqual(self.sent[-1], ('phi.ctl.fx.reverb.mix', 0.25))


class StateVerbTest(PhiTestCase):
    def test_fire_publishes_the_target(self):
        phi.state.fire('break')
        self.assertEqual(self.sent[-1], ('phi.ctl.state.fire', 'break'))


class VarVerbTest(PhiTestCase):
    def test_string_assignment_keeps_its_type(self):
        phi.var.section = 'b'
        self.assertEqual(self.sent[-1], ('phi.ctl.var.section', 'b'))

    def test_numeric_assignment_keeps_its_type(self):
        phi.var.count = 3
        self.assertEqual(self.sent[-1], ('phi.ctl.var.count', 3))


class DomainVerbTest(PhiTestCase):
    def test_tempo_assignment_is_host_mediated_float(self):
        phi._sync_create('domain.drum')
        phi.domain.drum.tempo = 124
        self.assertEqual(self.sent[-1], ('phi.ctl.domain.drum.tempo', 124.0))


class SchedulingSugarTest(PhiTestCase):
    def test_after_schedules_once(self):
        calls = []
        phi.after(2, lambda: calls.append('x'))
        self.assertEqual(len(self.scheduled), 1)
        self.assertEqual(self.scheduled[0]['beat'], 2)
        self.fire_due()
        self.assertEqual(calls, ['x'])

    def test_every_reschedules_itself(self):
        calls = []
        phi.every(1, lambda: calls.append('tick'))
        self.assertEqual(len(self.scheduled), 1)
        self.fire_due()  # fires once...
        self.assertEqual(calls, ['tick'])
        self.assertEqual(len(self.scheduled), 1)  # ...and re-armed
        self.fire_due()
        self.assertEqual(calls, ['tick', 'tick'])

    def test_every_with_a_bound_proxy_follows_a_rename(self):
        phi._sync_create('voice.bells')
        pad = phi.voice.bells
        phi.every(1, lambda: pad.note(60))
        self.fire_due()
        self.assertEqual(self.sent[-1], ('phi.ctl.voice.bells.note', [60.0, 100.0]))
        phi._sync_rename('voice.bells', 'voice.chimes')
        self.fire_due()
        self.assertEqual(self.sent[-1], ('phi.ctl.voice.chimes.note', [60.0, 100.0]))


if __name__ == '__main__':
    unittest.main()
