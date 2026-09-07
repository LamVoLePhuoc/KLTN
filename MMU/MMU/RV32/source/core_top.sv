`timescale 1ps / 1ps
//
// core_top: Phase-1 single-core RV32I integration.
//
// Wires the existing datapath blocks (decode.v, execute.v, write_back.v)
// together with a fixed PC unit (pc_unit.v) and the private L0/L1 cache
// subsystem (MMU.sv, in ../../MMU.sv / I_Cache.sv / D_Cache.sv) into one
// complete, stall-correct RV32I core.
//
// This supersedes the old rv32i.v / core_wrapper.v / soc.v chain, which
// wired the pipeline to a different, buggy cache path (Cache.v +
// memory_access.v, which has a multiply-driven `mem_ready` net) and never
// stalled the PC on a cache miss. Those files are left in place for
// reference but are not part of the Phase-1 deliverable. See
// README_PHASE1.md.
//
// Timing model: this is a single-cycle datapath (fetch/decode/execute/
// mem/wb all resolve combinationally from the instruction word), but an
// instruction may take multiple clock cycles to *retire* whenever the
// I-cache or D-cache is not ready (line fill / write-back in progress).
// While stalled, the core keeps re-presenting the same PC/address to the
// caches every cycle (cheap, and harmless for a cache controller that
// only latches a new request out of IDLE) until both are ready, at which
// point the register file and the PC commit exactly once.
//
module core_top #(
    // Phase-2: each core in multicore_top.sv is given a different
    // RESET_PC so it boots into its own program region instead of every
    // core racing to execute core 0's code at address 0.
    parameter [31:0] RESET_PC = 32'h0000_0000
) (
    input clk,
    input rst_n,

    // Backing memory interface for the private I-cache (256-bit line, AXI-like)
    output [31:0]  i_mem_req_addr,
    output         i_mem_req_read,
    output         i_mem_req_write,
    output [255:0] i_mem_req_wdata,
    input  [255:0] i_mem_rdata,
    input          i_mem_ready,

    // Backing memory interface for the private D-cache
    output [31:0]  d_mem_req_addr,
    output         d_mem_req_read,
    output         d_mem_req_write,
    output [255:0] d_mem_req_wdata,
    input  [255:0] d_mem_rdata,
    input          d_mem_ready,

    // Phase-2 coherence snoop-invalidate input (from the shared
    // interconnect; tie to 0/don't-care for single-core use).
    input          snoop_en,
    input  [31:0]  snoop_addr,

    // Debug/verification taps (used by the testbench)
    output [31:0]  dbg_pc,
    output [31:0]  dbg_instr,
    output         dbg_instr_retire,
    output         dbg_i_cpu_ready,
    output         dbg_d_cpu_ready,
    output         dbg_needs_mem,
    output         dbg_mem_read,
    output         dbg_mem_write
);

    // ---------------------------------------------------------------
    // Fetch
    // ---------------------------------------------------------------
    wire [31:0] pc, pc_plus_4;
    wire [31:0] i_cpu_addr = pc;
    wire [31:0] instr;          // = i_cpu_rdata, valid when i_cpu_ready
    wire        i_cpu_ready;

    // ---------------------------------------------------------------
    // Decode
    // ---------------------------------------------------------------
    wire [31:0] rs1_data, rs2_data, imm, wb_data;
    wire [3:0]  alu_op;
    wire        mem_read, mem_write, reg_write_en;
    wire [1:0]  wb_sel, pc_sel;
    wire        a_sel, b_sel, br_un;
    wire [9:0]  ls_sel, branch_signal;

    // ---------------------------------------------------------------
    // Execute
    // ---------------------------------------------------------------
    wire [31:0] alu_result, branch_taken;

    // ---------------------------------------------------------------
    // Retire / stall control
    // ---------------------------------------------------------------
    wire mem_read_q  = mem_read  & i_cpu_ready; // only issue once instr is known-valid
    wire mem_write_q = mem_write & i_cpu_ready;
    wire needs_mem   = mem_read_q | mem_write_q;

    wire d_cpu_ready;
    wire instr_done = i_cpu_ready & (needs_mem ? d_cpu_ready : 1'b1);

    assign dbg_pc           = pc;
    assign dbg_instr        = instr;
    assign dbg_instr_retire = instr_done;
    assign dbg_i_cpu_ready  = i_cpu_ready;
    assign dbg_d_cpu_ready  = d_cpu_ready;
    assign dbg_needs_mem    = needs_mem;
    assign dbg_mem_read     = mem_read_q;
    assign dbg_mem_write    = mem_write_q;

    // ---------------------------------------------------------------
    // Data memory address / byte-enable / load-select generation
    // (RV32I funct3 -> MMU's ld_sel / byte_en encodings)
    // ---------------------------------------------------------------
    wire [2:0] funct3 = instr[14:12];
    reg  [2:0] ld_sel;
    reg  [3:0] byte_en;

    always @(*) begin
        case (funct3)
            3'b000:  begin ld_sel = 3'h2; byte_en = 4'b0001; end // LB  / SB
            3'b001:  begin ld_sel = 3'h4; byte_en = 4'b0011; end // LH  / SH
            3'b010:  begin ld_sel = 3'h6; byte_en = 4'b1111; end // LW  / SW
            3'b100:  begin ld_sel = 3'h0; byte_en = 4'b0001; end // LBU
            3'b101:  begin ld_sel = 3'h1; byte_en = 4'b0011; end // LHU
            default: begin ld_sel = 3'h6; byte_en = 4'b1111; end
        endcase
    end

    wire [63:0] d_cpu_mem_ld_data;
    wire [31:0] data_mem = d_cpu_mem_ld_data[31:0];

    // ---------------------------------------------------------------
    // Module instances
    // ---------------------------------------------------------------
    pc_unit #(.RESET_PC(RESET_PC)) u_pc (
        .clk(clk), .rst_n(rst_n),
        .pc_en(instr_done),
        .pc_sel(pc_sel),
        .branch_taken(branch_taken),
        .alu_result(alu_result),
        .pc(pc), .pc_plus_4(pc_plus_4)
    );

    decode u_decode (
        .clk(clk), .rst_n(rst_n),
        .instr(instr),
        .wb_data(wb_data),
        .instr_valid(instr_done),
        .rs1_data(rs1_data), .rs2_data(rs2_data), .imm(imm),
        .alu_op(alu_op),
        .mem_read(mem_read), .mem_write(mem_write),
        .reg_write_en(reg_write_en),
        .wb_sel(wb_sel), .pc_sel(pc_sel),
        .a_sel(a_sel), .b_sel(b_sel),
        .ls_sel(ls_sel), .branch_signal(branch_signal), .br_un(br_un)
    );

    execute u_execute (
        .PC(pc), .Imm(imm), .DataA(rs1_data), .DataB(rs2_data),
        .alu_op(alu_op), .br_un(br_un),
        .a_sel(a_sel), .b_sel(b_sel),
        .branch_signal(branch_signal),
        .alu_result(alu_result), .branch_taken(branch_taken)
    );

    write_back u_wb (
        .alu_result(alu_result), .data_mem(data_mem), .pc_plus_4(pc_plus_4),
        .wb_sel(wb_sel), .wb_data_out(wb_data)
    );

    MMU u_mmu (
        .clk(clk), .rst_n(rst_n),
        // I-side
        .i_cpu_addr(i_cpu_addr),
        .i_cpu_rdata(instr),
        .i_cpu_ready(i_cpu_ready),
        // D-side (CPU load/store)
        .d_cpu_mem_st_en(mem_write_q),
        .d_cpu_mem_ld_en(mem_read_q),
        .d_cpu_mem_addr(alu_result[11:0]),
        .d_cpu_mem_byte_en(byte_en),
        .d_cpu_mem_ld_sel(ld_sel),
        .d_cpu_mem_st_data({32'b0, rs2_data}),
        .d_cpu_mem_ld_data(d_cpu_mem_ld_data),
        // D-side (FPU load/store) — unused in RV32I, tie off
        .d_fpu_mem_ld_sel(1'b0),
        .d_fpu_mem_wren(1'b0),
        .d_fpu_mem_addr(12'b0),
        .d_fpu_mem_din(64'b0),
        .d_fpu_mem_dout(),
        .d_cpu_ready(d_cpu_ready),
        // Backing memory
        .i_mem_req_addr(i_mem_req_addr), .i_mem_req_read(i_mem_req_read),
        .i_mem_req_write(i_mem_req_write), .i_mem_req_wdata(i_mem_req_wdata),
        .i_mem_rdata(i_mem_rdata), .i_mem_ready(i_mem_ready),
        .d_mem_req_addr(d_mem_req_addr), .d_mem_req_read(d_mem_req_read),
        .d_mem_req_write(d_mem_req_write), .d_mem_req_wdata(d_mem_req_wdata),
        .d_mem_rdata(d_mem_rdata), .d_mem_ready(d_mem_ready),
        .snoop_en(snoop_en), .snoop_addr(snoop_addr)
    );

endmodule
