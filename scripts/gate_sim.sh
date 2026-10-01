#!/usr/bin/env bash
# Gate-level simulation of minerva_asic_top against a LibreLane netlist.
#
#   scripts/gate_sim.sh [run_tag]
#
# With no argument it uses the newest run under asic/runs/. Runs the P5 campaign
# workload through the host AXI4-Lite port and checks the ten result words
# against the values the ZedBoard produced.
#
# The two defines below are NOT optional. Without -DFUNCTIONAL -DUNIT_DELAY the
# Sky130 cell models elaborate in a way that leaves the design at X: the AXI
# handshakes appear to complete (faster than they should) and every readback is
# xxxxxxxx. It looks exactly like a broken netlist and is not one.
set -euo pipefail

cd "$(dirname "$0")/.."
PDK="${PDK_ROOT:-$HOME/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A}"
CELLS="$PDK/libs.ref/sky130_fd_sc_hd/verilog"

RUN="${1:-$(ls -td asic/runs/RUN_* | head -1)}"
[ -d "$RUN" ] || RUN="asic/runs/$1"
NL="$RUN/final/nl/minerva_asic_top.nl.v"
[ -f "$NL" ] || NL="$(ls -t $RUN/*-yosys-synthesis/minerva_asic_top.nl.v 2>/dev/null | head -1)"

echo "netlist: $NL"
mkdir -p build

# Icarus cannot read the testbench's SystemVerilog directly; convert it first.
nix shell nixpkgs#haskellPackages.sv2v --command \
    sv2v --write=build/tb_minerva_asic.v sim/tb/tb_minerva_asic.sv

iverilog -g2012 -DGATE_LEVEL -DFUNCTIONAL -DUNIT_DELAY=#1 \
    -o build/gate_sim build/tb_minerva_asic.v "$NL" \
    "$CELLS/primitives.v" "$CELLS/sky130_fd_sc_hd.v"

vvp build/gate_sim | tee build/gate_sim.log
grep -q "==== PASS" build/gate_sim.log