`timescale 1ps/1ps

module execute(
    input  [31:0] PC,         // Program Counter
    input  [31:0] Imm,        // Immediate value
    input  [31:0] DataA,      // Register file data A
    input  [31:0] DataB,      // Register file data B
    input  [3:0]  alu_op,     // ALU operation
    input         br_un,      // Branch Unsigned flag (1-bit)
    input         a_sel,      // Select for source A (PC vs. DataA)
    input         b_sel,      // Select for source B (Imm vs. DataB)
    input  [9:0]  branch_signal, // Branch signal (combined control from Controller)
    output [31:0] alu_result,    // ALU result output
    output [31:0] branch_taken   // Computed branch target (if branch taken)
);

    // Selected source signals for ALU and branch comparison.
    wire [31:0] src_A, src_B;
    wire br_eq, br_lt, br_gt;

    // Branch target is computed in an always block
    reg [31:0] branch_taken_reg;

    // Select source A: either PC or DataA based on a_sel.
    assign src_A = a_sel ? PC : DataA;
    // Select source B: either Imm or DataB based on b_sel.
    //
    // Phase-1 fix: this used to be `b_sel ? Imm : DataB`, which is the
    // opposite of what decode.v's Controller actually intends (per its
    // own comments: b_sel=0 -> "select immediate", b_sel=1 -> "select
    // data from rs2"). With the old polarity, every immediate-using
    // instruction (ADDI, LOAD, STORE, JAL, JALR, Bxx) read rs2 instead
    // of the immediate, and R-type instructions added Imm (usually 0)
    // instead of rs2. In particular JAL's target collapsed to
    // PC + (whatever rs2 happened to hold, often 0) = PC, which is an
    // instant infinite self-loop — this is what produced the "core never
    // reaches the halt loop" simulation hang.
    assign src_B = b_sel ? DataB : Imm;

    // Instantiate the ALU using the selected sources.
    alu alu_inst (
        .in1(src_A),
        .in2(src_B),
        .alu_op(alu_op),
        .alu_result(alu_result)
    );

    // Instantiate the branch comparator.
    branchcomp branchcomp_inst (
        .DataA(DataA),
        .DataB(DataB),
        .br_un(br_un), // Now 1-bit
        .br_eq(br_eq),
        .br_lt(br_lt),
        .br_gt(br_gt)
    );
    
    // Compute branch target address based on branch_signal and comparison results.
    always @(branch_signal or br_eq or br_lt or br_gt) begin
        case(branch_signal)
            10'b1100011000: branch_taken_reg = br_eq ? PC + Imm : 32'h0;    // BEQ: if equal, branch taken.
            10'b1100011001: branch_taken_reg = br_eq ? 32'h0    : PC + Imm;   // BNE: if not equal, branch taken.
            10'b1100011100: branch_taken_reg = br_lt ? PC + Imm : 32'h0;    // BLT: if less-than, branch taken.
            10'b1100011101: branch_taken_reg = br_gt ? PC + Imm : 32'h0;    // BGE: if greater-than or equal, branch taken.
            10'b1100011110: branch_taken_reg = br_lt ? PC + Imm : 32'h0;    // BLTU: if less-than (unsigned), branch taken.
            10'b1100011111: branch_taken_reg = br_gt ? PC + Imm : 32'h0;    // BGEU: if greater-than or equal (unsigned), branch taken.
            default: branch_taken_reg = 32'h0;
        endcase
    end

    // Connect the computed branch target to the output.
    assign branch_taken = branch_taken_reg;

endmodule

// ALU module: performs arithmetic and logic operations.
module alu(
    input  [31:0] in1,      // First operand
    input  [31:0] in2,      // Second operand
    input  [3:0]  alu_op,   // ALU operation code
    output reg [31:0] alu_result  // ALU result output
);
    always @(*) begin
        case(alu_op)
            4'b0000: alu_result = in1 + in2;                   // ADD
            4'b0001: alu_result = in1 - in2;                   // SUB
            4'b0010: alu_result = in1 << in2;                  // SLL
            4'b0011: alu_result = ($signed(in1) < $signed(in2)) ? 1 : 0; // SLT (signed)
            4'b0100: alu_result = (in1 < in2) ? 1 : 0;         // SLTU (unsigned)
            4'b0101: alu_result = in1 ^ in2;                   // XOR
            4'b0110: alu_result = in1 >> in2;                  // SRL (logical shift right)
            4'b0111: alu_result = in1 >>> in2;                 // SRA (arithmetic shift right)
            4'b1000: alu_result = in1 | in2;                   // OR
            4'b1001: alu_result = in1 & in2;                   // AND
            // LUI: decode.v's imm_value for U-type is already
            // {instr[31:12], 12'b0} (pre-shifted into position), so this
            // must just pass it through. The old `in2 << 12` here
            // double-shifted it, corrupting every LUI result.
            4'b1010: alu_result = in2;                         // LUI: imm already pre-shifted by decode.v
            default: alu_result = 32'h0;
        endcase
    end
endmodule

// Branch Comparator module: compares two data values.
module branchcomp(
    input  [31:0] DataA,  // First data value
    input  [31:0] DataB,  // Second data value
    input         br_un,  // Branch Unsigned flag (1-bit)
    output reg    br_eq,  // Equality flag
    output reg    br_lt,  // Less-than flag
    output reg    br_gt   // Greater-than flag
);
    always @(*) begin
        // If branch is signed (br_un == 0), perform signed comparisons.
        if (br_un == 1'b0) begin
            if (DataA == DataB) begin
                br_eq = 1;
                br_lt = 0;
                br_gt = 0;
            end 
            else if ($signed(DataA) < $signed(DataB)) begin
                br_eq = 0;
                br_lt = 1;
                br_gt = 0;
            end 
            else begin
                br_eq = 0;
                br_lt = 0;
                br_gt = 1;
            end
        end
        // If branch is unsigned (br_un == 1), perform unsigned comparisons.
        else begin
            if (DataA == DataB) begin
                br_eq = 1;
                br_lt = 0;
                br_gt = 0;
            end 
            else if (DataA < DataB) begin
                br_eq = 0;
                br_lt = 1;
                br_gt = 0;
            end 
            else begin
                br_eq = 0;
                br_lt = 0;
                br_gt = 1;
            end
        end
    end
endmodule
