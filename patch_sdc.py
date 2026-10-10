#!/usr/bin/env python3
"""Patch asic/constraints.sdc for the 32 MHz + library-limits run.

Strict by design: it will not write anything unless it finds every line it
expects. Better to refuse and tell you than to half-edit an SDC, because a
silently wrong SDC is exactly what cost us two identical 100-minute runs
earlier in this project.

Changes:
  clk_period        20.0 or 30.0  ->  31.0   (32 MHz; covers the 0.718 ns
                                              setup gap at max_ss)
  set_max_transition  0.75        ->  1.5    (sky130_fd_sc_hd's own
                                              default_max_transition)
  set_max_capacitance             ->  removed (liberty carries per-pin
                                              max_capacitance already)
  set_max_fanout                  ->  removed (no default_max_fanout exists
                                              in the library at all)

Run from the repo root:  python3 patch_sdc.py
"""
import re, sys, shutil, difflib, os

P = "asic/constraints.sdc"
if not os.path.exists(P):
    sys.exit(f"not found: {P} (run this from the repo root)")

orig = open(P).read()
new = orig
notes = []

# --- clock period -----------------------------------------------------------
m = re.search(r'^(\s*set\s+clk_period\s+)([0-9.]+)\s*$', new, re.M)
if not m:
    sys.exit("could not find a 'set clk_period <n>' line -- not patching. "
             "Paste the file and I'll do it by hand.")
old_p = m.group(2)
new = new[:m.start()] + f"{m.group(1)}31.0" + new[m.end():]
notes.append(f"clk_period {old_p} -> 31.0")

# --- max_transition ---------------------------------------------------------
m = re.search(r'^(\s*set_max_transition\s+)([0-9.]+)(.*)$', new, re.M)
if m:
    old_t = m.group(2)
    new = new[:m.start()] + f"{m.group(1)}1.5{m.group(3)}" + new[m.end():]
    notes.append(f"set_max_transition {old_t} -> 1.5")
else:
    notes.append("no set_max_transition found (library default 1.5 applies)")

# --- drop the two self-imposed limits --------------------------------------
for cmd in ("set_max_capacitance", "set_max_fanout"):
    pat = re.compile(r'^.*\b' + cmd + r'\b.*\n', re.M)
    hits = pat.findall(new)
    if hits:
        new = pat.sub("", new)
        notes.append(f"removed {len(hits)} {cmd} line(s)")
    else:
        notes.append(f"no {cmd} line to remove")

if new == orig:
    sys.exit("nothing changed -- file may already be patched.")

shutil.copy(P, P + ".bak")
open(P, "w").write(new)

print("\n".join("  " + n for n in notes))
print(f"\nbackup: {P}.bak\n")
print("".join(difflib.unified_diff(
    orig.splitlines(True), new.splitlines(True),
    fromfile=P + " (before)", tofile=P + " (after)")))