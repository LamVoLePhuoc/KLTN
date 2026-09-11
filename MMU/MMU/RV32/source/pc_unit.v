`timescale 1ps/1ps
//
// pc_unit: Program-counter register + next-PC selection.
//
// Phase-1 fix notes (vs. the old fetch.v / mux_pc):
//   - The old mux_pc hard-wired pc_sel==2'b11 (used by both JAL and JALR)
//     to 32'h0, which silently broke every jump. JAL/JALR now select the
//     ALU result (PC+imm for JAL, rs1+imm for JALR), which is exactly the
//     jump target already computed by `execute`.
//   - PC no longer free-runs every clock: it only advances when `pc_en`
//     is asserted by the core FSM (i.e. the current instruction has fully
//     retired). This lets the core stall correctly on I-cache / D-cache
//     misses instead of racing ahead of memory.
//
module pc_unit #(
    // Phase-2: per-core boot address. In multicore_top.sv each core is
    // given a distinct RESET_PC so all 4 cores don't all boot into core
    // 0's program at address 0. A real multicore chip would do this via
    // a hart-ID-dependent reset vector or a boot ROM; this is the
    // simulation-friendly equivalent for a first working system.
    parameter [31:0] RESET_PC = 32'h0000_0000
) (
    input         clk,
    input         rst_n,
    input         pc_en,          // advance PC (retire current instruction)
    input  [1:0]  pc_sel,         // 00: PC+4, 10: branch target, 11: jump target (ALU result)
    input  [31:0] branch_taken,   // branch target from execute (0 if not taken)
    input  [31:0] alu_result,     // JAL/JALR target from execute
    output [31:0] pc,             // current PC (address of instr in flight)
    output [31:0] pc_plus_4
);

    reg [31:0] pc_reg;
    reg [31:0] pc_next;

    assign pc          = pc_reg;
    assign pc_plus_4   = pc_reg + 32'd4;

    always @(*) begin
        case (pc_sel)
            2'b10:   pc_next = (branch_taken != 32'h0) ? branch_taken : pc_plus_4; // Bxx
            2'b11:   pc_next = alu_result;                                         // JAL / JALR
            default: pc_next = pc_plus_4;                                          // PC+4
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            pc_reg <= RESET_PC;
        end else if (pc_en) begin
            pc_reg <= pc_next;
        end
    end

endmodule
