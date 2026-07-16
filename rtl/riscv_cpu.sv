// riscv_cpu.sv — top level
// Instantiates all stages and pipeline registers
// Pipeline registers are plain always_ff blocks here

module riscv_cpu (
    input  logic        clk, rst,
    // debug / UART output port for FPGA
    output logic [31:0] debug_out
);

    // ══ IF/ID pipeline register ═══════════════════════════════════
    logic [31:0] if_id_pc, if_id_pc_plus4, if_id_instr;

    // ══ ID/EX pipeline register ═══════════════════════════════════
    logic [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    logic [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    logic [2:0]  id_ex_funct3;
    logic        id_ex_funct7_5;
    logic [6:0]  id_ex_opcode;
    logic        id_ex_reg_write, id_ex_mem_to_reg;
    logic        id_ex_mem_read,  id_ex_mem_write;
    logic        id_ex_branch,    id_ex_jump;
    logic        id_ex_alu_src;
    logic [1:0]  id_ex_alu_op;

    // ══ EX/MEM pipeline register ══════════════════════════════════
    logic [31:0] ex_mem_alu_result, ex_mem_rs2_data;
    logic [4:0]  ex_mem_rd;
    logic        ex_mem_reg_write, ex_mem_mem_to_reg;
    logic        ex_mem_mem_read,  ex_mem_mem_write;
    logic [2:0]  ex_mem_funct3;
    logic        ex_mem_branch_taken;
    logic [31:0] ex_mem_branch_target;

    // ══ MEM/WB pipeline register ══════════════════════════════════
    logic [31:0] mem_wb_alu_result, mem_wb_mem_data;
    logic [4:0]  mem_wb_rd;
    logic        mem_wb_reg_write, mem_wb_mem_to_reg;

    // ══ hazard and forwarding signals ═════════════════════════════
    logic        pc_write, if_id_write;
    logic        id_ex_flush, if_id_flush;
    logic [1:0]  forwardA, forwardB;

    // ══ stage outputs ═════════════════════════════════════════════
    logic [31:0] if_instr, if_pc, if_pc_plus4;
    logic [31:0] id_rd1, id_rd2, id_imm;
    logic [4:0]  id_rs1, id_rs2, id_rd;
    logic        id_reg_write, id_mem_to_reg;
    logic        id_mem_read,  id_mem_write;
    logic        id_branch,    id_jump, id_alu_src;
    logic [1:0]  id_alu_op;
    logic [31:0] ex_alu_result, ex_rs2_out;
    logic        ex_branch_taken;
    logic [31:0] ex_branch_target;
    logic [31:0] mem_mem_data;
    logic [31:0] wb_data;

    // ══ IF stage ══════════════════════════════════════════════════
    if_stage u_if (
        .clk            (clk),
        .rst            (rst),
        .pc_write       (pc_write),
        .pc_sel         (ex_mem_branch_taken),
        .branch_target  (ex_mem_branch_target),
        .instr          (if_instr),
        .pc             (if_pc),
        .pc_plus4       (if_pc_plus4)
    );

    // ══ IF/ID register ════════════════════════════════════════════
    always_ff @(posedge clk or posedge rst) begin
        if (rst || if_id_flush) begin
            if_id_instr    <= 32'h0000_0013; // NOP = ADDI x0,x0,0
            if_id_pc       <= 32'b0;
            if_id_pc_plus4 <= 32'b0;
        end else if (if_id_write) begin
            if_id_instr    <= if_instr;
            if_id_pc       <= if_pc;
            if_id_pc_plus4 <= if_pc_plus4;
        end
        // if_id_write=0 and no flush → hold value (stall)
    end

    // ══ ID stage ══════════════════════════════════════════════════
    id_stage u_id (
        .clk            (clk),
        .rst            (rst),
        .instr          (if_id_instr),
        .pc             (if_id_pc),
        .reg_write_wb   (mem_wb_reg_write),
        .rd_wb          (mem_wb_rd),
        .wd_wb          (wb_data),
        .reg_write      (id_reg_write),
        .mem_to_reg     (id_mem_to_reg),
        .mem_read       (id_mem_read),
        .mem_write      (id_mem_write),
        .branch         (id_branch),
        .alu_src        (id_alu_src),
        .alu_op         (id_alu_op),
        .jump           (id_jump),
        .rd1            (id_rd1),
        .rd2            (id_rd2),
        .imm            (id_imm),
        .rs1            (id_rs1),
        .rs2            (id_rs2),
        .rd             (id_rd)
    );

    // ══ ID/EX register ════════════════════════════════════════════
    always_ff @(posedge clk or posedge rst) begin
        if (rst || id_ex_flush) begin
            // flush → NOP bubble propagates into EX
            id_ex_pc         <= 32'b0;
            id_ex_rs1_data   <= 32'b0;
            id_ex_rs2_data   <= 32'b0;
            id_ex_imm        <= 32'b0;
            id_ex_rs1        <= 5'b0;
            id_ex_rs2        <= 5'b0;
            id_ex_rd         <= 5'b0;
            id_ex_funct3     <= 3'b0;
            id_ex_funct7_5   <= 1'b0;
            id_ex_opcode     <= 7'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
            id_ex_alu_src    <= 1'b0;
            id_ex_alu_op     <= 2'b0;
        end else begin
            id_ex_pc         <= if_id_pc;
            id_ex_rs1_data   <= id_rd1;
            id_ex_rs2_data   <= id_rd2;
            id_ex_imm        <= id_imm;
            id_ex_rs1        <= id_rs1;
            id_ex_rs2        <= id_rs2;
            id_ex_rd         <= id_rd;
            id_ex_funct3     <= if_id_instr[14:12];
            id_ex_funct7_5   <= if_id_instr[30];
            id_ex_opcode     <= if_id_instr[6:0];
            id_ex_reg_write  <= id_reg_write;
            id_ex_mem_to_reg <= id_mem_to_reg;
            id_ex_mem_read   <= id_mem_read;
            id_ex_mem_write  <= id_mem_write;
            id_ex_branch     <= id_branch;
            id_ex_jump       <= id_jump;
            id_ex_alu_src    <= id_alu_src;
            id_ex_alu_op     <= id_alu_op;
        end
    end

    // ══ EX stage ══════════════════════════════════════════════════
    ex_stage u_ex (
        .pc             (id_ex_pc),
        .rs1_data       (id_ex_rs1_data),
        .rs2_data       (id_ex_rs2_data),
        .imm            (id_ex_imm),
        .rs1            (id_ex_rs1),
        .rs2            (id_ex_rs2),
        .rd             (id_ex_rd),
        .alu_src        (id_ex_alu_src),
        .alu_op         (id_ex_alu_op),
        .branch         (id_ex_branch),
        .jump           (id_ex_jump),
        .funct3         (id_ex_funct3),
        .funct7_5       (id_ex_funct7_5),
        .opcode         (id_ex_opcode),
        .forwardA       (forwardA),
        .forwardB       (forwardB),
        .ex_mem_result  (ex_mem_alu_result),
        .mem_wb_data    (wb_data),
        .alu_result     (ex_alu_result),
        .rs2_out        (ex_rs2_out),
        .branch_taken   (ex_branch_taken),
        .branch_target  (ex_branch_target)
    );

    // ══ EX/MEM register ═══════════════════════════════════════════
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_alu_result    <= 32'b0;
            ex_mem_rs2_data      <= 32'b0;
            ex_mem_rd            <= 5'b0;
            ex_mem_reg_write     <= 1'b0;
            ex_mem_mem_to_reg    <= 1'b0;
            ex_mem_mem_read      <= 1'b0;
            ex_mem_mem_write     <= 1'b0;
            ex_mem_funct3        <= 3'b0;
            ex_mem_branch_taken  <= 1'b0;
            ex_mem_branch_target <= 32'b0;
        end else begin
            ex_mem_alu_result    <= ex_alu_result;
            ex_mem_rs2_data      <= ex_rs2_out;
            ex_mem_rd            <= id_ex_rd;
            ex_mem_reg_write     <= id_ex_reg_write;
            ex_mem_mem_to_reg    <= id_ex_mem_to_reg;
            ex_mem_mem_read      <= id_ex_mem_read;
            ex_mem_mem_write     <= id_ex_mem_write;
            ex_mem_funct3        <= id_ex_funct3;
            ex_mem_branch_taken  <= ex_branch_taken;
            ex_mem_branch_target <= ex_branch_target;
        end
    end

    // ══ MEM stage ═════════════════════════════════════════════════
    mem_stage u_mem (
        .clk        (clk),
        .mem_read   (ex_mem_mem_read),
        .mem_write  (ex_mem_mem_write),
        .funct3     (ex_mem_funct3),
        .alu_result (ex_mem_alu_result),
        .rs2_data   (ex_mem_rs2_data),
        .mem_data   (mem_mem_data)
    );

    // ══ MEM/WB register ═══════════════════════════════════════════
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_alu_result <= 32'b0;
            mem_wb_mem_data   <= 32'b0;
            mem_wb_rd         <= 5'b0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
        end else begin
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_data   <= mem_mem_data;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
        end
    end

    // ══ WB stage ══════════════════════════════════════════════════
    wb_stage u_wb (
        .mem_to_reg (mem_wb_mem_to_reg),
        .alu_result (mem_wb_alu_result),
        .mem_data   (mem_wb_mem_data),
        .wb_data    (wb_data)
    );

    // ══ hazard unit ═══════════════════════════════════════════════
    hazard_unit u_hazard (
        .id_ex_mem_read (id_ex_mem_read),
        .id_ex_rd       (id_ex_rd),
        .if_id_rs1      (if_id_instr[19:15]),
        .if_id_rs2      (if_id_instr[24:20]),
        .branch_taken   (ex_mem_branch_taken),
        .pc_write       (pc_write),
        .if_id_write    (if_id_write),
        .id_ex_flush    (id_ex_flush),
        .if_id_flush    (if_id_flush)
    );

    // ══ forwarding unit ═══════════════════════════════════════════
    forwarding_unit u_fwd (
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_rd       (ex_mem_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_rd       (mem_wb_rd),
        .forwardA        (forwardA),
        .forwardB        (forwardB)
    );

    // ══ debug output ══════════════════════════════════════════════
    // wire register x10 (a0) out for UART — bubble sort result lives here
    assign debug_out = u_id.u_regfile.regs[10];

endmodule