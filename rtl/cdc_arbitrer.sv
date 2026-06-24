`timescale 1ns / 1ps
`default_nettype none

module cdc_arbiter #(
    parameter int NUM_SOURCES  = 4,
    parameter int DATA_WIDTH   = 64,
    parameter int TS_WIDTH     = 64,
    parameter int FIFO_DEPTH   = 1024,
    parameter int PACKET_BEATS = 256
)(
    input  wire wclk, wrst_n,
    input  wire [NUM_SOURCES-1:0]            s_tvalid,
    input  wire [NUM_SOURCES*DATA_WIDTH-1:0] s_tdata,   
    output logic [NUM_SOURCES-1:0]           s_tready,

    input  wire rclk, rrst_n,
    output logic                             m_tvalid,
    output logic [DATA_WIDTH-1:0]            m_tdata,
    output logic [ID_W-1:0]                  m_tid,
    output logic [TS_WIDTH-1:0]              m_tuser,
    output logic                             m_tlast,
    input  wire                              m_tready
);

    localparam int ID_W       = (NUM_SOURCES > 1) ? $clog2(NUM_SOURCES) : 1; 
    localparam int FIFO_WIDTH = 1 + TS_WIDTH + ID_W + DATA_WIDTH;

    // Unpack flat bus → array for arbiter
    logic [DATA_WIDTH-1:0] s_tdata_arr [NUM_SOURCES];
    always_comb
        for (int i = 0; i < NUM_SOURCES; i++)
            s_tdata_arr[i] = s_tdata[i*DATA_WIDTH +: DATA_WIDTH];

    // ---- Timestamp engine ----
    logic [TS_WIDTH-1:0] current_time;
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) current_time <= '0;
        else         current_time <= current_time + 1'b1;
    end

    // ---- Arbiter ----
    logic                  arb_tvalid, arb_tready;
    logic [DATA_WIDTH-1:0] arb_tdata;
    logic [ID_W-1:0]       arb_tid;

    rr_arbiter #(
        .NUM_SOURCES (NUM_SOURCES),
        .DATA_WIDTH  (DATA_WIDTH),
        .ID_W        (ID_W)
    ) u_arb (
        .clk       (wclk),      .rst_n     (wrst_n),
        .s_tvalid  (s_tvalid),  .s_tdata   (s_tdata_arr),
        .s_tready  (s_tready),
        .arb_tvalid(arb_tvalid),.arb_tdata (arb_tdata),
        .arb_tid   (arb_tid),   .arb_tready(arb_tready)
    );

    // ---- TLAST beat counter ----
    logic [$clog2(PACKET_BEATS)-1:0] beat_count;
    wire  arb_handshake = arb_tvalid && arb_tready;

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) beat_count <= '0;
        else if (arb_handshake)
            beat_count <= (beat_count == PACKET_BEATS-1) ? '0 : beat_count + 1;
    end
    wire arb_tlast = (beat_count == PACKET_BEATS - 1);

    // ---- XPM async FIFO ----
    logic [FIFO_WIDTH-1:0] fifo_din, fifo_dout;
    logic                  fifo_full, fifo_empty, fifo_rd_en;

    assign fifo_din   = {arb_tlast, current_time, arb_tid, arb_tdata};
    assign arb_tready = ~fifo_full;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE ("block"),
        .READ_MODE        ("fwft"),
        .FIFO_WRITE_DEPTH (FIFO_DEPTH),
        .WRITE_DATA_WIDTH (FIFO_WIDTH),
        .READ_DATA_WIDTH  (FIFO_WIDTH),
        .CDC_SYNC_STAGES  (2)
    ) u_xpm_fifo (
        .wr_clk(wclk),  .rst(~wrst_n),
        .din(fifo_din), .wr_en(arb_handshake), .full(fifo_full),   
        .rd_clk(rclk),  .dout(fifo_dout), .rd_en(fifo_rd_en), .empty(fifo_empty),
        .sleep(1'b0),   .injectsbiterr(1'b0), .injectdbiterr(1'b0)
    );

    // ---- Output controller ----
    logic [FIFO_WIDTH-1:0] m_tdata_raw;

    fifo_output_ctrl #(.FIFO_WIDTH(FIFO_WIDTH)) u_out_ctrl (
        .rclk       (rclk),       .rrst_n     (rrst_n),
        .fifo_empty (fifo_empty), .fifo_dout  (fifo_dout),
        .rd_en      (fifo_rd_en),
        .m_tvalid   (m_tvalid),   .m_tdata_raw(m_tdata_raw),
        .m_tready   (m_tready)
    );

    // Unbundle output
    assign m_tlast = m_tdata_raw[FIFO_WIDTH-1];
    assign m_tuser = m_tdata_raw[FIFO_WIDTH-2 : DATA_WIDTH+ID_W];
    assign m_tid   = m_tdata_raw[DATA_WIDTH+ID_W-1 : DATA_WIDTH];
    assign m_tdata = m_tdata_raw[DATA_WIDTH-1 : 0];

endmodule