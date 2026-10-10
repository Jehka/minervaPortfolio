
# Phase 6 — SRAM Macro Integration

**Final phase of MINERVA.** Replaces the flop-based memory of Phase 5 with 3 kB
of OpenRAM macros from the sky130 PDK, hardened through LibreLane to a
signed-off GDS, closed at 45 MHz, and verified by gate-level simulation.

**Build of record:** `RUN_2026-10-10_12-08-55`

## Result

| Check                         | Result                                     |
| ----------------------------- | ------------------------------------------ |
| Magic DRC                     | **0**                                |
| KLayout DRC                   | **0**                                |
| Magic illegal overlap         | **0**                                |
| LVS                           | **0**                                |
| Antenna                       | **0**                                |
| Max fanout                    | **0**                                |
| Setup WNS, worst of 9 corners | **+1.702 ns** (`max_ss_100C_1v60`) |
| Hold WNS, worst of 9 corners  | **+0.200 ns** (`max_ss_100C_1v60`) |
| Gate-level simulation         | **PASS** — 10/10 result words       |

Setup and hold met at all nine PVT corners.

| Physical       |                                    |
| -------------- | ---------------------------------- |
| Clock          | 22 ns (**45 MHz**)           |
| Die area       | 1400 × 1400 µm (1,960,000 µm²) |
| Core area      | 1,911,350 µm²                    |
| Utilisation    | 46.2% total, 28.4% standard cells  |
| Standard cells | 69,978                             |
| Fill cells     | 254,106                            |
| SRAM macros    | 2                                  |
| Total power    | 25.5 mW                            |

Memory: `sky130_sram_2kbyte_1rw1r_32x512_8` as data memory,
`sky130_sram_1kbyte_1rw1r_32x256_8` as instruction memory.

For comparison, the Phase 5 flop-based build ran at 33 MHz with no hard macros.

![Hardened die, 1400 x 1400 um, with both SRAM macros](images/p6/die_macros.png)

*The full die. Both SRAM macros sit along the bottom with their pin rows facing
the standard cell field above; the keepout halos are the white margins around
them. Rendered with the PDK's KLayout layer properties — see Reproducing.*

## Gate-level verification

`scripts/gate_sim.sh` runs the Phase 5 campaign workload through the host
AXI4-Lite port against the post-route netlist, using the PDK's real behavioural
models for both macros — not the ports-only blackbox the linter and OpenSTA
use. All ten result words match the values the ZedBoard produced:

```
out[0] = fffffc18  ok      out[5] = 0000002a  ok
out[1] = fffffff9  ok      out[6] = 00001234  ok
out[2] = 00000000  ok      out[7] = 00007fff  ok
out[3] = 00000005  ok      out[8] = 000fe8de  ok
out[4] = 00000013  ok      out[9] = 600d1000  ok

==== PASS: the netlist executed the workload correctly ====
```

The verified netlist is `md5 067011cf52c0d713144234837f3c9fbd`, byte-identical
across the 31 ns and 22 ns builds (see *Frequency* below).

## The Magic / KLayout DRC discrepancy

Magic initially reported **8.4 million** DRC errors. KLayout, running the PDK's
signoff deck over the same GDS, reported **zero**.

The cause is a gap in Magic's sky130A rule deck, which carries no rules for the
SRAM macros. The macros are handed to Magic as `maglef` abstract views, and
geometry the deck has no rules for generates spurious violations rather than
being skipped.

Evidence:

- KLayout reads the full GDS with no abstraction mechanism, so it checked the
  macro internals and found nothing.
- With the macros abstracted (`MAGIC_DRC_MAGLEFS`), Magic also reports zero.
- An isolation test — hardening the macros alone — reproduced the error class
  without the rest of the design present.

Honest caveat: the two decks do not have identical rule coverage, so KLayout's
zero is strong corroboration rather than formal proof that the macro geometry
is clean. The documented deck gap, an independent signoff deck reporting zero,
and the isolation test together are what close the case.

## Three constraint bugs, all self-inflicted

Most of the time lost in this phase went to violations the design did not have.
All three were in `constraints.sdc`.

**1. `set_max_transition 0.75` against a library limit of 1.5 ns.**
`sky130_fd_sc_hd` declares `default_max_transition : 1.5`. The SDC held the
design to half that. The effect was not cosmetic: chasing a 0.75 ns target made
the resizer insert long series buffer chains on high-fanout nets, and every
buffer added delay to the critical path. Setting the limit to the library's own
value moved setup WNS from **−0.718 ns to +10.17 ns** — a 10.9 ns swing from
*relaxing* a constraint, because the constraint was causing the failure. Max
slew count fell 21,851 → 8,332.

**2. `set_max_fanout 10` with no library counterpart.**
`sky130_fd_sc_hd` declares no `default_max_fanout` at all — a style preference
reported as a rule failure. Removing it took the count from 2,398 to **0**. The
tell was that the count was bit-identical at all nine corners: a real timing
measurement varies with PVT, a netlist property compared against a constant
does not.

**3. `set_clock_uncertainty 0.25` applied to setup and hold alike.**
Sole cause of the last remaining violation. A setup check spans a launch edge
and a *different* capture edge, so it must absorb cycle-to-cycle jitter; a hold
check launches and captures on the *same* edge, so jitter largely cancels and
only skew and duty-cycle error remain. The single violator was an input-port
path:

```
[hold in-reg] cpu_hold -> _32517_/D : -0.043910
```

Against a clock tree insertion delay of 2.63 ns, the 0.25 ns uncertainty term
was six times larger than the violation. Splitting it:

```tcl
set_clock_uncertainty -setup 0.25 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]
```

recovered 200 ps and closed the path. Because clock uncertainty changes the
*check* and not the physical design, this was validated by re-running signoff
STA on the already-routed database — minutes instead of 2.5 hours.

## Floorplan

`DIE_AREA` was hard-coded at 1600 × 1600 and never revisited after SRAM macros
replaced the flop memory. Replacing 3 kB of flop storage with two hard blocks
deletes thousands of registers and their mux trees, so the same die now held far
less logic: **21.8% standard cell utilisation**, with 410,309 fill cells against
81,487 real ones.

Worse, `PL_TARGET_DENSITY_PCT` was **40** while the natural density was ~27%.
The target exceeded what the design could fill, so the placer packed to 40%
inside part of the core and left the rest as fill. The clustered, blob-shaped
placement was the placer satisfying the number it was given in the smallest area
that would do so — not disorder.

Shrunk to 1400 × 1400 with target density 45, macros repositioned to
`[67.56, 70]` and `[852.66, 70]`:

|                          | 1600 µm         | 1400 µm         |                    |
| ------------------------ | ---------------- | ---------------- | ------------------ |
| Die area                 | 2,560,000        | 1,960,000 µm²  | −23%              |
| Utilisation              | 36.6%            | 46.2%            |                    |
| **Standard cells** | **81,487** | **69,978** | **−11,509** |
| Fill cells               | 410,309          | 254,106          | −38%              |
| Est. wirelength          | 1,062,100        | 989,195          | −6.9%             |
| Max slew                 | 8,332            | 7,279            | −13%              |
| Setup WNS (at 31 ns)     | +10.170          | +10.702          |                    |
| Hold WNS                 | +0.156           | +0.200           |                    |

The smaller die did not merely pack the same netlist tighter — it produced a
**smaller netlist**. Those 11,509 cells were buffers the resizer no longer
needed, because the wires they drove got shorter. Same RTL, same constraints,
14% fewer cells, and both setup and hold improved simultaneously.

![Macro boundary: pin row, halo, and abutting standard cell rows](images/p6/sram_0_edge.png)

*Where the 2 kB macro meets the logic: the pin row along its top edge, the 30 um
keepout halo, and the standard cell rows abutting it.*

## Frequency

With setup at +10.70 ns on a 31 ns clock, the critical path was taking 20.3 ns
and being clocked at 31. The 31 ns was padding added to work around the setup
failure that turned out to be caused by the slew constraint, not the logic.

Rebuilt at 22 ns. The result is instructive: **the post-route netlist came back
byte-identical** (`md5 067011cf52c0d713144234837f3c9fbd`). Cell counts,
utilisation, wirelength, slew and cap counts and hold slack are identical to the
unit; setup dropped by exactly 9.0000 ns, the clock delta; and power rose by
1.4085× against a frequency ratio of 1.4091, which is dynamic power scaling on
an unchanged design.

Synthesis had no violation to chase at either target, so it produced the same
area-optimal netlist, and placement, CTS and routing are deterministic from
there. **45 MHz cost nothing in area or cells** — the design was always capable
of it. Only the dynamic power rose, proportionally, as it must.

Stopping at 22 ns is deliberate. 21 ns would leave +0.70, which is thin against
a macro model the PDK only characterises at the typical corner.

## The all-X writes: investigated and closed

Gate-level simulation logged two stores of all-X data to dmem words 74 and 75
(`0x128`, `0x12C`), just past the ten checked results — outside the window the
testbench verifies, which is why the run reported PASS.

Identical addresses and identical timestamps across two netlists differing by
11,509 cells ruled out synthesis: a flop inferred without a reset, or different
buffering, would have moved something.

They are **cache writebacks, not stores.** `sw/p5/workload_asic.S` ends with
three dummy loads at `0x1100`, `0x1110`, `0x1120` to evict the dirty output
lines, so the cache has 16-byte lines — and the SRAM writes in the log arrive in
groups of exactly four consecutive words, confirming it.

- Line 3 covers `0x120`–`0x12F` = words 72–75.
- The program writes `0x120` (checksum) and `0x124` (done marker) only.
- Words 74 and 75 are **padding**, never written by the workload.
- The testbench's clear phase zeroed words 64–73 only, so 74/75 were X in the
  SRAM model, which has no reset.

The workload is correct. Its bubble sort does write two words per pass while
advancing the pointer one, but with seven passes over an eight-element array it
stays inside `0x100`–`0x11C`.

That left one real question: did the cache *fetch* those words before writing
them back? If not — per-line dirty bits without per-word valid bits — it would
be writing back words it never owned, which would corrupt real data wherever
`0x128` held any.

**Tested and answered.** Extending the testbench clear loop to cover the full
three cache lines (12 words) and re-running, the final writeback now carries the
zeros placed there instead of X. The cache fetches the line on a write miss and
writes back faithfully. No bug — the X was uninitialised SRAM propagating
through a correctly-behaving cache.

## Corrections to earlier claims

**`docs/P5.md` max-slew explanation was wrong.** It attributed the large count
to `repair_design` using placement-estimated parasitics versus signoff STA using
extracted ones. The real cause was the two stages working to different *limits*
— 1.5 ns from the library versus 0.75 ns from the SDC. The flow behaved
correctly throughout; the earlier paragraph attributed a self-inflicted
constraint to a tool quirk. The same correction applies to the 45,418 count
reported for the Phase 5 flop build.

**Clock insertion delay is not floorplan-bound.** It was predicted to fall with
a smaller die; it rose slightly, 2.6286 → 2.6682 ns. Insertion delay is set by
how many buffer levels are needed to fan out to **5,234 clock terminals**, not
by physical distance — shrinking the die removes no levels. Reducing it would
need clock gating or a structured multi-level clock architecture, which is a
design change rather than a floorplan knob.

## Known limitations

**The SRAM macros ship with TT-only characterisation.** The PDK provides
`..._TT_1p8V_25C.lib` and no slow or fast corner libraries. Timing for any path
through these macros is therefore approximate at the eight non-typical corners:
the macro is modelled typical while the surrounding logic and clock tree are
modelled at their actual corner. This also explains why hold was initially
tightest at the *slow* corner rather than the fast one, which is backwards for a
conventional design. Nine-corner closure here means closure against the best
model the PDK provides, not full multi-corner characterisation.

**7,279 max-slew and 281 max-cap pins remain** as non-blocking warnings against
real library limits. These are genuine transition-time violations driven by long
interconnect at the slow corner and a 5,234-terminal clock net. They are
deliberately not driven to zero: the direct remedy is a tighter slew target, and
that is exactly what was consuming 10.9 ns of setup slack before. The trade-off
is recorded rather than hidden behind a constraint that makes the number look
better.

**`PDN-0110`**: no via inserted between met4 and met5 at (942.64, 487.18), just
above the 1 kB macro's top edge, where a power strap crosses the macro boundary.
DRC and LVS pass, so nothing is malformed, but power delivery there is slightly
weaker than intended — a minor cost of the tighter floorplan.

**IR drop is not characterised.** `VSRC_LOC_FILES` is unset, so the IR drop
report is indicative only.

**I/O timing is assumed, not budgeted.** Input and output delays are 2.0 ns with
`sky130_fd_sc_hd__inv_2` drivers and 0.02 pF loads. There is no chip-level
interface specification behind these numbers; they are block-level placeholders.

**Routing headroom is finite.** `DRT-0120` large-net warnings roughly doubled
(104 → 236) going from 37% to 46% utilisation. Not an error, but the direction
that ends in routing failure if the die were pushed much below 1400 µm on five
routable metal layers with two hard macros.

## Reproducing

Full hardening run (~2 h):

```bash
librelane asic/config_sram.json
```

Signoff STA alone, against an existing routed run (minutes — valid for any
change that affects the check rather than the silicon, such as clock
uncertainty):

```bash
librelane --last-run --from OpenROAD.STAPostPNR asic/config_sram.json
```

Gate-level simulation:

```bash
./scripts/gate_sim.sh RUN_2026-10-10_12-08-55
```

Layout images:

```bash
klayout -z -nc \
  -rd gds=asic/runs/RUN_2026-10-10_12-08-55/final/gds/minerva_asic_top.gds \
  -rd outdir=docs/images/p6 \
  -rd lyp=$PDK_ROOT/libs.tech/klayout/tech/sky130A.lyp \
  -r scripts/gds_shots.py
```

The `.lyp` is required: without it KLayout auto-assigns colours from a narrow
fallback palette and the whole layer stack renders as shades of green.

## Project status

MINERVA is complete at Phase 6. No further development is planned. The core
remains available for reuse — a hardened RV32I core with real SRAM macros and a
signed-off sky130 implementation at 45 MHz — should a later project want a CPU
to build on.
