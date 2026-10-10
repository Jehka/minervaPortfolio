/// sta-blackbox
// -----------------------------------------------------------------------------
// Blackbox declarations for the sky130 OpenRAM macros.
//
// These exist because the three tools in the flow want incompatible things from
// the same macro:
//
//   the linter  needs a module DECLARATION or it errors with "Cannot find
//               file containing module" -- one error per macro.
//   OpenSTA     cannot parse the PDK's behavioural model at all: it only reads
//               gate-level netlists, and chokes on that model's parameter
//               declarations ("line 20, syntax error").
//   Yosys       needs these treated as hard blocks, not synthesised.
//
// (Comment lines here deliberately avoid starting with the linter's own name:
//  it reads "// <its name> ..." as a pragma and errors on the unknown comment.)
//
// Ports only, no behaviour. The '/// sta-blackbox' marker on line 1 is what
// OpenSTA looks for to skip the file, and (* blackbox *) is what stops Yosys
// from inferring an empty module and optimising the instance away.
//
// This file is for the BUILD flow. Simulation uses the PDK's real behavioural
// models at $PDK/libs.ref/sky130_sram_macros/verilog/ -- see scripts/gate_sim.sh.
//
// Port lists taken verbatim from those models. Note csb0/csb1/web0 are all
// ACTIVE LOW, and port 0's inputs are registered inside the macro.
// -----------------------------------------------------------------------------

(* blackbox *)
module sky130_sram_1kbyte_1rw1r_32x256_8 (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [3:0]  wmask0,
    input  wire [7:0]  addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0,
    input  wire        clk1,
    input  wire        csb1,
    input  wire [7:0]  addr1,
    output wire [31:0] dout1
);
endmodule

(* blackbox *)
module sky130_sram_2kbyte_1rw1r_32x512_8 (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [3:0]  wmask0,
    input  wire [8:0]  addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0,
    input  wire        clk1,
    input  wire        csb1,
    input  wire [8:0]  addr1,
    output wire [31:0] dout1
);
endmodule