// tb_alu.sv — complete self-checking testbench
module tb_alu;
    logic [31:0] a, b, result;
    logic [3:0]  alu_sel;
    logic        zero, overflow;

    alu dut (.*);

    int pass_count = 0;
    int fail_count = 0;

    task automatic check(
        input [31:0] exp_result,
        input        exp_zero,
        input string op_name
    );
        #1;
        if (result !== exp_result || zero !== exp_zero) begin
            $display("FAIL  %-10s | got result=%08h zero=%b | expected %08h %b",
                     op_name, result, zero, exp_result, exp_zero);
            fail_count++;
        end else begin
            $display("PASS  %-10s | result=%08h zero=%b",
                     op_name, result, zero);
            pass_count++;
        end
    endtask

    initial begin
        $display("=== ALU testbench ===");

        // ADD
        a = 32'h0000_0005; b = 32'h0000_0003; alu_sel = 4'b0000;
        check(32'h0000_0008, 1'b0, "ADD basic");

        // ADD producing zero
        a = 32'h0000_0001; b = 32'hFFFF_FFFF; alu_sel = 4'b0000;
        check(32'h0000_0000, 1'b1, "ADD zero flag");

        // SUB
        a = 32'h0000_0010; b = 32'h0000_0004; alu_sel = 4'b0001;
        check(32'h0000_000C, 1'b0, "SUB basic");

        // SUB producing zero (equal values — BEQ case)
        a = 32'h0000_00AA; b = 32'h0000_00AA; alu_sel = 4'b0001;
        check(32'h0000_0000, 1'b1, "SUB zero=BEQ");

        // AND
        a = 32'hFF00_FF00; b = 32'hF0F0_F0F0; alu_sel = 4'b0010;
        check(32'hF000_F000, 1'b0, "AND");

        // OR
        a = 32'hFF00_0000; b = 32'h00FF_0000; alu_sel = 4'b0011;
        check(32'hFFFF_0000, 1'b0, "OR");

        // XOR
        a = 32'hFFFF_FFFF; b = 32'hFFFF_FFFF; alu_sel = 4'b0100;
        check(32'h0000_0000, 1'b1, "XOR self");

        // SLT signed: -1 < 1 → true (result=1)
        a = 32'hFFFF_FFFF; b = 32'h0000_0001; alu_sel = 4'b0101;
        check(32'h0000_0001, 1'b0, "SLT -1<1");

        // SLT signed: 1 < -1 → false (result=0)
        a = 32'h0000_0001; b = 32'hFFFF_FFFF; alu_sel = 4'b0101;
        check(32'h0000_0000, 1'b1, "SLT 1<-1");

        // SLTU unsigned: 0xFFFFFFFF < 1 → false (it's huge unsigned)
        a = 32'hFFFF_FFFF; b = 32'h0000_0001; alu_sel = 4'b0110;
        check(32'h0000_0000, 1'b1, "SLTU big<1");

        // SLTU unsigned: 1 < 0xFFFFFFFF → true
        a = 32'h0000_0001; b = 32'hFFFF_FFFF; alu_sel = 4'b0110;
        check(32'h0000_0001, 1'b0, "SLTU 1<big");

        // SLL
        a = 32'h0000_0001; b = 32'h0000_0004; alu_sel = 4'b0111;
        check(32'h0000_0010, 1'b0, "SLL <<4");

        // SRL logical right shift — MSB fills with 0
        a = 32'h8000_0000; b = 32'h0000_0001; alu_sel = 4'b1000;
        check(32'h4000_0000, 1'b0, "SRL MSB→0");

        // SRA arithmetic right shift — MSB sign-extends
        a = 32'h8000_0000; b = 32'h0000_0001; alu_sel = 4'b1001;
        check(32'hC000_0000, 1'b0, "SRA MSB→1");

        // SRA on positive number — same as SRL
        a = 32'h4000_0000; b = 32'h0000_0001; alu_sel = 4'b1001;
        check(32'h2000_0000, 1'b0, "SRA pos");

        // LUI passthrough (pass B)
        a = 32'hDEAD_BEEF; b = 32'hABCD_0000; alu_sel = 4'b1010;
        check(32'hABCD_0000, 1'b0, "LUI pass-B");

        // Shift uses only low 5 bits of B
        a = 32'h0000_0001; b = 32'h0000_0021; alu_sel = 4'b0111; // 0x21 = 33, low 5 bits = 1
        check(32'h0000_0002, 1'b0, "SLL b[4:0]");

        $display("=== %0d passed, %0d failed ===", pass_count, fail_count);
        $finish;
    end
endmodule