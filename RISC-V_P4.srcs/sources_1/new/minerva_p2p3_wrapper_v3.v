// minerva_p2p3_wrapper.v (v3)
// Plain-Verilog top wrapper around riscv_cpu_p3 for Vivado IP Integrator.
//
// CHANGE FROM v2: dma_reg was tied off to constants in v2 -- that was a
// deliberate diagnostic simplification for isolating the ext_mem/AXI hang
// bug during P3 bring-up, made before dma_reg needed to go anywhere. For
// P4, dma_reg must actually reach axi4lite_crossbar Slave 1 (so it's
// "the external agent" the riscv_cpu_p3.sv comment refers to). This
// version exposes dma_reg as real flat ports instead.
//
// debug_out / mem_stall_out / if_pc_out unchanged from v2.

module minerva_p2p3_wrapper (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] debug_out,
    output wire         mem_stall_out,
    output wire [31:0]  if_pc_out,

    // ---------------- dma_reg: AXI4-Lite SLAVE, from crossbar Slave 1 ----
    input  wire [31:0] dma_reg_awaddr,
    input  wire        dma_reg_awvalid,
    output wire        dma_reg_awready,
    input  wire [31:0] dma_reg_wdata,
    input  wire [3:0]  dma_reg_wstrb,
    input  wire        dma_reg_wvalid,
    output wire        dma_reg_wready,
    output wire [1:0]  dma_reg_bresp,
    output wire        dma_reg_bvalid,
    input  wire        dma_reg_bready,
    input  wire [31:0] dma_reg_araddr,
    input  wire        dma_reg_arvalid,
    output wire        dma_reg_arready,
    output wire [31:0] dma_reg_rdata,
    output wire [1:0]  dma_reg_rresp,
    output wire        dma_reg_rvalid,
    input  wire        dma_reg_rready,

    output wire        dma_irq,

    // ---------------- ext_mem: AXI4-Lite MASTER, to crossbar Master 0 ----
    output wire [31:0] ext_mem_awaddr,
    output wire        ext_mem_awvalid,
    input  wire        ext_mem_awready,
    output wire [31:0] ext_mem_wdata,
    output wire [3:0]  ext_mem_wstrb,
    output wire        ext_mem_wvalid,
    input  wire        ext_mem_wready,
    input  wire [1:0]  ext_mem_bresp,
    input  wire        ext_mem_bvalid,
    output wire        ext_mem_bready,
    output wire [31:0] ext_mem_araddr,
    output wire        ext_mem_arvalid,
    input  wire        ext_mem_arready,
    input  wire [31:0] ext_mem_rdata,
    input  wire [1:0]  ext_mem_rresp,
    input  wire        ext_mem_rvalid,
    output wire        ext_mem_rready
);

    riscv_cpu_p3 u_cpu (
        .clk        (clk),
        .rst        (rst),
        .debug_out  (debug_out),
        .mem_stall_out (mem_stall_out),
        .if_pc_out     (if_pc_out),

        .dma_reg_awaddr  (dma_reg_awaddr),
        .dma_reg_awvalid (dma_reg_awvalid),
        .dma_reg_awready (dma_reg_awready),
        .dma_reg_wdata   (dma_reg_wdata),
        .dma_reg_wstrb   (dma_reg_wstrb),
        .dma_reg_wvalid  (dma_reg_wvalid),
        .dma_reg_wready  (dma_reg_wready),
        .dma_reg_bresp   (dma_reg_bresp),
        .dma_reg_bvalid  (dma_reg_bvalid),
        .dma_reg_bready  (dma_reg_bready),
        .dma_reg_araddr  (dma_reg_araddr),
        .dma_reg_arvalid (dma_reg_arvalid),
        .dma_reg_arready (dma_reg_arready),
        .dma_reg_rdata   (dma_reg_rdata),
        .dma_reg_rresp   (dma_reg_rresp),
        .dma_reg_rvalid  (dma_reg_rvalid),
        .dma_reg_rready  (dma_reg_rready),

        .dma_irq (dma_irq),

        .ext_mem_awaddr  (ext_mem_awaddr),
        .ext_mem_awvalid (ext_mem_awvalid),
        .ext_mem_awready (ext_mem_awready),
        .ext_mem_wdata   (ext_mem_wdata),
        .ext_mem_wstrb   (ext_mem_wstrb),
        .ext_mem_wvalid  (ext_mem_wvalid),
        .ext_mem_wready  (ext_mem_wready),
        .ext_mem_bresp   (ext_mem_bresp),
        .ext_mem_bvalid  (ext_mem_bvalid),
        .ext_mem_bready  (ext_mem_bready),
        .ext_mem_araddr  (ext_mem_araddr),
        .ext_mem_arvalid (ext_mem_arvalid),
        .ext_mem_arready (ext_mem_arready),
        .ext_mem_rdata   (ext_mem_rdata),
        .ext_mem_rresp   (ext_mem_rresp),
        .ext_mem_rvalid  (ext_mem_rvalid),
        .ext_mem_rready  (ext_mem_rready)
    );

endmodule