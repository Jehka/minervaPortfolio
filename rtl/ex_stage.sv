// ex_stage.sv - execute stage
// Forwarding muxes, ALU, branch resolution, branch target

module ex_stage (
    // data from ID/EX register
    input  logic [31:0] pc,
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [31:0] imm,
    input  logic [4:0]  rs1, rs2, rd,
    // control signals from ID/EX register
    input  logic        alu_src,
    input  logic [1:0]  alu_op,
    input  logic        branch,
    input  logic        jump,
    input  logic [2:0]  funct3,
    input  logic        funct7_5,
    input  logic [6:0]  opcode,
    // forwarding inputs
    input  logic [1:0]  forwardA,       // from forwarding unit
    input  logic [1:0]  forwardB,       // from forwarding unit
    input  logic [31:0] ex_mem_result,  // EX/MEM alu result
    input  logic [31:0] mem_wb_data,    // MEM/WB writeback data
    // outputs → EX/MEM register
    output logic [31:0] alu_result,
    output logic [31:0] rs2_out,        // forwarded rs2 - needed for stores
    output logic        branch_taken,
    output logic [31:0] branch_target
);

    // ── forwarding mux A ─────────────────────────────────────────
    logic [31:0] fwd_a;
    always_comb begin
        case (forwardA)
            2'b10:   fwd_a = ex_mem_result;
            2'b01:   fwd_a = mem_wb_data;
            default: fwd_a = rs1_data;
        endcase
    end

    // ── forwarding mux B ─────────────────────────────────────────
    logic [31:0] fwd_b;
    always_comb begin
        case (forwardB)
            2'b10:   fwd_b = ex_mem_result;
            2'b01:   fwd_b = mem_wb_data;
            default: fwd_b = rs2_data;
        endcase
    end

    // rs2_out carries the forwarded rs2 value to EX/MEM
    // stores need this - the ALU computes the address, not the store data
    assign rs2_out = fwd_b;

    // ── AUIPC: select PC as ALU A input ──────────────────────────
    logic [31:0] alu_a;
    assign alu_a = (opcode == 7'b0010111) ? pc : fwd_a;

    // ── ALU B input mux ──────────────────────────────────────────
    // alu_src=1 → immediate, alu_src=0 → forwarded rs2
    logic [31:0] alu_b;
    assign alu_b = alu_src ? imm : fwd_b;

    // ── alu_decoder ───────────────────────────────────────────────
    logic [3:0] alu_sel;
    alu_decoder u_alu_decoder (
        .alu_op   (alu_op),
        .funct3   (funct3),
        .funct7_5 (funct7_5),
        .op_bit5  (opcode[5]),
        .alu_sel  (alu_sel)
    );

    // ── ALU ───────────────────────────────────────────────────────
    logic        zero, overflow;
    alu u_alu (
        .a        (alu_a),
        .b        (alu_b),
        .alu_sel  (alu_sel),
        .result   (alu_result),
        .zero     (zero),
        .overflow (overflow)
    );

    // ── branch target ─────────────────────────────────────────────
    // all branches and JAL: PC + imm
    // JALR: rs1 + imm (use alu_result directly - ALU already computed it)
    assign branch_target = (opcode == 7'b1100111) ?
                            {alu_result[31:1], 1'b0} : // JALR - clear bit 0
                            pc + imm;                  // JAL, branches

    // ── branch decision ───────────────────────────────────────────
    logic branch_condition;
    always_comb begin
        case (funct3)
            3'b000: branch_condition =  zero;                    // BEQ
            3'b001: branch_condition = ~zero;                    // BNE
            3'b100: branch_condition =  (alu_result[31] ^ overflow); // BLT
            3'b101: branch_condition = ~(alu_result[31] ^ overflow); // BGE
            3'b110: branch_condition = ~zero & ~overflow;        // BLTU
            3'b111: branch_condition =  zero |  overflow;        // BGEU
            default: branch_condition = 1'b0;
        endcase
    end

    // branch taken if instruction is a branch AND condition is true
    // OR if instruction is a jump (always taken)
    assign branch_taken = (branch & branch_condition) | jump;

endmodule