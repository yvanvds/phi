"""Shared test support: path bootstrap, fake-bus wiring, table reset.

Every test module imports this first. It makes both the ``phi`` package (under
``python/``) and ``fake_yse`` (this directory) importable regardless of how the
suite is launched — directly, via ``unittest discover``, or through the Dart
harness that runs it in CI.
"""

import os
import sys
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_PYROOT = os.path.dirname(_HERE)
for _path in (_PYROOT, _HERE):
    if _path not in sys.path:
        sys.path.insert(0, _path)

import fake_yse  # noqa: E402  (after the sys.path bootstrap above)

# Install the fake before phi resolves the bus, so phi._bus() finds it.
sys.modules['yse'] = fake_yse

import phi  # noqa: E402


class PhiTestCase(unittest.TestCase):
    """Base case that isolates each test: fresh table, empty fake bus."""

    def setUp(self):
        sys.modules['yse'] = fake_yse
        fake_yse.reset()
        phi._reset()

    @property
    def sent(self):
        return fake_yse.sent

    @property
    def scheduled(self):
        return fake_yse.scheduled

    def fire_due(self):
        fake_yse.fire_due()
