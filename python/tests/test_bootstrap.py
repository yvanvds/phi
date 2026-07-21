"""Module bootstrap: exec the source into a module, install into
``sys.modules`` so ``import phi`` works, and expose the namespaces into a live
script's global scope (issue #230, design §3)."""

import importlib
import os
import sys
import types
import unittest

from _support import PhiTestCase  # noqa: F401  (ensures sys.path + fake bus)

import fake_yse


def _phi_source():
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(os.path.dirname(here), 'phi', '__init__.py')
    with open(path, 'r', encoding='utf-8') as handle:
        return handle.read()


class BootstrapTest(unittest.TestCase):
    def test_exec_installs_into_sys_modules(self):
        saved = sys.modules.get('phi')
        try:
            module = types.ModuleType('phi')
            module.__file__ = '<phi>'
            exec(compile(_phi_source(), '<phi>', 'exec'), module.__dict__)
            sys.modules['phi'] = module
            self.assertIs(importlib.import_module('phi'), module)
            for name in ('voice', 'clip', 'state'):
                self.assertTrue(hasattr(module, name), name)
        finally:
            if saved is None:
                sys.modules.pop('phi', None)
            else:
                sys.modules['phi'] = saved

    def test_install_exposes_public_api_only(self):
        module = types.ModuleType('phi_probe')
        exec(compile(_phi_source(), '<phi>', 'exec'), module.__dict__)
        script_globals = {}
        module.install(script_globals)
        for name in (
            'voice', 'clip', 'mix', 'fx', 'patch',
            'domain', 'var', 'state', 'every', 'after',
        ):
            self.assertIn(name, script_globals)
        # The host-facing sync helpers are deliberately not injected into the
        # performer's namespace.
        self.assertNotIn('_sync_create', script_globals)
        self.assertNotIn('_sync', script_globals)

    def test_bootstrapped_module_publishes_through_the_bus(self):
        fake_yse.reset()
        module = types.ModuleType('phi_probe2')
        exec(compile(_phi_source(), '<phi>', 'exec'), module.__dict__)
        module._sync_create('clip.intro')
        module.clip.intro.play()
        self.assertEqual(fake_yse.sent[-1], ('phi.ctl.clip.intro.play', 1))


if __name__ == '__main__':
    unittest.main()
