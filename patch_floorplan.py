#!/usr/bin/env python3
"""Shrink the MINERVA P6 die and re-place the SRAM macros for it.

Strict by design: it verifies every value it expects to find before writing
anything, and recomputes the macro fit from the LEF footprints rather than
trusting hard-coded coordinates. A floorplan that is wrong costs 2.5 hours to
discover, so this would rather refuse than guess.

Run from the repo root:  python3 patch_floorplan.py

WHAT CHANGES AND WHY
--------------------
DIE_AREA  1600x1600 -> 1400x1400
    The die was hard-coded and never revisited after SRAM macros replaced the
    flop memory, which deleted most of the standard cell content. Core area
    goes 2,506,550 -> ~1,912,689 um^2; total utilisation 36.6% -> ~53%.

PL_TARGET_DENSITY_PCT  40 -> 45
    This is what actually caused the clustered placement. Standard cells
    occupy ~546,428 um^2; on the old core that is a natural density of ~27%,
    so a target of 40 let the placer satisfy itself inside roughly half the
    die and leave the rest as fill. On the new die natural density is ~41%,
    so 45 sits just above it and the placer must use nearly the whole core.

Macro locations
    Repositioned for the smaller die and centred as a pair along the bottom,
    with a ~102 um channel between them for the macro-to-core routing. Moving
    these is NOT optional: the old coordinates (120,120) and (900,120) put the
    1 kB macro's right edge at 1379.8 um, which on a 1400 um die leaves no
    room for its 30 um halo.

NOT CHANGED: clock period, SDC, hold margins. Those are closed and verified;
one variable at a time. If the tighter floorplan improves slew and clock
insertion delay, that shows up cleanly on its own.
"""
import json, os, shutil, sys

CFG = "asic/config_sram.json"

DIE = 1400.0
HALO = 30.0
CHANNEL = 102.0          # gap between the two macros
BOTTOM = 70.0            # macro bottom edge

# (cell name, width, height) straight from the PDK LEF SIZE lines
DMEM = ("sky130_sram_2kbyte_1rw1r_32x512_8", 683.10, 416.54)
IMEM = ("sky130_sram_1kbyte_1rw1r_32x256_8", 479.78, 397.50)

if not os.path.exists(CFG):
    sys.exit(f"not found: {CFG} (run this from the repo root)")

cfg = json.load(open(CFG))

# ---- verify what we expect to be true before touching anything -------------
if cfg.get("DIE_AREA") != [0, 0, 1600, 1600]:
    sys.exit(f"DIE_AREA is {cfg.get('DIE_AREA')}, expected [0,0,1600,1600] -- "
             "already patched, or not the config I was shown. Not writing.")
if cfg.get("FP_SIZING") != "absolute":
    sys.exit("FP_SIZING is not 'absolute'; DIE_AREA would be ignored. Stopping.")
for name, _, _ in (DMEM, IMEM):
    if name not in cfg.get("MACROS", {}):
        sys.exit(f"MACROS has no entry for {name}. Stopping.")

# ---- compute the placement and check it fits -------------------------------
span = DMEM[1] + CHANNEL + IMEM[1]
left = round((DIE - span) / 2.0, 2)
dmem_x, imem_x = left, round(left + DMEM[1] + CHANNEL, 2)

checks = [
    ("dmem left halo",   dmem_x - HALO,                     lambda v: v > 0),
    ("imem right halo",  DIE - (imem_x + IMEM[1] + HALO),   lambda v: v > 0),
    ("bottom halo",      BOTTOM - HALO,                     lambda v: v > 0),
    ("inter-macro gap",  CHANNEL - 2 * HALO,                lambda v: v > 0),
    ("dmem top halo",    DIE - (BOTTOM + DMEM[2] + HALO),   lambda v: v > 0),
]
print("fit checks (all must be positive):")
bad = False
for label, val, ok in checks:
    flag = "ok " if ok(val) else "FAIL"
    print(f"  {flag} {label:18s} {val:8.2f} um")
    bad = bad or not ok(val)
if bad:
    sys.exit("macro placement does not fit the requested die. Not writing.")

macro_area = DMEM[1] * DMEM[2] + IMEM[1] * IMEM[2]
std_area = 546428.0                       # 0.218 * old core area
core = (DIE - 17.0) ** 2                  # same die->core margin as before
print(f"\nmacro area      {macro_area:12,.0f} um^2")
print(f"stdcell area    {std_area:12,.0f} um^2")
print(f"new core area   {core:12,.0f} um^2")
print(f"new utilisation {(macro_area + std_area) / core * 100:12.1f} %  (was 36.6)")

# ---- write -----------------------------------------------------------------
shutil.copy(CFG, CFG + ".bak")

cfg["DIE_AREA"] = [0, 0, int(DIE), int(DIE)]
cfg["PL_TARGET_DENSITY_PCT"] = 45
cfg["//floorplan"] = (
    "Die shrunk 1600->1400 and target density 40->45 after P6 showed 21.8% "
    "standard-cell utilisation. The old die was sized for the flop build; "
    "replacing flop memory with SRAM macros deleted most of the standard "
    "cell content and the die was never revisited. The clustered placement "
    "was caused by the density target (40) exceeding the natural density "
    "(~27%) -- the placer packed to 40% in part of the core and left the "
    "rest as fill. Macro coordinates are recomputed for the smaller die; "
    "the old ones put the 1kB macro 20 um from the new die edge."
)

for (name, w, h), x in ((DMEM, dmem_x), (IMEM, imem_x)):
    insts = cfg["MACROS"][name]["instances"]
    key = next(iter(insts))
    old = insts[key]["location"]
    insts[key]["location"] = [x, BOTTOM]
    print(f"  {key}: {old} -> [{x}, {BOTTOM}]")

json.dump(cfg, open(CFG, "w"), indent=2)
json.load(open(CFG))          # re-read to prove it is valid JSON
print(f"\nwrote {CFG}  (backup at {CFG}.bak)")