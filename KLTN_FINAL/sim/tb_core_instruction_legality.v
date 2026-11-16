`timescale 1ns / 1ps

// Focused decoder regression for legal and reserved RV32IMA encodings.  This
// complements the architectural execution test by proving that a recognized
// opcode with an illegal funct field cannot silently execute as another op.
module tb_core_instruction_legality;
    reg  [31:0] instr;
    wire is_system;
    wire is_csr;
    wire is_priv;
    wire is_ecall;
    wire is_ebreak;
    wire is_mret;
    wire is_sret;
    wire is_wfi;
    wire is_sfence_vma;
    wire is_priv_illegal;
    wire is_illegal;
    integer errors;

    sys_decoder dut (
        .InstrD(instr), .OpD(instr[6:0]),
        .IsSystemD(is_system), .IsCsrD(is_csr), .IsPrivD(is_priv),
        .IsEcallD(is_ecall), .IsEbreakD(is_ebreak),
        .IsMretD(is_mret), .IsSretD(is_sret), .IsWfiD(is_wfi),
        .IsSfenceVmaD(is_sfence_vma),
        .IsPrivIllegalD(is_priv_illegal), .IsIllegalOpD(is_illegal)
    );

    task check_decode;
        input [31:0] value;
        input expected_illegal;
        input expected_priv_illegal;
        input [8*40-1:0] label_text;
        begin
            instr = value;
            #1;
            if ((is_illegal !== expected_illegal) ||
                (is_priv_illegal !== expected_priv_illegal)) begin
                $display("[FAIL] %0s instr=%08x illegal=%b/%b priv=%b/%b",
                         label_text, value, is_illegal, expected_illegal,
                         is_priv_illegal, expected_priv_illegal);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        instr = 32'd0;

        // Representative legal encodings from every constrained group.
        check_decode(32'h0020_81b3, 1'b0, 1'b0, "ADD");
        check_decode(32'h0220_81b3, 1'b0, 1'b0, "MUL");
        check_decode(32'h0030_9113, 1'b0, 1'b0, "SLLI");
        check_decode(32'h4030_d113, 1'b0, 1'b0, "SRAI");
        check_decode(32'h0000_8083, 1'b0, 1'b0, "LB");
        check_decode(32'h0000_a083, 1'b0, 1'b0, "LW");
        check_decode(32'h0020_a023, 1'b0, 1'b0, "SW");
        check_decode(32'h0020_8463, 1'b0, 1'b0, "BEQ");
        check_decode(32'h0000_80e7, 1'b0, 1'b0, "JALR");
        check_decode(32'h0000_000f, 1'b0, 1'b0, "FENCE");
        check_decode(32'h0000_100f, 1'b0, 1'b0, "FENCE.I");
        check_decode(32'h1000_a12f, 1'b0, 1'b0, "LR.W rs2=x0");
        check_decode(32'h0020_a1af, 1'b0, 1'b0, "AMOADD.W");
        check_decode(32'h3000_9173, 1'b0, 1'b0, "CSRRW");
        check_decode(32'h0000_0073, 1'b0, 1'b0, "ECALL");

        // Reserved encodings which the old opcode-only check accepted.
        check_decode(32'h0000_0000, 1'b1, 1'b0, "unknown opcode");
        check_decode(32'h0000_b083, 1'b1, 1'b0, "reserved LOAD funct3");
        check_decode(32'h0020_b023, 1'b1, 1'b0, "reserved STORE funct3");
        check_decode(32'h0020_a463, 1'b1, 1'b0, "reserved BRANCH funct3");
        check_decode(32'h0000_90e7, 1'b1, 1'b0, "reserved JALR funct3");
        check_decode(32'h4020_f1b3, 1'b1, 1'b0, "reserved OP funct7/funct3");
        check_decode(32'h2020_81b3, 1'b1, 1'b0, "reserved OP funct7");
        check_decode(32'h2030_9113, 1'b1, 1'b0, "reserved SLLI upper bits");
        check_decode(32'h2030_d113, 1'b1, 1'b0, "reserved right shift upper bits");
        check_decode(32'h0000_200f, 1'b1, 1'b0, "reserved MISC-MEM funct3");
        check_decode(32'h1000_912f, 1'b1, 1'b0, "AMO non-word funct3");
        check_decode(32'h1010_a12f, 1'b1, 1'b0, "LR.W rs2 nonzero");
        check_decode(32'h2800_a12f, 1'b1, 1'b0, "reserved AMO funct5");
        check_decode(32'h3000_c173, 1'b1, 1'b0, "reserved SYSTEM funct3");

        // Invalid privileged SYSTEM is kept separate from illegal CSR/opcode
        // encoding so the trap unit receives exactly one precise reason.
        check_decode(32'h0020_0073, 1'b0, 1'b1, "reserved privileged SYSTEM");
        check_decode(32'h0000_00f3, 1'b0, 1'b1, "ECALL with nonzero rd");
        check_decode(32'h3020_80f3, 1'b0, 1'b1, "MRET with nonzero rs1/rd");

        if (errors == 0)
            $display("CORE_INSTRUCTION_LEGALITY_TB: PASS");
        else
            $display("CORE_INSTRUCTION_LEGALITY_TB: FAIL (%0d checks failed)", errors);
        $finish;
    end
endmodule
