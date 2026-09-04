// cache_controller.sv
// MINERVA P3 - L1 Cache Controller
// Direct-mapped, 4KB, 16B (4-word) lines, write-back / write-allocate, blocking.
// CPU side: simple valid/ready local bus (matches P2 RV32I pipeline MEM stage).
// Memory side: AXI4-Lite master via axi4lite_master_engine (word-at-a-time,
// since AXI4-Lite has no burst -- line fill/writeback = 4 sequential txns).
//
// Address breakdown (32-bit):
//   [31:12] tag   (20 bits)
//   [11:4]  index (8 bits)   -> 256 lines
//   [3:2]   word  (2 bits)   -> 4 words/line
//   [1:0]   byte  (unused, word-aligned accesses only)

`include "axi4lite_ports.vh"

module cache_controller (
    input  logic        clk,
    input  logic        rst_n,

    // CPU side (simple bus, from P2 MEM stage)
    input  logic         cpu_req_valid,
    output logic         cpu_req_ready,
    input  logic [31:0]  cpu_req_addr,
    input  logic [31:0]  cpu_req_wdata,
    input  logic [3:0]   cpu_req_be,
    input  logic         cpu_req_we,

    output logic         cpu_resp_valid,
    output logic [31:0]  cpu_resp_rdata,

    // Memory side
    `AXI4LITE_MASTER_PORTS(m_axi)
);

  localparam int INDEX_BITS = 8;
  localparam int OFFSET_BITS = 2;   // word select within line (4 words)
  localparam int NUM_LINES = 1 << INDEX_BITS;
  localparam int TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS - 2;

  // ---------------- Tag / data / valid / dirty arrays ----------------
  logic [TAG_BITS-1:0] tag_array   [NUM_LINES];
  logic                valid_array [NUM_LINES];
  logic                dirty_array [NUM_LINES];
  logic [31:0]         data_array  [NUM_LINES][4]; // 4 words per line

  // ---------------- Address decode (registered request) ----------------
  logic [31:0] req_addr_q, req_wdata_q;
  logic [3:0]  req_be_q;
  logic        req_we_q;

  wire [TAG_BITS-1:0]   req_tag   = req_addr_q[31:12];
  wire [INDEX_BITS-1:0] req_index = req_addr_q[11:4];
  wire [1:0]            req_word  = req_addr_q[3:2];

  wire hit = valid_array[req_index] && (tag_array[req_index] == req_tag);

  // ---------------- AXI engine interface (local simple bus) ----------------
  logic        axi_req_valid, axi_req_ready, axi_req_we;
  logic [31:0] axi_req_addr, axi_req_wdata;
  logic [3:0]  axi_req_be;
  logic        axi_rdata_valid, axi_bresp_valid, axi_resp_err;
  logic [31:0] axi_rdata;

  axi4lite_master_engine u_axi_eng (
      .clk         (clk),
      .rst_n       (rst_n),
      .req_valid   (axi_req_valid),
      .req_ready   (axi_req_ready),
      .req_addr    (axi_req_addr),
      .req_wdata   (axi_req_wdata),
      .req_be      (axi_req_be),
      .req_we      (axi_req_we),
      .rdata_valid (axi_rdata_valid),
      .rdata       (axi_rdata),
      .bresp_valid (axi_bresp_valid),
      .resp_err    (axi_resp_err),
      .m_axi_awaddr (m_axi_awaddr),   .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
      .m_axi_wdata  (m_axi_wdata),    .m_axi_wstrb  (m_axi_wstrb),   .m_axi_wvalid (m_axi_wvalid), .m_axi_wready(m_axi_wready),
      .m_axi_bresp  (m_axi_bresp),    .m_axi_bvalid (m_axi_bvalid),  .m_axi_bready (m_axi_bready),
      .m_axi_araddr (m_axi_araddr),   .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
      .m_axi_rdata  (m_axi_rdata),    .m_axi_rresp  (m_axi_rresp),   .m_axi_rvalid (m_axi_rvalid), .m_axi_rready(m_axi_rready)
  );

  // ---------------- FSM ----------------
  typedef enum logic [2:0] {
    IDLE,
    TAG_CHECK,
    HIT_DONE,
    WRITEBACK,   // evict dirty line: 4 sequential AXI writes
    ALLOCATE     // fill new line: 4 sequential AXI reads
  } state_e;

  state_e state_q;
  logic [1:0] beat_cnt_q; // 0..3, tracks word within line for WB/ALLOC

  assign cpu_req_ready = (state_q == IDLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q     <= IDLE;
      beat_cnt_q  <= 2'd0;
      req_addr_q  <= '0;
      req_wdata_q <= '0;
      req_be_q    <= '0;
      req_we_q    <= 1'b0;
      cpu_resp_valid <= 1'b0;
      cpu_resp_rdata <= '0;
      axi_req_valid  <= 1'b0;
      axi_req_we     <= 1'b0;
      axi_req_addr   <= '0;
      axi_req_wdata  <= '0;
      axi_req_be     <= '0;
      for (int i = 0; i < NUM_LINES; i++) begin
        valid_array[i] <= 1'b0;
        dirty_array[i] <= 1'b0;
      end
    end else begin
      cpu_resp_valid <= 1'b0;
      axi_req_valid  <= 1'b0; // default deassert, pulsed below

      unique case (state_q)

        IDLE: begin
          if (cpu_req_valid) begin
            req_addr_q  <= cpu_req_addr;
            req_wdata_q <= cpu_req_wdata;
            req_be_q    <= cpu_req_be;
            req_we_q    <= cpu_req_we;
            state_q     <= TAG_CHECK;
          end
        end

        TAG_CHECK: begin
          if (hit) begin
            if (req_we_q) begin
              // write hit: update line, mark dirty, no memory access
              for (int b = 0; b < 4; b++)
                if (req_be_q[b])
                  data_array[req_index][req_word][b*8 +: 8] <= req_wdata_q[b*8 +: 8];
              dirty_array[req_index] <= 1'b1;
            end else begin
              cpu_resp_rdata <= data_array[req_index][req_word];
            end
            cpu_resp_valid <= 1'b1;
            state_q <= IDLE;
          end else begin
            // miss: evict first if dirty, else allocate directly
            beat_cnt_q <= 2'd0;
            if (valid_array[req_index] && dirty_array[req_index])
              state_q <= WRITEBACK;
            else
              state_q <= ALLOCATE;
          end
        end

        WRITEBACK: begin
          // issue one AXI write beat per line word; advance on bresp
          if (axi_req_ready && !axi_bresp_valid) begin
            axi_req_valid <= 1'b1;
            axi_req_we    <= 1'b1;
            axi_req_addr  <= {tag_array[req_index], req_index, beat_cnt_q, 2'b00};
            axi_req_wdata <= data_array[req_index][beat_cnt_q];
            axi_req_be    <= 4'hF;
          end
          if (axi_bresp_valid) begin
            if (beat_cnt_q == 2'd3) begin
              dirty_array[req_index] <= 1'b0;
              beat_cnt_q <= 2'd0;
              state_q    <= ALLOCATE;
            end else begin
              beat_cnt_q <= beat_cnt_q + 2'd1;
            end
          end
        end

        ALLOCATE: begin
          if (axi_req_ready && !axi_rdata_valid) begin
            axi_req_valid <= 1'b1;
            axi_req_we    <= 1'b0;
            axi_req_addr  <= {req_tag, req_index, beat_cnt_q, 2'b00};
          end
          if (axi_rdata_valid) begin
            data_array[req_index][beat_cnt_q] <= axi_rdata;
            if (beat_cnt_q == 2'd3) begin
              tag_array[req_index]   <= req_tag;
              valid_array[req_index] <= 1'b1;
              dirty_array[req_index] <= 1'b0;
              beat_cnt_q <= 2'd0;
              state_q    <= TAG_CHECK; // re-check: will hit now, completes req
            end else begin
              beat_cnt_q <= beat_cnt_q + 2'd1;
            end
          end
        end

        default: state_q <= IDLE;
      endcase
    end
  end

endmodule : cache_controller