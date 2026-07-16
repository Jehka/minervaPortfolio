// hazard_unit.sv - stall and flush control
// Purely combinational - detects load-use hazards and branch flushes

module hazard_unit (
    // load-use hazard detection
    input  logic       id_ex_mem_read,
    input  logic [4:0] id_ex_rd,
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,
    // branch flush
    input  logic       branch_taken,
    // stall outputs
    output logic       pc_write,      // 0 = freeze PC
    output logic       if_id_write,   // 0 = freeze IF/ID register
    output logic       id_ex_flush,   // 1 = insert NOP into ID/EX
    // flush outputs
    output logic       if_id_flush    // 1 = flush IF/ID on branch
);

    logic load_use_stall;

    // ── load-use hazard ───────────────────────────────────────────
    // EX stage has a load, and ID stage needs that register
    // one bubble required - forwarding cannot help here
    // (data isn't available until end of MEM stage)
    assign load_use_stall = id_ex_mem_read &&
                            ((id_ex_rd == if_id_rs1) ||
                             (id_ex_rd == if_id_rs2)) &&
                            (id_ex_rd != 5'b0);

    assign pc_write    = ~load_use_stall;
    assign if_id_write = ~load_use_stall;
    assign id_ex_flush =  load_use_stall;

    // ── branch flush ──────────────────────────────────────────────
    // branch resolved in EX - IF and ID fetched wrong-path instructions
    // flush both IF/ID and ID/EX by turning them into NOPs
    assign if_id_flush = branch_taken;

endmodule