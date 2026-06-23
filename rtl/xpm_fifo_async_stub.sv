module xpm_fifo_async #(
    parameter FIFO_WRITE_DEPTH = 1024,
    parameter WRITE_DATA_WIDTH = 128,
    parameter READ_DATA_WIDTH  = 128
)(
    input  wire wr_clk,
    input  wire rd_clk,
    input  wire rst,

    input  wire [WRITE_DATA_WIDTH-1:0] din,
    input  wire wr_en,
    output wire full,

    output reg  [READ_DATA_WIDTH-1:0] dout,
    input  wire rd_en,
    output wire empty,

    input wire sleep,
    input wire injectsbiterr,
    input wire injectdbiterr
);

    reg [WRITE_DATA_WIDTH-1:0] mem [0:FIFO_WRITE_DEPTH-1];

    integer wr_ptr;
    integer rd_ptr;
    integer count;

    assign full  = (count == FIFO_WRITE_DEPTH);
    assign empty = (count == 0);

    always @(posedge wr_clk)
    begin
        if (rst)
        begin
            wr_ptr <= 0;
            count  <= 0;
        end
        else if (wr_en && !full)
        begin
            mem[wr_ptr] <= din;
            wr_ptr <= (wr_ptr + 1) % FIFO_WRITE_DEPTH;
            count <= count + 1;
        end
    end

    always @(posedge rd_clk)
    begin
        if (rd_en && !empty)
        begin
            dout <= mem[rd_ptr];
            rd_ptr <= (rd_ptr + 1) % FIFO_WRITE_DEPTH;
            count <= count - 1;
        end
    end

endmodule