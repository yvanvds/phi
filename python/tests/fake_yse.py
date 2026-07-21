"""A fake ``yse`` bus module for the phi library tests.

Stands in for the engine's embedded bus DSL (``docs/design/live-coding.md``
§2). It records every ``send`` as an ``(address, value)`` pair and every
``schedule`` as a pending callback, so a test can submit phi verbs and assert
on exactly the addresses and values that reached the bus — the "submit source,
assert published addresses/values" contract from issue #230.
"""

#: Every ``(address, value)`` handed to :func:`send`, in order.
sent = []

#: Pending scheduled callbacks: list of ``{'beat': ..., 'fn': ...}``.
scheduled = []


def send(address, value):
    """Record an immediate bus publish."""
    sent.append((address, value))


def schedule(beat, fn):
    """Queue ``fn`` to run at ``beat``; returns the pending record."""
    record = {'beat': beat, 'fn': fn}
    scheduled.append(record)
    return record


def fire_due():
    """Fire every currently-scheduled callback once (snapshot first, so a
    callback that reschedules itself — ``every`` — is captured freshly)."""
    due = list(scheduled)
    scheduled.clear()
    for record in due:
        record['fn']()


def reset():
    """Forget all recorded sends and pending schedules."""
    sent.clear()
    scheduled.clear()
