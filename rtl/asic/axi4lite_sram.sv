// axi4lite_sram.sv
// -----------------------------------------------------------------------------
// AXI4-Lite slave front end for the sky130 OpenRAM macros, drop-in replacement
// for axi4lite_mem_model in the ASIC build.
//
//   ADDR_WIDTH = 8  -> sky130_sram_1kbyte_1rw1r_32x256_8   (256 x 32,  1 KB)
//   ADDR_WIDTH = 9  -> sky130_sram_2kbyte_1rw1r_32x512_8   (512 x 32,  2 KB)
//
// THE REASON THIS MODULE EXISTS AT ALL: the macro has a REGISTERED read port.
// axi4lite_mem_model answered a read combinationally in the same cycle; the
// macro latches csb0/web0/addr0 on the clock edge and only presents dout0 in
// the cycle AFTER that edge. So a read cannot be answered where the old model
// answered it, and this wrapper adds the state to wait.
//
// Macro interface (from the PDK's behavioural model):
//   port 0 (rw):  clk0, csb0, web0, wmask0[3:0], addr0, din0[31:0], dout0[31:0]
//   port 1 (r):   clk1, csb1, addr1, dout1[31:0]
//   csb0/csb1 and web0 are ACTIVE LOW. All port-0 inputs are registered.
//
// Port 1 is tied off. It is a second read port the CPU has no use for -- the
// fetch and data paths already arbitrate through the crossbar -- but it is
// there if a future phase wants a dedicated instruction-fetch read port that
// never contends with the fault-injection master.
//
// Timing, per transaction:
//   write  IDLE (drive macro) -> S_BRESP (bvalid, await bready)         2 cycles
//   read   IDLE (drive macro) -> S_RD (capture dout0) -> S_RRESP        3 cycles
//
// S_RD exists because dout0 is only valid during that one cycle: the macro
// drives it X again on the next edge once csb0 has gone inactive. Capturing it
// into rdata_q means a master that is slow to assert rready still gets the
// right data.
//
// Single outstanding by construction: awready/wready/arready are low in every
// state but IDLE, so a second request cannot arrive while one is in flight.
// -----------------------------------------------------------------------------

`include "axi4lite_ports.vh"

module axi4lite_sram #(
    // 8 => 256 words (1 KB), 9 => 512 words (2 KB). Nothing else is valid:
    // those are the only two 32-bit-wide macros the sky130A PDK ships.
    parameter int ADDR_WIDTH = 9
) (
    input  logic clk,
    input  logic rst_n,
    `AXI4LITE_SLAVE_PORTS(s_axi)
);

  initial begin
    if (ADDR_WIDTH != 8 && ADDR_WIDTH != 9)
      $fatal(1, "axi4lite_sram: ADDR_WIDTH must be 8 (1 KB) or 9 (2 KB)");
  end

  // ------------------------------------------------------------ macro port ---
  logic                  csb0, web0;
  logic [3:0]            wmask0;
  logic [ADDR_WIDTH-1:0] addr0;
  logic [31:0]           din0;
  logic [31:0]           dout0;

  // Word addresses pulled out as continuous assignments rather than sliced
  // inside the always_comb below. Icarus rejects a parameterised part-select in
  // an always_* process ("constant selects ... not currently supported"), the
  // same limitation that affects imm_gen.sv, and this form avoids it entirely.
  wire [ADDR_WIDTH-1:0] wr_word_addr = s_axi_awaddr[ADDR_WIDTH+1:2];
  wire [ADDR_WIDTH-1:0] rd_word_addr = s_axi_araddr[ADDR_WIDTH+1:2];

  typedef enum logic [1:0] {S_IDLE, S_RD, S_RRESP, S_BRESP} state_e;
  state_e state_q;

  logic [31:0] rdata_q;
  logic        bvalid_q, rvalid_q;

  // Ready only in IDLE: that is what makes this single-outstanding, and it is
  // also why the macro's inputs can be driven straight off the AXI signals
  // without a holding register -- nothing else can be presented mid-access.
  assign s_axi_awready = (state_q == S_IDLE);
  assign s_axi_wready  = (state_q == S_IDLE);
  assign s_axi_arready = (state_q == S_IDLE);
  assign s_axi_bresp   = 2'b00;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_bvalid  = bvalid_q;
  assign s_axi_rvalid  = rvalid_q;
  assign s_axi_rdata   = rdata_q;

  // Drive the macro combinationally; it registers these itself on the edge.
  // Writes win over reads when both are offered, matching axi4lite_mem_model.
  always_comb begin
    csb0   = 1'b1;          // active low -- deselected
    web0   = 1'b1;          // active low -- read
    wmask0 = 4'h0;
    addr0  = '0;
    din0   = '0;
    if (state_q == S_IDLE) begin
      if (s_axi_awvalid && s_axi_wvalid) begin
        csb0   = 1'b0;
        web0   = 1'b0;
        wmask0 = s_axi_wstrb;
        addr0  = wr_word_addr;
        din0   = s_axi_wdata;
      end else if (s_axi_arvalid) begin
        csb0   = 1'b0;
        web0   = 1'b1;
        addr0  = rd_word_addr;
      end
    end
  end

  // Addresses above the macro's depth alias down, exactly as the old model's
  // "% MEM_WORDS" did. The crossbar still decodes the full 16 KB / 4 KB
  // windows, so the CPU address map is unchanged from the FPGA build.

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q  <= S_IDLE;
      rdata_q  <= '0;
      bvalid_q <= 1'b0;
      rvalid_q <= 1'b0;
    end else begin
      if (bvalid_q && s_axi_bready) bvalid_q <= 1'b0;
      if (rvalid_q && s_axi_rready) rvalid_q <= 1'b0;

      unique case (state_q)
        S_IDLE: begin
          if (s_axi_awvalid && s_axi_wvalid) begin
            // The macro captured the write on this same edge.
            bvalid_q <= 1'b1;
            state_q  <= S_BRESP;
          end else if (s_axi_arvalid) begin
            state_q  <= S_RD;
          end
        end

        S_RD: begin
          // dout0 was valid throughout this cycle; this edge samples it before
          // the macro drives it X again.
          rdata_q  <= dout0;
          rvalid_q <= 1'b1;
          state_q  <= S_RRESP;
        end

        S_RRESP: begin
          if (rvalid_q && s_axi_rready) state_q <= S_IDLE;
        end

        S_BRESP: begin
          if (bvalid_q && s_axi_bready) state_q <= S_IDLE;
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

  // ----------------------------------------------------------- the macro ---
  // Port 1 tied off: csb1 inactive, address parked. dout1 is left unconnected
  // deliberately; synthesis drops it.
  generate
    if (ADDR_WIDTH == 8) begin : g_sram_1kb
      sky130_sram_1kbyte_1rw1r_32x256_8 u_sram (
`ifdef USE_POWER_PINS
          .vccd1 (vccd1),
          .vssd1 (vssd1),
`endif
          .clk0 (clk),   .csb0 (csb0), .web0 (web0), .wmask0 (wmask0),
          .addr0 (addr0), .din0 (din0), .dout0 (dout0),
          .clk1 (clk),   .csb1 (1'b1), .addr1 ({ADDR_WIDTH{1'b0}}), .dout1 ()
      );
    end else begin : g_sram_2kb
      sky130_sram_2kbyte_1rw1r_32x512_8 u_sram (
`ifdef USE_POWER_PINS
          .vccd1 (vccd1),
          .vssd1 (vssd1),
`endif
          .clk0 (clk),   .csb0 (csb0), .web0 (web0), .wmask0 (wmask0),
          .addr0 (addr0), .din0 (din0), .dout0 (dout0),
          .clk1 (clk),   .csb1 (1'b1), .addr1 ({ADDR_WIDTH{1'b0}}), .dout1 ()
      );
    end
  endgenerate

endmodule : axi4lite_sram