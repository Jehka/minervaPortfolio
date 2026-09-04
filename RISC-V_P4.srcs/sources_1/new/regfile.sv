// regfile.sv - 32x32 register file, RV32I
// Two async read ports, one sync write port, write-first on collision
// x0 hardwired to zero

module regfile (
    input  logic        clk,
    input  logic        we,
    input  logic [4:0]  rs1, rs2,
    input  logic [4:0]  rd,
    input  logic [31:0] wd,
    output logic [31:0] rd1, rd2
);

    logic [31:0] regs [31:0];

    // Synchronous write - x0 write is silently ignored
    always_ff @(posedge clk) begin
        if (we && rd != 5'b0)
            regs[rd] <= wd;
    end

    // Async read - write-first forwarding on address match
    assign rd1 = (rs1 == 5'b0)              ? 32'b0 :
                 (we && rd == rs1) ? wd              :
                 regs[rs1];

    assign rd2 = (rs2 == 5'b0)              ? 32'b0 :
                 (we && rd == rs2) ? wd              :
                 regs[rs2];

endmodule