`timescale 1ns / 1ps

module RV32IMFA_DualCore_Wrapper(
    input  wire        clk,
    input  wire        rst,

    // ============================================================
    // Instruction memory interface for Core 0
    // ============================================================
    output wire [31:0] PC0F,
    input  wire [31:0] Instr0F,

    // ============================================================
    // Instruction memory interface for Core 1
    // ============================================================
    output wire [31:0] PC1F,
    input  wire [31:0] Instr1F,

    // ============================================================
    // Shared data memory interface
    // ============================================================
    output wire [31:0] Shared_Mem_Addr,
    output wire [31:0] Shared_Mem_WriteData,
    output wire        Shared_Mem_WriteEn,
    output wire        Shared_Mem_ReadEn,
    output wire [2:0]  Shared_MemOp,
    input  wire [31:0] Shared_Mem_ReadData,

    // ============================================================
    // Debug outputs
    // ============================================================
    output wire [31:0] Core0_ResultW,
    output wire [31:0] Core1_ResultW,

    output wire [31:0] Core0_ALU_ResultE_Debug,
    output wire [31:0] Core1_ALU_ResultE_Debug,

    output wire        Grant0_Debug,
    output wire        Grant1_Debug,
    output wire        Turn_Debug
);

    // ============================================================
    // Core 0 data memory bus
    // ============================================================
    wire [31:0] c0_mem_addr;
    wire [31:0] c0_mem_wdata;
    wire        c0_mem_we;
    wire        c0_mem_re;
    wire [2:0]  c0_memop;
    wire [31:0] c0_mem_rdata;
    wire        c0_stall;

    // ============================================================
    // Core 1 data memory bus
    // ============================================================
    wire [31:0] c1_mem_addr;
    wire [31:0] c1_mem_wdata;
    wire        c1_mem_we;
    wire        c1_mem_re;
    wire [2:0]  c1_memop;
    wire [31:0] c1_mem_rdata;
    wire        c1_stall;

    // ============================================================
    // Snoop / write commit signals
    // ============================================================
    wire [31:0] c0_write_addr_commit;
    wire        c0_write_commit;

    wire [31:0] c1_write_addr_commit;
    wire        c1_write_commit;

    // ============================================================
    // Core 0
    //
    // Synthesis note:
    // Không dùng #(.RESET_ADDR(...)) ở đây để tránh lỗi khi Vivado
    // synth nhầm RV32IMFA bằng stub không có parameter RESET_ADDR.
    // ============================================================
    RV32IMFA core0 (
        .clk                (clk),
        .rst                (rst),

        .Stall_Core_External(c0_stall),

        // Core 0 snoop write thật từ Core 1
        .Snoop_Addr         (c1_write_addr_commit),
        .Snoop_WE           (c1_write_commit),

        // Instruction side
        .PCF                (PC0F),
        .InstrF             (Instr0F),

        // Data memory side
        .Mem_AddrM          (c0_mem_addr),
        .Mem_WriteDataM     (c0_mem_wdata),
        .Mem_WriteEnM       (c0_mem_we),
        .Mem_ReadEnM        (c0_mem_re),
        .MemOpM             (c0_memop),
        .Mem_ReadDataM      (c0_mem_rdata),

        // Debug
        .ResultW            (Core0_ResultW),
        .ALU_ResultE_Debug  (Core0_ALU_ResultE_Debug)
    );

    // ============================================================
    // Core 1
    //
    // Synthesis note:
    // Không dùng #(.RESET_ADDR(...)) ở đây để tránh lỗi RESET_ADDR.
    // ============================================================
    RV32IMFA core1 (
        .clk                (clk),
        .rst                (rst),

        .Stall_Core_External(c1_stall),

        // Core 1 snoop write thật từ Core 0
        .Snoop_Addr         (c0_write_addr_commit),
        .Snoop_WE           (c0_write_commit),

        // Instruction side
        .PCF                (PC1F),
        .InstrF             (Instr1F),

        // Data memory side
        .Mem_AddrM          (c1_mem_addr),
        .Mem_WriteDataM     (c1_mem_wdata),
        .Mem_WriteEnM       (c1_mem_we),
        .Mem_ReadEnM        (c1_mem_re),
        .MemOpM             (c1_memop),
        .Mem_ReadDataM      (c1_mem_rdata),

        // Debug
        .ResultW            (Core1_ResultW),
        .ALU_ResultE_Debug  (Core1_ALU_ResultE_Debug)
    );

    // ============================================================
    // Round-robin arbiter for shared data memory
    // ============================================================
    round_robin_arbiter_2core arbiter (
        .clk                 (clk),
        .rst                 (rst),

        // Core 0 data bus
        .c0_addr             (c0_mem_addr),
        .c0_wdata            (c0_mem_wdata),
        .c0_we               (c0_mem_we),
        .c0_re               (c0_mem_re),
        .c0_memop            (c0_memop),
        .c0_rdata            (c0_mem_rdata),
        .c0_stall            (c0_stall),

        // Core 1 data bus
        .c1_addr             (c1_mem_addr),
        .c1_wdata            (c1_mem_wdata),
        .c1_we               (c1_mem_we),
        .c1_re               (c1_mem_re),
        .c1_memop            (c1_memop),
        .c1_rdata            (c1_mem_rdata),
        .c1_stall            (c1_stall),

        // Shared RAM side
        .mem_addr            (Shared_Mem_Addr),
        .mem_wdata           (Shared_Mem_WriteData),
        .mem_we              (Shared_Mem_WriteEn),
        .mem_re              (Shared_Mem_ReadEn),
        .memop               (Shared_MemOp),
        .mem_rdata           (Shared_Mem_ReadData),

        // Snoop commit
        .c0_write_addr_commit(c0_write_addr_commit),
        .c0_write_commit     (c0_write_commit),
        .c1_write_addr_commit(c1_write_addr_commit),
        .c1_write_commit     (c1_write_commit),

        // Debug
        .grant0_debug        (Grant0_Debug),
        .grant1_debug        (Grant1_Debug),
        .turn_debug          (Turn_Debug)
    );

endmodule