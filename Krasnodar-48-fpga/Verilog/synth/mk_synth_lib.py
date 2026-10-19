#!/usr/bin/env python3
"""Write lib/ttl.v + lib/cmos4000.v for synthesis: drop the parts that
counters_sync.v replaces, and swap in the synchronous models from
sync_overrides.v, so yosys sees exactly one definition of each module."""
import re, sys
REPLACED = ('ttl_74193', 'cd4520', 'ttl_7474')
over = open('sync_overrides.v', encoding='utf-8').read()
OVERRIDDEN = tuple(re.findall(r'^module\s+(\w+)', over, flags=re.M))
out = []
for f in ('../lib/ttl.v', '../lib/cmos4000.v'):
    s = open(f, encoding='utf-8').read()
    for name in REPLACED + OVERRIDDEN:
        s = re.sub(r'module\s+' + name + r'\b.*?endmodule\s*', '', s, flags=re.S)
    out.append(s)
out.append(over)
open(sys.argv[1] if len(sys.argv) > 1 else 'lib_sync.v', 'w',
     encoding='utf-8').write('\n'.join(out))
