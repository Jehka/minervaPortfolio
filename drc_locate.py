#!/usr/bin/env python3
"""Classify Magic DRC violations by whether they fall inside a macro footprint.

    python3 drc_locate.py <drc.magic.rpt>

The sky130 OpenRAM macros are pre-hardened IP: their internal geometry was
signed off by whoever built them, with their own ruleset. When Magic re-checks
them in context it re-reports every bitcell-level rule, which is why a design
whose flop-memory build had 0 violations suddenly reports millions.

The number that actually matters is violations OUTSIDE the macro footprints --
those are in geometry this flow generated and they are the ones that count.
"""
import re, sys
from collections import Counter

# Macro placements from asic/config_sram.json, sizes from the PDK LEFs.
MACROS = {
    "dmem 2KB (sky130_sram_2kbyte_1rw1r_32x512_8)": (120.0, 120.0, 120.0 + 683.10, 120.0 + 416.54),
    "imem 1KB (sky130_sram_1kbyte_1rw1r_32x256_8)": (900.0, 120.0, 900.0 + 479.78, 120.0 + 397.50),
}

COORD = re.compile(
    r"^\s*([-\d.]+)um\s+([-\d.]+)um\s+([-\d.]+)um\s+([-\d.]+)um\s*$")

def inside(x1, y1, x2, y2, box):
    bx1, by1, bx2, by2 = box
    return x1 >= bx1 and y1 >= by1 and x2 <= bx2 and y2 <= by2

def main(path):
    rule = "(none)"
    total = 0
    in_macro = Counter()
    outside = []
    outside_rules = Counter()

    with open(path, errors="replace") as fh:
        for line in fh:
            m = COORD.match(line)
            if not m:
                t = line.strip()
                # Rule descriptions are the non-separator, non-coordinate lines.
                if t and not t.startswith("-") and not t.startswith("["):
                    rule = t
                continue
            total += 1
            x1, y1, x2, y2 = (float(v) for v in m.groups())
            for name, box in MACROS.items():
                if inside(x1, y1, x2, y2, box):
                    in_macro[name] += 1
                    break
            else:
                outside.append((rule, x1, y1, x2, y2))
                outside_rules[rule] += 1

    print("Magic DRC violations: %d total\n" % total)
    for name, n in in_macro.most_common():
        print("  %7d  inside %s" % (n, name))
    print("  %7d  OUTSIDE every macro footprint" % len(outside))

    if outside:
        print("\nThese are the ones that matter -- top rules:")
        for rule, n in outside_rules.most_common(15):
            print("  %6d  %s" % (n, rule))
        print("\nFirst 20 by location:")
        for rule, x1, y1, x2, y2 in outside[:20]:
            print("  (%8.3f, %8.3f)  %s" % (x1, y1, rule))
    else:
        print("\nEvery violation is inside a pre-hardened macro.")
        print("Nothing this flow generated violates a design rule.")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])