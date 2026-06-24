// cdc_arbiter_wrap.v
// Plain Verilog wrapper around cdc_arbiter.sv for Vivado Block Design compatibility.
module cdc_arbiter_wrap (
    input  wire         wclk,
    input  wire         wrst_n,
    input  wire [3:0]   s_tvalid,
    input  wire [255:0] s_tdata,
    output wire [3:0]   s_tready,
    input  wire         rclk,
    input  wire         rrst_n,
    output wire         m_tvalid,
    output wire [63:0]  m_tdata,
    output wire [1:0]   m_tid,
    output wire [63:0]  m_tuser,
    output wire         m_tlast,
    input  wire         m_tready
);

    cdc_arbiter #(
        .NUM_SOURCES  (4),
        .DATA_WIDTH   (64),
        .TS_WIDTH     (64),
        .FIFO_DEPTH   (1024),
        .PACKET_BEATS (256)
    ) u_cdc (
        .wclk     (wclk),
        .wrst_n   (wrst_n),
        .s_tvalid (s_tvalid),
        .s_tdata  (s_tdata),
        .s_tready (s_tready),
        .rclk     (rclk),
        .rrst_n   (rrst_n),
        .m_tvalid (m_tvalid),
        .m_tdata  (m_tdata),
        .m_tid    (m_tid),
        .m_tuser  (m_tuser),
        .m_tlast  (m_tlast),
        .m_tready (m_tready)
    );

endmodule