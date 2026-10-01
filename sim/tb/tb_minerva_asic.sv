// tb_minerva_asic.sv
// -----------------------------------------------------------------------------
// MINERVA P5 -- gate-level (and RTL) testbench for minerva_asic_top.
//
// Proves the ASIC build actually executes code, which synthesis, place-and-route
// and DRC/LVS do not. Runs the P5 campaign workload through the host AXI4-Lite
// port and checks the ten result words against the golden values the hardware
// produced on the ZedBoard.
//
// Same sequence the PS ran in sw/p5/p5_campaign.c:
//     hold CPU -> load imem + dmem -> release -> CPU parks on the gate
//     -> host writes a NOP over the gate -> poll the done marker -> compare
//
// The image is the ASIC variant (sw/p5/workload_asic.S): its preamble zeroes
// only the nine registers the workload uses instead of all 31, so the program
// is 43 words and fits the 64-word ASIC imem. Golden results are bit-identical
// to the FPGA campaign.
//
// RTL run (sv2v first: Icarus rejects the crossbar's unpacked array params):
//   sv2v --write=/tmp/rtl.v -Irtl/common <rtl files> sim/tb/tb_minerva_asic.sv
//   iverilog -g2012 -o /tmp/sim /tmp/rtl.v && vvp /tmp/sim
//
// Gate-level run (netlist from the LibreLane run, plus Sky130 cell models):
//   iverilog -g2012 -DGATE_LEVEL -o /tmp/gsim \
//     sim/tb/tb_minerva_asic.sv \
//     asic/runs/<tag>/final/nl/minerva_asic_top.nl.v \
//     $PDK/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v \
//     $PDK/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
//   vvp /tmp/gsim
//
// NOTE: the netlist's flops have no initial value, so a gate-level run starts
// with every register at X. The workload writes every register it uses before
// reading it, and the host writes every memory word it later reads, so the X
// state should wash out. If it does not, that is itself the finding.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_minerva_asic;

  // 25 ns period -- matches the SDC. Nothing here depends on the exact value.
  localparam real CLK_PERIOD = 25.0;   // ns, with `timescale 1ns/1ps

  localparam logic [31:0] IMEM_BASE = 32'h0003_0000;
  localparam logic [31:0] DMEM_BASE = 32'h0000_0000;
  localparam logic [31:0] GATE_OFF  = 32'h0000_0024;  // see workload_asic.S
  localparam logic [31:0] NOP_INSN  = 32'h0000_0013;
  localparam logic [31:0] IN_OFF    = 32'h0000_0000;
  localparam logic [31:0] OUT_OFF   = 32'h0000_0100;
  localparam int          OUT_WORDS = 10;
  localparam logic [31:0] MARKER    = 32'h600D_1000;

  localparam logic [31:0] IMAGE [43] = '{
    32'h00000413, 32'h00000493, 32'h00000913, 32'h00000293, 32'h00000313,
    32'h00000393, 32'h00000E13, 32'h00000E93, 32'h00000513, 32'h0000006F,
    32'h00000413, 32'h10000493, 32'h00800293, 32'h00000513, 32'h00042303,
    32'h0064A023, 32'h00151513, 32'h00654533, 32'h00440413, 32'h00448493,
    32'hFFF28293, 32'hFE0292E3, 32'h12A02023, 32'h00700293, 32'h10000493,
    32'h00700E13, 32'h0004A303, 32'h0044A383, 32'h0063D663, 32'h0074A023,
    32'h0064A223, 32'h00448493, 32'hFFFE0E13, 32'hFE0E12E3, 32'hFFF28293,
    32'hFC029AE3, 32'h600D1337, 32'h12602223, 32'h00001937, 32'h10092E83,
    32'h11092E83, 32'h12092E83, 32'h0000006F
  };

  localparam logic [31:0] INPUT [8] = '{
    32'h00000013, 32'hFFFFFFF9, 32'h00007FFF, 32'h0000002A,
    32'h00000000, 32'hFFFFFC18, 32'h00000005, 32'h00001234
  };

  // Golden output, identical to the ZedBoard campaign run.
  localparam logic [31:0] GOLDEN [OUT_WORDS] = '{
    32'hFFFFFC18, 32'hFFFFFFF9, 32'h00000000, 32'h00000005, 32'h00000013,
    32'h0000002A, 32'h00001234, 32'h00007FFF, 32'h000FE8DE, MARKER
  };

  // ------------------------------------------------------------------ DUT ---
  logic        clk = 1'b0;
  logic        rst_n_pad;
  logic        cpu_hold;

  logic [31:0] host_awaddr;
  logic        host_awvalid, host_awready;
  logic [31:0] host_wdata;
  logic [3:0]  host_wstrb;
  logic        host_wvalid,  host_wready;
  logic [1:0]  host_bresp;
  logic        host_bvalid,  host_bready;
  logic [31:0] host_araddr;
  logic        host_arvalid, host_arready;
  logic [31:0] host_rdata;
  logic [1:0]  host_rresp;
  logic        host_rvalid,  host_rready;

  logic [31:0] debug_out, if_pc_out;
  logic        if_stall_out, mem_stall_out, dma_irq, fi_irq;

  minerva_asic_top dut (
      .clk (clk), .rst_n_pad (rst_n_pad), .cpu_hold (cpu_hold),
      .host_awaddr (host_awaddr), .host_awvalid(host_awvalid), .host_awready(host_awready),
      .host_wdata  (host_wdata),  .host_wstrb  (host_wstrb),   .host_wvalid (host_wvalid),
      .host_wready (host_wready), .host_bresp  (host_bresp),   .host_bvalid (host_bvalid),
      .host_bready (host_bready), .host_araddr (host_araddr),  .host_arvalid(host_arvalid),
      .host_arready(host_arready),.host_rdata  (host_rdata),   .host_rresp  (host_rresp),
      .host_rvalid (host_rvalid), .host_rready (host_rready),
      .debug_out (debug_out), .if_pc_out (if_pc_out),
      .if_stall_out (if_stall_out), .mem_stall_out (mem_stall_out),
      .dma_irq (dma_irq), .fi_irq (fi_irq)
  );

  always #12.5 clk = ~clk;
  // ------------------------------------------------- AXI4-Lite host tasks ---
  task automatic host_write(input logic [31:0] addr, input logic [31:0] data);
    begin
      @(posedge clk);
      host_awaddr  <= addr;  host_awvalid <= 1'b1;
      host_wdata   <= data;  host_wstrb   <= 4'hF;  host_wvalid <= 1'b1;
      host_bready  <= 1'b1;
      // Address and data phases may complete in either order.
      fork
        begin : aw_phase
          while (!(host_awvalid && host_awready)) @(posedge clk);
          host_awvalid <= 1'b0;
        end
        begin : w_phase
          while (!(host_wvalid && host_wready)) @(posedge clk);
          host_wvalid <= 1'b0;
        end
      join
      while (!(host_bvalid && host_bready)) @(posedge clk);
      @(posedge clk);
      host_bready <= 1'b0;
    end
  endtask

  task automatic host_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      @(posedge clk);
      host_araddr  <= addr;  host_arvalid <= 1'b1;  host_rready <= 1'b1;
      while (!(host_arvalid && host_arready)) @(posedge clk);
      host_arvalid <= 1'b0;
      while (!(host_rvalid && host_rready)) @(posedge clk);
      data = host_rdata;
      @(posedge clk);
      host_rready <= 1'b0;
    end
  endtask

  // ------------------------------------------------------------- the test ---
  logic [31:0] rd;
  int          errors = 0;
  int          poll;

  initial begin
    host_awvalid = 0; host_wvalid = 0; host_bready = 0;
    host_arvalid = 0; host_rready = 0;
    host_awaddr  = 0; host_wdata  = 0; host_wstrb  = 0; host_araddr = 0;
    cpu_hold  = 1'b1;          // CPU held from the very first cycle
    rst_n_pad = 1'b0;
    repeat (10) @(posedge clk);
    rst_n_pad = 1'b1;
    repeat (10) @(posedge clk);

    $display("[%0t] loading %0d image words", $time, 43);
    for (int i = 0; i < 43; i++)
      host_write(IMEM_BASE + i*4, IMAGE[i]);

    $display("[%0t] loading input data, clearing results", $time);
    for (int i = 0; i < 8; i++)
      host_write(DMEM_BASE + IN_OFF + i*4, INPUT[i]);
    for (int i = 0; i < OUT_WORDS; i++)
      host_write(DMEM_BASE + OUT_OFF + i*4, 32'h0);

    // Read one word back: proves the host path works before the CPU is blamed.
    host_read(IMEM_BASE, rd);
    if (rd !== IMAGE[0]) begin
      $display("FAIL: imem readback %08h, expected %08h", rd, IMAGE[0]);
      errors = errors + 1;
    end

    $display("[%0t] releasing CPU", $time);
    cpu_hold = 1'b0;
    repeat (200) @(posedge clk);   // preamble runs, CPU parks on the gate

    $display("[%0t] opening the gate", $time);
    host_write(IMEM_BASE + GATE_OFF, NOP_INSN);

    // Poll the done marker. The workload evicts its output lines before the
    // marker store, so seeing the marker means the results reached dmem.
    poll = 0;
    rd   = 32'h0;
    while (rd !== MARKER) begin
      repeat (50) @(posedge clk);
      host_read(DMEM_BASE + OUT_OFF + 4*(OUT_WORDS-1), rd);
      poll = poll + 1;
      if (poll > 400) begin
        $display("FAIL: marker never appeared (last read %08h, pc=%08h)", rd, if_pc_out);
        errors = errors + 1;
        rd = MARKER;   // leave the loop
        poll = -1;     // remember that this was a timeout
      end
    end

    if (poll != -1) begin
      $display("[%0t] marker seen after %0d polls", $time, poll);
      for (int i = 0; i < OUT_WORDS; i++) begin
        host_read(DMEM_BASE + OUT_OFF + i*4, rd);
        if (rd !== GOLDEN[i]) begin
          $display("FAIL: out[%0d] = %08h, expected %08h", i, rd, GOLDEN[i]);
          errors = errors + 1;
        end else begin
          $display("      out[%0d] = %08h  ok", i, rd);
        end
      end
    end

    if (errors == 0) $display("\n==== PASS: the netlist executed the workload correctly ====\n");
    else             $display("\n==== FAIL: %0d error(s) ====\n", errors);
    $finish;
  end

  // Safety net so a hung run ends rather than spinning forever.
  initial begin
    #5000000;   // 5 ms
    $display("FAIL: global timeout");
    $finish;
  end

`ifdef GATE_LEVEL
  initial begin
    $dumpfile("tb_minerva_asic.vcd");
    $dumpvars(1, tb_minerva_asic);
  end
`endif

endmodule