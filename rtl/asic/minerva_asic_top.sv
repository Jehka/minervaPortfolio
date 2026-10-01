// minerva_asic_top.sv
// -----------------------------------------------------------------------------
// MINERVA P5 ASIC top level -- the hardening boundary for the Sky130 flow.
//
// Differences from p4_top.v, and why:
//
//   * No Xilinx anything. No PS, no AXI BRAM controllers, no ILA, no ps7.
//     Memories are plain flop arrays inside this boundary.
//
//   * Memories are shrunk so they synthesise as flops instead of needing SRAM
//     macros: dmem 2 KB (512 words), imem 1 KB (256 words). The crossbar decode
//     ranges are UNCHANGED, so the address map matches the FPGA build and the
//     same programs run; addresses above the physical size alias down.
//
//   * The cache shrinks from 256 lines to 16 (CACHE_INDEX_BITS = 4), about 1 KB
//     of flops. Same RTL, one parameter.
//
//   * A host port replaces the ZedBoard PS. It is crossbar master 3, so an
//     external tester loads imem and dmem, programs the FI master and reads
//     results through one AXI4-Lite slave port. The FI config registers sit on
//     slave 2 (the reserved peripheral slot), so they are reachable the same
//     way -- no second external port.
//
//   * Reset: active-low, synchronised here. On the FPGA the equivalent reset
//     was an OR of two sources built from a LUT; a pad reset needs a proper
//     synchroniser instead (async assert, synchronous release).
//
// CPU-space map (unchanged from P4):
//   0x0000_0000  dmem        (2 KB here, decode range still 16 KB)
//   0x0001_0000  DMA regs
//   0x0002_0000  FI config   (was a reserved slot on the FPGA)
//   0x0003_0000  imem        (1 KB here, decode range still 4 KB)
// -----------------------------------------------------------------------------

module minerva_asic_top #(
    parameter int CACHE_INDEX_BITS = 4,    // 16 lines
    // Memory depth for the first closure. Flop arrays synthesise their read
    // path as a mux tree, so depth drives cell count hard: 512/256 words came
    // out at ~86k cells (~1.23 mm2 of cell area), 128/64 lands near a quarter
    // of that and routes in a fraction of the time. The pipeline, cache,
    // crossbar and FI master are unaffected -- only how much a test program
    // can hold. 128/64 still fits the P5 campaign workload (65 imem words,
    // 8 input + 10 output data words). Raise these once the flow closes.
    parameter int DMEM_WORDS       = 128,  // 512 B
    parameter int IMEM_WORDS       = 64    // 256 B
)(
    input  logic        clk,
    input  logic        rst_n_pad,       // async assert, synchronised below

    // Hold the CPU (and only the CPU) in reset while the host loads memory.
    // This is the ZedBoard's cpu_reset_gpio bit as a pin. The crossbar, FI
    // master and both memories stay live so the host can still reach them --
    // the same reset-domain split that P5 had to fix on the FPGA, where the
    // CPU-side BRAM controllers sat in the wrong domain and deadlocked the
    // crossbar whenever a hold landed mid-fetch.
    input  logic        cpu_hold,

    // Host port -- crossbar master 3. Load memory, program FI, read results.
    input  logic [31:0] host_awaddr,
    input  logic        host_awvalid,
    output logic        host_awready,
    input  logic [31:0] host_wdata,
    input  logic [3:0]  host_wstrb,
    input  logic        host_wvalid,
    output logic        host_wready,
    output logic [1:0]  host_bresp,
    output logic        host_bvalid,
    input  logic        host_bready,
    input  logic [31:0] host_araddr,
    input  logic        host_arvalid,
    output logic        host_arready,
    output logic [31:0] host_rdata,
    output logic [1:0]  host_rresp,
    output logic        host_rvalid,
    input  logic        host_rready,

    // Observability (the ILA probes, brought out as pins)
    output logic [31:0] debug_out,
    output logic [31:0] if_pc_out,
    output logic        if_stall_out,
    output logic        mem_stall_out,
    output logic        dma_irq,
    output logic        fi_irq
);

  localparam int NM = 4;   // masters: 0 cpu-data, 1 FI, 2 cpu-fetch, 3 host
  localparam int NS = 4;   // slaves:  0 dmem, 1 dma_reg, 2 fi_cfg, 3 imem

  // ---------------------------------------------------------------- reset ---
  // Async assert, synchronous release. Two flops, reset-asserted, so the
  // release edge is clean regardless of when the pad deasserts.
  logic [1:0] rst_sync_q;
  wire        rst_n;
  always_ff @(posedge clk or negedge rst_n_pad) begin
    if (!rst_n_pad) rst_sync_q <= 2'b00;
    else            rst_sync_q <= {rst_sync_q[0], 1'b1};
  end
  assign rst_n = rst_sync_q[1];
  wire rst = ~rst_n;

  // CPU-only reset: pad reset OR the hold pin, registered so no combinational
  // gate drives a reset pin.
  logic cpu_rst_q;
  always_ff @(posedge clk or negedge rst_n_pad) begin
    if (!rst_n_pad) cpu_rst_q <= 1'b1;
    else            cpu_rst_q <= rst | cpu_hold;
  end
  wire cpu_rst = cpu_rst_q;

  // ------------------------------------------------------- crossbar nets ---
  logic [NM-1:0][31:0] m_awaddr,  m_wdata,  m_araddr, m_rdata;
  logic [NM-1:0][3:0]  m_wstrb;
  logic [NM-1:0][1:0]  m_bresp,   m_rresp;
  logic [NM-1:0]       m_awvalid, m_awready, m_wvalid, m_wready;
  logic [NM-1:0]       m_bvalid,  m_bready,  m_arvalid, m_arready;
  logic [NM-1:0]       m_rvalid,  m_rready;

  logic [NS-1:0][31:0] s_awaddr,  s_wdata,  s_araddr, s_rdata;
  logic [NS-1:0][3:0]  s_wstrb;
  logic [NS-1:0][1:0]  s_bresp,   s_rresp;
  logic [NS-1:0]       s_awvalid, s_awready, s_wvalid, s_wready;
  logic [NS-1:0]       s_bvalid,  s_bready,  s_arvalid, s_arready;
  logic [NS-1:0]       s_rvalid,  s_rready;

  // ------------------------------------------------------------- the CPU ---
  riscv_cpu_p4 #(
      .CACHE_INDEX_BITS (CACHE_INDEX_BITS)
  ) u_cpu (
      .clk (clk), .rst (cpu_rst),
      .debug_out (debug_out), .mem_stall_out (mem_stall_out),
      .if_pc_out (if_pc_out), .if_stall_out (if_stall_out),
      .dma_irq (dma_irq),

      // DMA register slave <- crossbar slave 1
      .dma_reg_awaddr (s_awaddr[1]), .dma_reg_awvalid(s_awvalid[1]), .dma_reg_awready(s_awready[1]),
      .dma_reg_wdata  (s_wdata[1]),  .dma_reg_wstrb  (s_wstrb[1]),   .dma_reg_wvalid (s_wvalid[1]),
      .dma_reg_wready (s_wready[1]), .dma_reg_bresp  (s_bresp[1]),   .dma_reg_bvalid (s_bvalid[1]),
      .dma_reg_bready (s_bready[1]), .dma_reg_araddr (s_araddr[1]),  .dma_reg_arvalid(s_arvalid[1]),
      .dma_reg_arready(s_arready[1]),.dma_reg_rdata  (s_rdata[1]),   .dma_reg_rresp  (s_rresp[1]),
      .dma_reg_rvalid (s_rvalid[1]), .dma_reg_rready (s_rready[1]),

      // data master -> crossbar master 0
      .ext_mem_awaddr (m_awaddr[0]), .ext_mem_awvalid(m_awvalid[0]), .ext_mem_awready(m_awready[0]),
      .ext_mem_wdata  (m_wdata[0]),  .ext_mem_wstrb  (m_wstrb[0]),   .ext_mem_wvalid (m_wvalid[0]),
      .ext_mem_wready (m_wready[0]), .ext_mem_bresp  (m_bresp[0]),   .ext_mem_bvalid (m_bvalid[0]),
      .ext_mem_bready (m_bready[0]), .ext_mem_araddr (m_araddr[0]),  .ext_mem_arvalid(m_arvalid[0]),
      .ext_mem_arready(m_arready[0]),.ext_mem_rdata  (m_rdata[0]),   .ext_mem_rresp  (m_rresp[0]),
      .ext_mem_rvalid (m_rvalid[0]), .ext_mem_rready (m_rready[0]),

      // fetch master -> crossbar master 2
      .instr_mem_awaddr (m_awaddr[2]), .instr_mem_awvalid(m_awvalid[2]), .instr_mem_awready(m_awready[2]),
      .instr_mem_wdata  (m_wdata[2]),  .instr_mem_wstrb  (m_wstrb[2]),   .instr_mem_wvalid (m_wvalid[2]),
      .instr_mem_wready (m_wready[2]), .instr_mem_bresp  (m_bresp[2]),   .instr_mem_bvalid (m_bvalid[2]),
      .instr_mem_bready (m_bready[2]), .instr_mem_araddr (m_araddr[2]),  .instr_mem_arvalid(m_arvalid[2]),
      .instr_mem_arready(m_arready[2]),.instr_mem_rdata  (m_rdata[2]),   .instr_mem_rresp  (m_rresp[2]),
      .instr_mem_rvalid (m_rvalid[2]), .instr_mem_rready (m_rready[2])
  );

  // --------------------------------------------- fault-injection master ----
  // Config slave on crossbar slave 2; injection master on crossbar master 1.
  fault_injection_master u_fi (
      .clk (clk), .rst_n (rst_n),
      .s_axi_awaddr (s_awaddr[2]), .s_axi_awvalid(s_awvalid[2]), .s_axi_awready(s_awready[2]),
      .s_axi_wdata  (s_wdata[2]),  .s_axi_wstrb  (s_wstrb[2]),   .s_axi_wvalid (s_wvalid[2]),
      .s_axi_wready (s_wready[2]), .s_axi_bresp  (s_bresp[2]),   .s_axi_bvalid (s_bvalid[2]),
      .s_axi_bready (s_bready[2]), .s_axi_araddr (s_araddr[2]),  .s_axi_arvalid(s_arvalid[2]),
      .s_axi_arready(s_arready[2]),.s_axi_rdata  (s_rdata[2]),   .s_axi_rresp  (s_rresp[2]),
      .s_axi_rvalid (s_rvalid[2]), .s_axi_rready (s_rready[2]),

      .m_axi_awaddr (m_awaddr[1]), .m_axi_awvalid(m_awvalid[1]), .m_axi_awready(m_awready[1]),
      .m_axi_wdata  (m_wdata[1]),  .m_axi_wstrb  (m_wstrb[1]),   .m_axi_wvalid (m_wvalid[1]),
      .m_axi_wready (m_wready[1]), .m_axi_bresp  (m_bresp[1]),   .m_axi_bvalid (m_bvalid[1]),
      .m_axi_bready (m_bready[1]), .m_axi_araddr (m_araddr[1]),  .m_axi_arvalid(m_arvalid[1]),
      .m_axi_arready(m_arready[1]),.m_axi_rdata  (m_rdata[1]),   .m_axi_rresp  (m_rresp[1]),
      .m_axi_rvalid (m_rvalid[1]), .m_axi_rready (m_rready[1]),
      .irq (fi_irq)
  );

  // ----------------------------------------------------- host = master 3 ---
  assign m_awaddr[3]  = host_awaddr;  assign m_awvalid[3] = host_awvalid;
  assign host_awready = m_awready[3];
  assign m_wdata[3]   = host_wdata;   assign m_wstrb[3]   = host_wstrb;
  assign m_wvalid[3]  = host_wvalid;  assign host_wready  = m_wready[3];
  assign host_bresp   = m_bresp[3];   assign host_bvalid  = m_bvalid[3];
  assign m_bready[3]  = host_bready;
  assign m_araddr[3]  = host_araddr;  assign m_arvalid[3] = host_arvalid;
  assign host_arready = m_arready[3];
  assign host_rdata   = m_rdata[3];   assign host_rresp   = m_rresp[3];
  assign host_rvalid  = m_rvalid[3];  assign m_rready[3]  = host_rready;

  // ---------------------------------------------------------- the fabric ---
  axi4lite_crossbar #(
      .NUM_MASTERS (NM),
      .NUM_SLAVES  (NS)
  ) u_xbar (
      .clk (clk), .rst_n (rst_n),
      .m_awaddr (m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
      .m_wdata  (m_wdata),  .m_wstrb  (m_wstrb),   .m_wvalid (m_wvalid), .m_wready(m_wready),
      .m_bresp  (m_bresp),  .m_bvalid (m_bvalid),  .m_bready (m_bready),
      .m_araddr (m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
      .m_rdata  (m_rdata),  .m_rresp  (m_rresp),   .m_rvalid (m_rvalid), .m_rready(m_rready),

      .s_awaddr (s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
      .s_wdata  (s_wdata),  .s_wstrb  (s_wstrb),   .s_wvalid (s_wvalid), .s_wready(s_wready),
      .s_bresp  (s_bresp),  .s_bvalid (s_bvalid),  .s_bready (s_bready),
      .s_araddr (s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
      .s_rdata  (s_rdata),  .s_rresp  (s_rresp),   .s_rvalid (s_rvalid), .s_rready(s_rready)
  );

  // ------------------------------------------------------------ memories ---
  // Same RTL as the simulation memory model. On the FPGA these were AXI BRAM
  // controllers outside the boundary; here they are flop arrays inside it.
  axi4lite_mem_model #(.MEM_WORDS(DMEM_WORDS)) u_dmem (
      .clk (clk), .rst_n (rst_n),
      .s_axi_awaddr (s_awaddr[0]), .s_axi_awvalid(s_awvalid[0]), .s_axi_awready(s_awready[0]),
      .s_axi_wdata  (s_wdata[0]),  .s_axi_wstrb  (s_wstrb[0]),   .s_axi_wvalid (s_wvalid[0]),
      .s_axi_wready (s_wready[0]), .s_axi_bresp  (s_bresp[0]),   .s_axi_bvalid (s_bvalid[0]),
      .s_axi_bready (s_bready[0]), .s_axi_araddr (s_araddr[0]),  .s_axi_arvalid(s_arvalid[0]),
      .s_axi_arready(s_arready[0]),.s_axi_rdata  (s_rdata[0]),   .s_axi_rresp  (s_rresp[0]),
      .s_axi_rvalid (s_rvalid[0]), .s_axi_rready (s_rready[0])
  );

  axi4lite_mem_model #(.MEM_WORDS(IMEM_WORDS)) u_imem (
      .clk (clk), .rst_n (rst_n),
      .s_axi_awaddr (s_awaddr[3]), .s_axi_awvalid(s_awvalid[3]), .s_axi_awready(s_awready[3]),
      .s_axi_wdata  (s_wdata[3]),  .s_axi_wstrb  (s_wstrb[3]),   .s_axi_wvalid (s_wvalid[3]),
      .s_axi_wready (s_wready[3]), .s_axi_bresp  (s_bresp[3]),   .s_axi_bvalid (s_bvalid[3]),
      .s_axi_bready (s_bready[3]), .s_axi_araddr (s_araddr[3]),  .s_axi_arvalid(s_arvalid[3]),
      .s_axi_arready(s_arready[3]),.s_axi_rdata  (s_rdata[3]),   .s_axi_rresp  (s_rresp[3]),
      .s_axi_rvalid (s_rvalid[3]), .s_axi_rready (s_rready[3])
  );

endmodule