/// The source seeded into a fresh project's scratch script (`code.scratch`) —
/// and the fallback the Code surface loads when no project is wired (design
/// `docs/design/live-coding.md` §5: "the seeded scratch script keeps the surface
/// alive on a fresh project").
///
/// Idiomatic Python, not a DSL that doesn't exist yet — the point is a live,
/// evaluable script so a brand-new project's Code surface is never empty.
const String codeScratchSource = '''
# phi · scratchpad
# ctrl+enter evaluates the block under the cursor

import math

def gain(db):
    return 10 ** (db / 20)

print(gain(-6))
''';
