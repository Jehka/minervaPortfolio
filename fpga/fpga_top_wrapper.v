module fpga_top_wrapper (
    input  wire        clk,       // 100MHz from PS FCLK_CLK0
    input  wire        rst_n,     // active-low from PS reset
    output wire [31:0] debug_out,
    output wire [7:0]  led
);

    wire rst = ~rst_n;

    // Clock divider: 100MHz → ~1.5Hz for visible LED blink
    reg [25:0] clk_div;
    always @(posedge clk or posedge rst) begin
        if (rst)
            clk_div <= 0;
        else
            clk_div <= clk_div + 1'b1;
    end

    // === PHASE 1: Use slow clock so LEDs blink ===
    wire cpu_clk = clk_div[25];   // CHANGE TO 'clk' FOR PHASE 2

    riscv_cpu cpu (
        .clk       (cpu_clk),
        .rst       (rst),
        .debug_out (debug_out)
    );

    assign led = debug_out[7:0];

endmodule