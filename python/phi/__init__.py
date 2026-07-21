"""The ``phi`` live-coding library — the friendly object layer over the engine
bus.

Design: ``docs/design/live-coding.md`` §3, §4 (epic #228, issue #230).

Shipped as **plain Python source** in the Phi repo (review decision 4) and
exec'd into the engine's embedded CPython at boot. The host then keeps the
name table in sync with the Dart registry by calling the ``_sync_*`` functions
(issue #231), and the performer types verb-first vocabulary against dot-access
namespaces::

    pad = voice.bells            # bind the entry, not the address
    every(1, lambda: pad.note(60))
    mix.pads.fade(0.6, 4)        # fade volume over four ticks
    clip.drums.intro_fill.play()
    var.section = "b"

Two command planes, both invisible at the call site (design §4):

* **Engine-direct** — ``mix``/``patch`` publish straight to an engine-owned
  bus prefix (``channel.<addr>.<param>`` / ``patcher.<addr>.<slot>``); the
  engine consumes them with no host round-trip.
* **Host-mediated** — every structural verb (clip play/stop/pause/loop, voice
  note/off, ``state.fire``, ``var`` assignment, ``domain`` tempo, ``fx``
  params) publishes to the reserved ``phi.ctl.*`` prefix; the host taps that
  address and dispatches to the owning controller (issue #233).

**Rename-following by construction.** A proxy references a *table entry* (a
mutable object), never an address string. When ``_sync`` mutates an entry's
address in place — a rename or regroup — every bound proxy follows, so a
running script survives a rename mid-performance ("resolve once, bind the
object").

Boot / bootstrap (the host does this once via ``LiveCoding.run``; issue #232)::

    import sys, types
    mod = types.ModuleType('phi')
    exec(PHI_SOURCE, mod.__dict__)   # PHI_SOURCE = this file's text
    sys.modules['phi'] = mod         # so ``import phi`` works
    mod.install(script_globals)      # expose voice/clip/... at global scope
"""

import sys

__all__ = [
    'voice',
    'clip',
    'mix',
    'fx',
    'patch',
    'domain',
    'var',
    'state',
    'every',
    'after',
]

#: The eight dot-access namespaces mirroring the registry (design §3).
NAMESPACES = ('voice', 'clip', 'mix', 'fx', 'patch', 'domain', 'var', 'state')

#: Reserved host-mediated control-plane prefix (design §4).
CTL_PREFIX = 'phi.ctl'

#: Engine-owned bus prefixes per engine-direct kind (design §2, §4).
_ENGINE_PREFIX = {'mix': 'channel', 'patch': 'patcher'}

#: The single implicit parameter for kinds whose verbs take a value with no
#: explicit slot (a mix strip's only continuous parameter is its volume).
_DEFAULT_PARAM = {'mix': 'volume'}


# --------------------------------------------------------------------------- #
# The bus handle                                                              #
# --------------------------------------------------------------------------- #
_yse = None


def _bus():
    """Return the live ``yse`` bus module.

    Resolved lazily from ``sys.modules`` on every call so the engine's real
    module and a test's fake are equally reachable, and swapping the fake
    between tests just works.
    """
    global _yse
    mod = sys.modules.get('yse')
    if mod is not None:
        return mod
    if _yse is not None:
        return _yse
    try:
        import yse as resolved  # noqa: WPS433 (deliberate lazy import)
    except Exception as exc:  # pragma: no cover - only when the engine is absent
        raise RuntimeError('phi: the yse bus module is not available') from exc
    _yse = resolved
    return resolved


# --------------------------------------------------------------------------- #
# The name table                                                             #
# --------------------------------------------------------------------------- #
class _Entry:
    """One node in the name table — a registry entity or group.

    The **address is mutable**: ``_sync`` rewrites it in place on a rename or
    regroup, which is exactly what lets a bound proxy follow the change.
    """

    __slots__ = ('address', 'kind', 'children', 'params')

    def __init__(self, address, kind):
        self.address = address
        self.kind = kind
        self.children = {}  # name -> _Entry (insertion-ordered)
        self.params = {}  # param -> last value published (mix / fx / patch)


_roots = {name: _Entry(name, name) for name in NAMESPACES}


def _split(address):
    parts = address.split('.')
    return parts[0], parts[1:]


def _join(head, tail):
    return head + '.' + tail


def _strip_kind(address):
    """Drop the leading ``<kind>.`` — the entity address the engine prefix
    expects (``mix.drums.sub`` -> ``drums.sub``)."""
    _, path = _split(address)
    return '.'.join(path)


def _find(address):
    kind, path = _split(address)
    node = _roots.get(kind)
    for seg in path:
        if node is None:
            return None
        node = node.children.get(seg)
    return node


def _ensure_group(kind, path):
    """Walk/create the intermediate groups for ``path`` under ``kind`` and
    return the deepest node."""
    node = _roots[kind]
    acc = kind
    for seg in path:
        acc = _join(acc, seg)
        child = node.children.get(seg)
        if child is None:
            child = _Entry(acc, kind)
            node.children[seg] = child
        node = child
    return node


# --------------------------------------------------------------------------- #
# The _sync protocol (host -> interpreter; issue #231 drives it)             #
# --------------------------------------------------------------------------- #
def _sync_create(address):
    """Add ``address`` to the table (creating any missing parent groups)."""
    kind, path = _split(address)
    return _ensure_group(kind, path)


def _sync_delete(address):
    """Remove ``address`` (and its subtree) from the table."""
    kind, path = _split(address)
    if not path:
        return
    parent = _roots[kind]
    for seg in path[:-1]:
        parent = parent.children.get(seg)
        if parent is None:
            return
    parent.children.pop(path[-1], None)


def _rebase(entry, new_address):
    """Rewrite ``entry``'s address (and every descendant's) **in place**."""
    entry.address = new_address
    entry.kind = _split(new_address)[0]
    for name, child in entry.children.items():
        _rebase(child, _join(new_address, name))


def _move(old_address, new_address):
    """Move an existing entry to ``new_address``, mutating the *same* entry
    object in place so bound proxies follow. Rename (same parent) and regroup
    (new parent) are the same operation over the table."""
    entry = _find(old_address)
    if entry is None:
        # Tolerate a move of something we never saw — best-effort resync.
        return _sync_create(new_address)

    okind, opath = _split(old_address)
    old_parent = _roots[okind]
    for seg in opath[:-1]:
        old_parent = old_parent.children[seg]
    old_parent.children.pop(opath[-1], None)

    nkind, npath = _split(new_address)
    new_parent = _ensure_group(nkind, npath[:-1])
    new_parent.children[npath[-1]] = entry
    _rebase(entry, new_address)
    return entry


#: Rename and regroup share ``_move`` but stay distinct entry points so the
#: host mirror's ``onRename`` / ``onRegroup`` classification maps 1:1.
_sync_rename = _move
_sync_regroup = _move


def _collect(entry, out):
    for child in entry.children.values():
        out[child.address] = child
        _collect(child, out)


def _sync_replace(addresses):
    """Full-table replace (boot sync / re-init re-sync, issue #231).

    Rebuilds the table from ``addresses`` while **preserving surviving entry
    objects** — so a proxy bound before a full re-sync keeps following as long
    as its address still exists.
    """
    survivors = {}
    for root in _roots.values():
        _collect(root, survivors)
    for root in _roots.values():
        root.children.clear()

    # Shallowest first, so a parent group is rebuilt before its children.
    for address in sorted(addresses, key=lambda a: a.count('.')):
        kind, path = _split(address)
        if kind not in _roots:
            continue
        node = _roots[kind]
        acc = kind
        for seg in path:
            acc = _join(acc, seg)
            child = node.children.get(seg)
            if child is None:
                child = survivors.get(acc)
                if child is not None:
                    child.children.clear()  # repopulated by deeper addresses
                    child.address = acc
                    child.kind = kind
                else:
                    child = _Entry(acc, kind)
                node.children[seg] = child
            node = child


def _reset():
    """Clear the whole table — test/boot convenience."""
    for root in _roots.values():
        root.children.clear()
        root.params.clear()


# --------------------------------------------------------------------------- #
# Emission helpers                                                            #
# --------------------------------------------------------------------------- #
def _emit_ctl(subaddress, value):
    """Host-mediated publish to ``phi.ctl.<subaddress>``."""
    _bus().send(_join(CTL_PREFIX, subaddress), value)


def _emit_engine(entry, param, value):
    """Engine-direct publish to ``<prefix>.<entity>.<param>``."""
    body = _strip_kind(entry.address)
    if not body:
        raise TypeError(
            'cannot set %r on the %s namespace root' % (param, entry.kind),
        )
    entry.params[param] = float(value)
    _bus().send(
        '%s.%s.%s' % (_ENGINE_PREFIX[entry.kind], body, param),
        float(value),
    )


def _emit_param(entry, param, value):
    """Route a parameter set to the right plane for ``entry``'s kind."""
    if entry.kind in _ENGINE_PREFIX:
        _emit_engine(entry, param, value)
    else:  # fx (and any future param-bearing host-mediated kind)
        entry.params[param] = float(value)
        _emit_ctl(_join(entry.address, param), float(value))


def _schedule_set(entry, param, value, beat):
    _bus().schedule(beat, lambda bound=value: _emit_param(entry, param, bound))


# --------------------------------------------------------------------------- #
# The proxy                                                                   #
# --------------------------------------------------------------------------- #
class _Proxy:
    """A dot-access handle onto a name-table entry.

    Namespace roots, groups, and leaves are all the same class — differentiated
    only by the entry they wrap. Verbs are real methods (so attribute lookup
    finds them before ``__getattr__``); any other name resolves to a child
    entry, which is what makes ``clip.drums.intro_fill`` and ``dir(clip)`` work.

    Every verb reads ``self._entry.address`` **at call time**, so a rename that
    mutated the entry in place is already reflected.
    """

    __slots__ = ('_entry',)

    def __init__(self, entry):
        object.__setattr__(self, '_entry', entry)

    # -- navigation / introspection ---------------------------------------- #
    def __getattr__(self, name):
        # Reached only for names normal lookup missed → treat as a child entry.
        if name.startswith('_'):
            raise AttributeError(name)
        entry = object.__getattribute__(self, '_entry')
        child = entry.children.get(name)
        if child is None:
            raise AttributeError(
                '%r has no member %r' % (entry.address, name),
            )
        return _Proxy(child)

    def __dir__(self):
        entry = object.__getattribute__(self, '_entry')
        return sorted(set(entry.children) | set(_VERB_NAMES))

    def __iter__(self):
        entry = object.__getattribute__(self, '_entry')
        for child in entry.children.values():
            yield _Proxy(child)

    def __len__(self):
        return len(object.__getattribute__(self, '_entry').children)

    def __contains__(self, name):
        return name in object.__getattribute__(self, '_entry').children

    def __repr__(self):
        entry = object.__getattribute__(self, '_entry')
        return '<phi %s:%s>' % (entry.kind, entry.address)

    # -- assignment sugar (engine-direct + host-mediated params) ----------- #
    def __setattr__(self, name, value):
        entry = object.__getattribute__(self, '_entry')
        kind = entry.kind
        if kind in _ENGINE_PREFIX:  # mix.pads.volume = 0.6 / patch.swirl.cut = ..
            _emit_engine(entry, name, value)
        elif kind == 'fx':
            _emit_param(entry, name, value)
        elif kind == 'domain':  # domain.drum.tempo = 124
            _emit_ctl(_join(entry.address, name), float(value))
        elif kind == 'var':  # var.section = "b"
            _emit_ctl(_join(entry.address, name), value)
        else:
            raise AttributeError(
                'cannot assign %r on the %s namespace (use a verb)'
                % (name, kind),
            )

    # -- clip / group verbs ------------------------------------------------ #
    def play(self):
        _emit_ctl(_join(self._entry.address, 'play'), 1)

    def stop(self):
        _emit_ctl(_join(self._entry.address, 'stop'), 1)

    def pause(self):
        _emit_ctl(_join(self._entry.address, 'pause'), 1)

    def loop(self, on=True):
        _emit_ctl(_join(self._entry.address, 'loop'), 1 if on else 0)

    # -- voice verbs ------------------------------------------------------- #
    def note(self, pitch, velocity=100):
        _emit_ctl(
            _join(self._entry.address, 'note'),
            [float(pitch), float(velocity)],
        )

    def off(self, pitch=None):
        payload = [] if pitch is None else [float(pitch)]
        _emit_ctl(_join(self._entry.address, 'off'), payload)

    # -- state verb -------------------------------------------------------- #
    def fire(self, target):
        _emit_ctl(_join(self._entry.address, 'fire'), str(target))

    # -- mix / fx / patch parameter verbs ---------------------------------- #
    def set(self, *args):
        entry = self._entry
        if len(args) == 1:
            param = _DEFAULT_PARAM.get(entry.kind)
            if param is None:
                raise TypeError('%s.set expects (slot, value)' % entry.kind)
            value = args[0]
        elif len(args) == 2:
            param, value = args
        else:
            raise TypeError('set expects (value) or (slot, value)')
        _emit_param(entry, param, value)

    #: ``patch.swirl.send("cutoff", 0.4)`` reads naturally for a patcher slot;
    #: it is an alias of ``set`` (design §4).
    send = set

    def fade(self, *args):
        entry = self._entry
        if len(args) == 2:
            param = _DEFAULT_PARAM.get(entry.kind)
            if param is None:
                raise TypeError(
                    '%s.fade expects (slot, target, ticks)' % entry.kind,
                )
            target, ticks = args
        elif len(args) == 3:
            param, target, ticks = args
        else:
            raise TypeError(
                'fade expects (target, ticks) or (slot, target, ticks)',
            )
        ticks = int(ticks)
        if ticks < 1:
            raise ValueError('fade ticks must be >= 1')
        start = float(entry.params.get(param, 0.0))
        target = float(target)
        for step in range(1, ticks + 1):
            value = start + (target - start) * (step / ticks)
            _schedule_set(entry, param, value, step)
        entry.params[param] = target


#: Verb names surfaced in ``dir()`` so in-script exploration matches the
#: editor's static method table (design §6).
_VERB_NAMES = (
    'play',
    'stop',
    'pause',
    'loop',
    'note',
    'off',
    'fire',
    'set',
    'send',
    'fade',
)


# --------------------------------------------------------------------------- #
# every / after — sugar over yse.schedule (design §3)                        #
# --------------------------------------------------------------------------- #
def after(beats, fn):
    """Run ``fn`` once after ``beats`` (domain beats/ticks)."""
    return _bus().schedule(beats, fn)


def every(beats, fn):
    """Run ``fn`` every ``beats``, rescheduling itself after each firing."""

    def _tick():
        fn()
        _bus().schedule(beats, _tick)

    return _bus().schedule(beats, _tick)


# --------------------------------------------------------------------------- #
# Namespace proxies + bootstrap install                                      #
# --------------------------------------------------------------------------- #
voice = _Proxy(_roots['voice'])
clip = _Proxy(_roots['clip'])
mix = _Proxy(_roots['mix'])
fx = _Proxy(_roots['fx'])
patch = _Proxy(_roots['patch'])
domain = _Proxy(_roots['domain'])
var = _Proxy(_roots['var'])
state = _Proxy(_roots['state'])


def install(namespace):
    """Expose the public API (namespaces + ``every``/``after``) into a target
    globals dict — the live script namespace. The host calls this once after
    exec'ing the module so bare ``voice`` / ``clip`` / ... work in scripts."""
    module_globals = globals()
    for name in __all__:
        namespace[name] = module_globals[name]
    return namespace
