# gds_shots.py -- batch KLayout screenshots of a GDS, no GUI fiddling.
#
#   klayout -z -nc -rd gds=<layout.gds> -rd outdir=docs/images \
#           -r scripts/gds_shots.py
#
# -z  : no main window shown (a view still exists, so images still render)
# -nc : ignore the user's saved configuration, so results are reproducible
#
# Both paths come through -rd, which defines them as variables before the script
# runs. KLayout does NOT put the layout path in sys.argv, and under -z anything
# printed to stdout is swallowed -- a script that fails on sys.argv therefore
# dies in complete silence. Hence -rd for the inputs and stderr for progress.
#
# Produces three images in outdir:
#   die_full.png     whole die, cell rows and local routing only
#   die_zoom.png     a 150 um square from the middle, cells resolvable
#   die_routing.png  whole die with met1..met4, the dense multi-colour view
#
# Why the layer lists look like this: sky130 layers appear at several
# datatypes. Only datatype 20 is drawing; /5, /16 and /44 are labels, pins and
# other annotation, and showing them buries the layout under text. 235/4 and
# 236/0 are boundary markers covering the whole die -- they are what makes an
# unfiltered view render as one solid colour block.

import pya
import sys
import os

try:
    gds
except NameError:
    sys.stderr.write("usage: klayout -z -nc -rd gds=FILE [-rd outdir=DIR] "
                     "-r gds_shots.py\n")
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


def show_only(layers):
    """layers: list of (layer, datatype) tuples to leave visible."""
    it = view.begin_layers()
    while not it.at_end():
        lp = it.current().dup()
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


LI1  = (67, 20)       # local interconnect
MET1 = (68, 20)
MET2 = (69, 20)
MET3 = (70, 20)
MET4 = (71, 20)

# 1. Whole die: standard cell rows and local routing.
shot("die_full.png", [LI1, MET1])

# 2. A 150 um square from the centre, where individual cells resolve. Full-die
#    views of 128k cells average out into texture; this is the publishable one.
bbox = view.active_cellview().cell.dbbox()
cx, cy, half = bbox.center().x, bbox.center().y, 75.0
shot("die_zoom.png", [LI1, MET1],
     pya.DBox(cx - half, cy - half, cx + half, cy + half))

# 3. Whole die with the metal stack -- the dense routing view.
shot("die_routing.png", [LI1, MET1, MET2, MET3, MET4])

sys.stderr.write("done\n")