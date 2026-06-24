`timescale 1ns / 1ps
// Behavioral stub for xpm_fifo_async — FWFT mode, single-clock-domain sim safe.
// Replace with real XPM when targeting Vivado elaboration/synthesis.
module xpm_fifo_async #(
    parameter FIFO_MEMORY_TYPE = "block",
    parameter READ_MODE        = "fwft",
    parameter FIFO_WRITE_DEPTH = 1024,
    parameter WRITE_DATA_WIDTH = 8,
    parameter READ_DATA_WIDTH  = 8,
    parameter CDC_SYNC_STAGES  = 2
)(
    input  logic                        wr_clk, rd_clk, rst,
    input  logic [WRITE_DATA_WIDTH-1:0] din,
    input  logic                        wr_en,
    output logic                        full,
    output logic [READ_DATA_WIDTH-1:0]  dout,
    input  logic                        rd_en,
    output logic                        empty,
    input  logic                        sleep,
    input  logic                        injectsbiterr,
    input  logic                        injectdbiterr
);
    localparam DEPTH = FIFO_WRITE_DEPTH;
    logic [WRITE_DATA_WIDTH-1:0] mem [0:DEPTH-1];
    int wr_ptr = 0, rd_ptr = 0, count = 0;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign dout  = mem[rd_ptr]; // FWFT: data always on output

    always @(posedge wr_clk) begin
        if (rst) begin wr_ptr <= 0; rd_ptr <= 0; count <= 0; end
        else if (wr_en && !full) begin
            mem[wr_ptr] <= din;
            wr_ptr <= (wr_ptr + 1) % DEPTH;
            count  <= count + 1;
        end
    end

    always @(posedge rd_clk) begin
        if (rst) begin end
        else if (rd_en && !empty) begin
            rd_ptr <= (rd_ptr + 1) % DEPTH;
            count  <= count - 1;
        end
    end
endmodule