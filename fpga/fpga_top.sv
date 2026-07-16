module fpga_top (
    input  logic clk,
    input  logic rst_n, 
    output logic [31:0] debug_out
);

    logic rst;
    assign rst = ~rst_n; // Invert to active-high for the CPU

    riscv_cpu u_cpu (
        .clk       (clk),
        .rst       (rst),
        .debug_out (debug_out)
    );

endmodule