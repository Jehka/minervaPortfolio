`timescale 1ns/1ps

module tb_riscv_cpu;

    logic        clk, rst;
    logic [31:0] debug_out;

    riscv_cpu dut (
        .clk       (clk),
        .rst       (rst),
        .debug_out (debug_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(500) @(posedge clk);
        $display("=========================");
        $display("debug_out (a0) = %0d", debug_out);
        $display("=========================");
        $finish;
    end

endmodule