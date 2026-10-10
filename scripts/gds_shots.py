# gds_shots.py -- batch KLayout screenshots of a GDS, no GUI fiddling.
#
#   klayout -z -nc -rd gds=<layout.gds> -rd outdir=docs/images \
#           -r scripts/gds_shots.py
#
#   optional:  -rd lyp=<path to sky130A.lyp>   (otherwise auto-located)
#              -rd pdk=<path to sky130A>       (otherwise $PDK_ROOT)
#
# -z  : no main window shown (a view still exists, so images still render)
# -nc : ignore the user's saved configuration, so results are reproducible
#
# Paths come through -rd, which defines them as variables before the script
# runs. KLayout does NOT put the layout path in sys.argv, and under -z anything
# printed to stdout is swallowed -- a script that fails on sys.argv therefore
# dies in complete silence. Hence -rd for the inputs and stderr for progress.
#
# ---------------------------------------------------------------- COLOUR ---
# A bare GDS carries geometry and layer NUMBERS, no appearance. With no
# technology attached KLayout auto-assigns colours from a fallback palette
# that cycles through a narrow range, so a sixteen-layer stack renders as
# sixteen shades of green and reads as a solid mass. The PDK's own .lyp file
# defines the canonical colour and hatch for each sky130 layer; loading it is
# what produces the familiar multi-colour layout view. This is purely display
# -- the geometry is identical either way.
#
# ----------------------------------------------------------------- ZOOM ----
# Window sizes here are tuned for a ~1600 um die rendered at 2400 px. The rule
# that matters: a standard cell is roughly 1-5 um wide, so a 400 um window
# gives it about 6 px and every structure averages into texture. Keep close-up
# windows at 40-120 um. Wider than that is a texture swatch, not a layout.
#
# Close-ups are also framed ABOVE A MACRO rather than at the die centre. On a
# macro-dominated floorplan the geometric centre tends to land in fill, which
# renders as a uniform field; the congested routing above a macro is where
# there is something to look at.

import pya
import sys
import os
import glob

try:
    gds
except NameError:
    sys.stderr.write("usage: klayout -z -nc -rd gds=FILE [-rd outdir=DIR] "
                     "[-rd lyp=FILE] [-rd pdk=DIR] -r gds_shots.py\n")
    raise SystemExit(1)

try:
    outdir
except NameError:
    outdir = "docs/images"

outdir = os.path.abspath(outdir)
os.makedirs(outdir, exist_ok=True)

W = H = 2400          # output resolution, square

mw = pya.Application.instance().main_window()
mw.load_layout(gds, 1)
view = mw.current_view()
view.max_hier()
sys.stderr.write("loaded %s\n" % gds)

# ------------------------------------------------------- layer properties ---
def find_lyp():
    try:
        return lyp                      # explicit -rd lyp=
    except NameError:
        pass
    try:
        root = pdk                      # explicit -rd pdk=
    except NameError:
        root = os.environ.get("PDK_ROOT", "")
        if root and not root.rstrip("/").endswith("sky130A"):
            # PDK_ROOT sometimes points one level above the variant dir
            cand = os.path.join(root, "sky130A")
            if os.path.isdir(cand):
                root = cand
    if not root:
        return None
    patterns = [
        os.path.join(root, "libs.tech", "klayout", "tech", "sky130A.lyp"),
        os.path.join(root, "libs.tech", "klayout", "sky130A.lyp"),
        os.path.join(root, "libs.tech", "klayout", "**", "*.lyp"),
    ]
    for p in patterns:
        hits = sorted(glob.glob(p, recursive=True))
        if hits:
            return hits[0]
    return None


lyp_path = find_lyp()
if lyp_path and os.path.isfile(lyp_path):
    view.load_layer_props(lyp_path)
    sys.stderr.write("layer properties: %s\n" % lyp_path)
else:
    sys.stderr.write("WARNING: no .lyp found -- images will use KLayout's\n"
                     "         fallback palette and look near-monochrome.\n"
                     "         Pass -rd lyp=/path/to/sky130A.lyp to fix.\n")

# ---------------------------------------------------------------- layers ---
NWELL = (64, 20)
DIFF  = (65, 20)
TAP   = (65, 44)
POLY  = (66, 20)
LICON = (66, 44)
NPC   = (95, 20)
LI1   = (67, 20)
MCON  = (67, 44)
MET1  = (68, 20)
VIA1  = (68, 44)
MET2  = (69, 20)
VIA2  = (69, 44)
MET3  = (70, 20)
VIA3  = (70, 44)
MET4  = (71, 20)
VIA4  = (71, 44)
MET5  = (72, 20)

DEVICE = [NWELL, DIFF, TAP, POLY, LICON, NPC]
METAL  = [LI1, MCON, MET1, VIA1, MET2, VIA2, MET3, VIA3, MET4, VIA4, MET5]
FULL   = DEVICE + METAL


def show_only(layers):
    """Leave only `layers` visible.

    A .lyp organises layers into named groups. A group node has no source
    layer of its own (source_layer is negative) and hiding it hides every
    child regardless of the child's own flag -- so groups are forced visible
    and the filter is applied only to leaves.
    """
    it = view.begin_layers()
    while not it.at_end():
        lp = it.current().dup()
        if lp.source_layer < 0:
            lp.visible = True
        else:
            lp.visible = (lp.source_layer, lp.source_datatype) in layers
        view.set_layer_properties(it, lp)
        it.next()


def shot(name, layers, box=None):
    show_only(layers)
    if box is None:
        view.zoom_fit()
    else:
        view.zoom_box(box)
    path = os.path.join(outdir, name)
    view.save_image(path, W, H)
    sys.stderr.write("wrote %s\n" % path)


def square_around(cx, cy, side):
    h = side / 2.0
    return pya.DBox(cx - h, cy - h, cx + h, cy + h)


# ------------------------------------------------------------ macro find ---
# LibreLane places hard macros as instances of the TOP cell, so a single pass
# over top-level instances finds them. Deliberately NOT recursive: walking into
# standard cells means visiting hundreds of thousands of instances to find two,
# and on a fill-heavy die that is slow enough to look like a hang.
cv = view.active_cellview()
top = cv.cell
ly = cv.layout()

macros = []
for inst in top.each_inst():
    try:
        name = ly.cell(inst.cell_index).name
    except Exception:
        continue
    if "sram" in name.lower():
        macros.append((name, inst.dbbox()))

if macros:
    sys.stderr.write("found %d SRAM macro(s):\n" % len(macros))
    for name, bb in macros:
        sys.stderr.write("  %-42s %.1f x %.1f um at (%.1f, %.1f)\n"
                         % (name, bb.width(), bb.height(),
                            bb.center().x, bb.center().y))
else:
    sys.stderr.write("no SRAM macros among top-level instances "
                     "(flop-memory build, or macros are nested deeper)\n")

bbox = cv.cell.dbbox()
sys.stderr.write("die: %.1f x %.1f um\n" % (bbox.width(), bbox.height()))

# Close-up focus: just above the first macro, where routing is congested.
# Falls back to the die centre when there are no macros.
if macros:
    mbb = macros[0][1]
    fx, fy = mbb.center().x, mbb.top + 70.0
    if fy > bbox.top - 60.0:            # macro near the top edge: go below
        fy = mbb.bottom - 70.0
else:
    fx, fy = bbox.center().x, bbox.center().y
sys.stderr.write("close-up focus: (%.1f, %.1f)\n" % (fx, fy))

# ------------------------------------------------------------- the shots ---

# 1. Whole die: standard cell rows and local routing.
shot("die_full.png", [LI1, MET1])

# 2. Whole die with the metal stack -- the dense routing view.
shot("die_routing.png", [LI1, MET1, MET2, MET3, MET4])

# 3. Whole die, everything. Macros read as texturally distinct blocks against
#    the standard cell sea, which is the point of this one.
shot("die_macros.png", FULL)

# 4. 50 um: individual cells and wires resolve. This is the publishable
#    close-up.
shot("die_zoom.png", FULL, square_around(fx, fy, 50.0))

# 5. 100 um: the full-stack view -- wide enough to look like a chip, close
#    enough that wires are still wires.
shot("die_stack.png", FULL, square_around(fx, fy, 100.0))

# 6. Per-macro framing. 1.35x the macro bbox leaves a margin of surrounding
#    logic so the macro reads as embedded rather than cropped.
for i, (name, bb) in enumerate(macros):
    side = max(bb.width(), bb.height()) * 1.35
    box = square_around(bb.center().x, bb.center().y, side)
    shot("sram_%d_context.png" % i, FULL, box)
    shot("sram_%d_routing.png" % i, [LI1, MET1, MET2, MET3, MET4], box)
    # Straddle the middle of the macro's top edge: the pin row on one side,
    # abutting standard cells on the other. Centring INSIDE the macro corner
    # lands in the keepout halo and renders as empty page.
    shot("sram_%d_edge.png" % i, FULL,
         square_around(bb.center().x, bb.top, 120.0))

sys.stderr.write("done\n")