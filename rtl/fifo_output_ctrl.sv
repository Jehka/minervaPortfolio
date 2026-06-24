`timescale 1ns / 1ps
`default_nettype none

module fifo_output_ctrl #(
    parameter int FIFO_WIDTH = 140
)(
    input  wire                   rclk, rrst_n,
    // XPM FIFO read-side signals
    input  wire                   fifo_empty,
    input  wire [FIFO_WIDTH-1:0]  fifo_dout,
    output logic                  rd_en,
    // AXI-S master
    output logic                  m_tvalid,
    output logic [FIFO_WIDTH-1:0] m_tdata_raw,
    input  wire                   m_tready
);

    logic valid_reg;

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) valid_reg <= 1'b0;
        else begin
            if (!fifo_empty && (!valid_reg || m_tready))
                valid_reg <= 1'b1;
            else if (m_tready)
                valid_reg <= 1'b0;
        end
    end

    assign rd_en       = !fifo_empty && (!valid_reg || m_tready);
    assign m_tvalid    = valid_reg;
    assign m_tdata_raw = fifo_dout;

endmodule