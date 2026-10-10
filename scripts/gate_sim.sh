#!/usr/bin/env bash
# Gate-level simulation of minerva_asic_top against a LibreLane netlist.
#
#   scripts/gate_sim.sh [run_tag]
#
# With no argument it uses the newest run under asic/runs/. Runs the P5 campaign
# workload through the host AXI4-Lite port and checks the ten result words
# against the values the ZedBoard produced.
#
# Handles both memory configurations: if the netlist instantiates the sky130
# SRAM macros, their behavioural models are patched (see below) and added to the
# compile. Those are the PDK's real models -- NOT rtl/asic/sky130_sram_blackbox.v,
# which is ports-only and exists so the build flow's linter and OpenSTA have a
# declaration. Simulating against the blackbox would "pass" with empty memories
# and prove nothing.
#
# -DFUNCTIONAL -DUNIT_DELAY are NOT optional. Without them the Sky130 standard
# cell models elaborate into an all-X state: the AXI handshakes appear to
# complete, faster than they should, and every readback is xxxxxxxx. It looks
# exactly like a broken netlist and is not one.
set -euo pipefail

cd "$(dirname "$0")/.."
PDK="${PDK_ROOT:-$HOME/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A}"
CELLS="$PDK/libs.ref/sky130_fd_sc_hd/verilog"
SRAMV="$PDK/libs.ref/sky130_sram_macros/verilog"

RUN="${1:-$(ls -td asic/runs/RUN_* | head -1)}"
[ -d "$RUN" ] || RUN="asic/runs/${1:-}"
NL="$RUN/final/nl/minerva_asic_top.nl.v"
[ -f "$NL" ] || NL="$(ls -t $RUN/*-yosys-synthesis/minerva_asic_top.nl.v 2>/dev/null | head -1)"
[ -f "$NL" ] || { echo "no netlist found under $RUN" >&2; exit 1; }
echo "netlist: $NL"

mkdir -p build/sram_models

# Patch the macro models for Icarus.
#
# The PDK models print debug lines like
#     $display($time," Reading %m addr0=%b dout0=%b",addr0_reg,mem[addr0_reg]);
# and iverilog cannot elaborate a memory word indexed by a variable inside
# $display ("Scope index expression is not constant"). Only the VERBOSE logging
# is affected -- the real read/write paths elaborate fine.
#
# Each such $display sits under a bare `if` on the line above, so it is replaced
# by an EMPTY STATEMENT rather than deleted: removing the line entirely would
# leave that `if` binding to whatever statement came next, silently changing
# the model's behaviour.
MACRO_MODELS=()
for m in sky130_sram_2kbyte_1rw1r_32x512_8 sky130_sram_1kbyte_1rw1r_32x256_8; do
    grep -q "$m" "$NL" || continue
    src="$SRAMV/$m.v"
    [ -f "$src" ] || { echo "netlist needs $m but $src is missing" >&2; exit 1; }
    dst="build/sram_models/$m.v"
    sed -E 's@^([[:space:]]*)\$display\(.*mem\[addr[01]_reg\].*\);[[:space:]]*$@\1;  // $display dropped for iverilog@' \
        "$src" > "$dst"

    # Confirm the patch hit the debug lines and left the memory behaviour alone.
    #
    # These use awk and match on whole-line containment rather than one hand
    # written regex. The model's own source contains (), [] and # -- characters
    # that are regex metacharacters -- so a single pattern spanning them is very
    # easy to get subtly wrong, and a guard that wrongly reports damage is worse
    # than no guard: it blocks a correct patch.
    [ "$(grep -c 'display.*mem\[addr' "$dst")" -eq 0 ] \
        || { echo "patch failed: debug \$display still present in $dst" >&2; exit 1; }

    # the registered read: some line assigns dout0 from mem[addr0_reg]
    awk '/dout0[ \t]*<=/ && /mem\[addr0_reg\]/ { n++ } END { exit !(n > 0) }' "$dst" \
        || { echo "patch damaged $dst: lost the dout0 <= mem[addr0_reg] read" >&2; exit 1; }

    # the byte-masked write: some line assigns a byte lane of mem[addr0_reg]
    awk '/mem\[addr0_reg\]\[/ && /din0_reg/ { n++ } END { exit !(n > 0) }' "$dst" \
        || { echo "patch damaged $dst: lost the mem[addr0_reg] write" >&2; exit 1; }

    MACRO_MODELS+=("$dst")
    echo "  + macro model: $m (patched, memory paths verified intact)"
done
if [ ${#MACRO_MODELS[@]} -eq 0 ]; then
    echo "  (flop-memory build -- no macro models needed)"
fi

# Icarus cannot read the testbench's SystemVerilog directly; convert it first.
nix shell nixpkgs#haskellPackages.sv2v --command \
    sv2v --write=build/tb_minerva_asic.v sim/tb/tb_minerva_asic.sv

iverilog -g2012 -DGATE_LEVEL -DFUNCTIONAL -DUNIT_DELAY=#1 \
    -o build/gate_sim build/tb_minerva_asic.v "$NL" \
    "$CELLS/primitives.v" "$CELLS/sky130_fd_sc_hd.v" \
    ${MACRO_MODELS[@]+"${MACRO_MODELS[@]}"}

vvp build/gate_sim | tee build/gate_sim.log
grep -q "==== PASS" build/gate_sim.log