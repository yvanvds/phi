/// Seed source loaded into the Code surface on first mount.
///
/// Demonstrates the editor without leaning on a DSL that doesn't exist
/// yet — keep it idiomatic Python. The block splitter must produce
/// exactly three blocks for the widget test to assert against.
const String codeSurfaceSeed = '''
# phi · scratchpad
# ctrl+enter evaluates the block under the cursor

import math

def gain(db):
    return 10 ** (db / 20)

print(gain(-6))
''';
