// mem_stage.sv - data memory access
// Handles byte/halfword/word loads and stores with sign extension

module mem_stage (
    input  logic        clk,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [2:0]  funct3,
    input  logic [31:0] alu_result,   // memory address
    input  logic [31:0] rs2_data,     // store data
    output logic [31:0] mem_data      // load data out
);

    logic [31:0] dmem [0:1023];

    initial begin
    integer i;
    for (i = 0; i < 1024; i = i + 1)
        dmem[i] = 32'b0;

    // New array: minimum is 4
    // Sorted result: [4, 4, 5, 5, 6, 6, 7, 8, 8, 9]
    dmem[128] = 32'd5;
    dmem[129] = 32'd4;
    dmem[130] = 32'd8;
    dmem[131] = 32'd6;
    dmem[132] = 32'd9;
    dmem[133] = 32'd7;
    dmem[134] = 32'd6;
    dmem[135] = 32'd4;
    dmem[136] = 32'd8;
    dmem[137] = 32'd5;
end
    // ── synchronous write ─────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000: begin // SB - store byte
                    case (alu_result[1:0])
                        2'b00: dmem[alu_result[11:2]][7:0]   <= rs2_data[7:0];
                        2'b01: dmem[alu_result[11:2]][15:8]  <= rs2_data[7:0];
                        2'b10: dmem[alu_result[11:2]][23:16] <= rs2_data[7:0];
                        2'b11: dmem[alu_result[11:2]][31:24] <= rs2_data[7:0];
                    endcase
                end
                3'b001: begin // SH - store halfword
                    case (alu_result[1])
                        1'b0: dmem[alu_result[11:2]][15:0]  <= rs2_data[15:0];
                        1'b1: dmem[alu_result[11:2]][31:16] <= rs2_data[15:0];
                    endcase
                end
                3'b010: dmem[alu_result[11:2]] <= rs2_data; // SW
                default: dmem[alu_result[11:2]] <= rs2_data;
            endcase
        end
    end

    // ── combinational read with sign extension ────────────────────
    logic [31:0] raw_word;
    assign raw_word = dmem[alu_result[11:2]];

    always_comb begin
        mem_data = 32'b0;
        if (mem_read) begin
            case (funct3)
                3'b000: begin // LB - sign extend byte
                    case (alu_result[1:0])
                        2'b00: mem_data = {{24{raw_word[7]}},  raw_word[7:0]};
                        2'b01: mem_data = {{24{raw_word[15]}}, raw_word[15:8]};
                        2'b10: mem_data = {{24{raw_word[23]}}, raw_word[23:16]};
                        2'b11: mem_data = {{24{raw_word[31]}}, raw_word[31:24]};
                    endcase
                end
                3'b001: begin // LH - sign extend halfword
                    case (alu_result[1])
                        1'b0: mem_data = {{16{raw_word[15]}}, raw_word[15:0]};
                        1'b1: mem_data = {{16{raw_word[31]}}, raw_word[31:16]};
                    endcase
                end
                3'b010: mem_data = raw_word; // LW
                3'b100: begin // LBU - zero extend
                    case (alu_result[1:0])
                        2'b00: mem_data = {24'b0, raw_word[7:0]};
                        2'b01: mem_data = {24'b0, raw_word[15:8]};
                        2'b10: mem_data = {24'b0, raw_word[23:16]};
                        2'b11: mem_data = {24'b0, raw_word[31:24]};
                    endcase
                end
                3'b101: begin // LHU - zero extend
                    case (alu_result[1])
                        1'b0: mem_data = {16'b0, raw_word[15:0]};
                        1'b1: mem_data = {16'b0, raw_word[31:16]};
                    endcase
                end
                default: mem_data = raw_word;
            endcase
        end
    end

endmodule