`timescale 1ns / 1ps
`include "define.vh"
// from Lee Min Hunz with luv

module single_core #(
    parameter ADDR_W        = `ADDR_W                   // Address width
,   parameter DATA_W        = `DATA_W                   // Data width

    // Memory Map Configuration
,   parameter CODE_START    = `CODE_A_START             // Instruction base address
,   parameter DATA_START    = `DATA_START               // Data base address

    // Cache Configuration
,   parameter NUM_WAYS      = `NUM_WAYS                 // Cache associativity
,   parameter NUM_SETS      = `NUM_SETS                 // L1 cache sets
,   parameter INDEX_W       = $clog2(NUM_SETS)          // Index width
,   parameter NUM_SETS_L2   = `NUM_SETS_L2              // L2 cache sets
,   parameter WORD_OFF_W    = `WORD_OFF_W               // Word offset (16 words/line)
,   parameter BYTE_OFF_W    = `BYTE_OFF_W               // Byte offset (4 bytes/word)
,   parameter LINE_W        = (1 << WORD_OFF_W) * 32    // Cache line width
,   parameter STRB_W        = DATA_W/8                  // Write strobe width
)(
    input clk
,   input rst_n
// ,   input test_stall // Bổ sung cổng này để truyền vào RV32IA

    // ==========================================
    // GIAO TIẾP I-CACHE VỚI COHERENCE INTERCONNECT
    // ==========================================
,   output                  o_ic_req_valid
,   input                   i_ic_req_ready
,   output  [ADDR_W-1:0]    o_ic_req_addr
    
,   input                   i_ic_rdata_valid
,   output                  o_ic_rdata_ready
,   input   [LINE_W-1:0]    i_ic_rdata

    // ==========================================
    // GIAO TIẾP D-CACHE VỚI COHERENCE INTERCONNECT
    // ==========================================
    // --- Request/Response Bus ---
,   output                  o_dc_req_valid
,   input                   i_dc_req_ready
,   output  [ADDR_W-1:0]    o_dc_req_addr
,   output  [1:0]           o_dc_req_cmd
,   output  [LINE_W-1:0]    o_dc_req_data
,   output                  o_dc_req_wb
    
,   input                   i_dc_resp_valid
,   output                  o_dc_resp_ready
,   input   [LINE_W-1:0]    i_dc_resp_data

    // --- Snoop Bus ---
,   input                   i_snp_req_valid
,   output                  o_snp_req_ready
,   input   [ADDR_W-1:0]    i_snp_req_addr
,   input   [1:0]           i_snp_req_cmd
,   input                   i_resp_is_shared
// ,   input                   i_resp_is_dirty
    
,   output                  o_snp_resp_valid
,   output                  o_snp_resp_hit
,   output  [LINE_W-1:0]    o_snp_resp_data

,   input   [4:0]           i_debug_reg_addr
,   input                   i_debug_ren
,   output  [DATA_W-1:0]    o_debug_reg_data
);

    // ================================================================
    // INTERNAL WIRES (Kết nối CPU với L1 Caches)
    // ================================================================
    wire [DATA_W-1:0]   data_rdata, data_wdata;
    wire [ADDR_W-1:0]   data_addr;
    wire [1:0]          data_size;
    wire                data_req, data_wr, dcache_stall;
    wire                cpu_dcache_flush;
    wire                cpu_lr, cpu_sc, cpu_amo;
    wire [2:0]          cpu_amo_op;

    wire [DATA_W-1:0]   imem_instr;
    wire [ADDR_W-1:0]   icache_addr;
    wire                icache_req;
    // wire                icache_flush;
    wire                icache_stall;
    wire                fetch_stall;
    // wire                w_snoop_req_invalidate; // Dây nội bộ (không ra ngoài core)

    // ================================================================
    // CORE RV32IA
    // ================================================================
    RV32IA #( 
        .WIDTH_ADDR (ADDR_W) 
    ,   .WIDTH_DATA (DATA_W)
    ,   .START_PC   (CODE_START)
    ) u_RV32IA (
        .clk            (clk)
    ,   .rst_n          (rst_n)
    // ,   .test_stall     (test_stall)

        // D-Cache
    ,   .data_rdata     (data_rdata)
    ,   .data_req       (data_req)
    ,   .data_wr        (data_wr)
    ,   .data_size      (data_size)
    ,   .data_addr      (data_addr)
    ,   .data_wdata     (data_wdata)
    ,   .dcache_stall   (dcache_stall)
    ,   .o_dcache_flush (cpu_dcache_flush)

        // Atomics
    ,   .cpu_lr         (cpu_lr)
    ,   .cpu_sc         (cpu_sc)
    ,   .cpu_amo        (cpu_amo)
    ,   .cpu_amo_op     (cpu_amo_op)

        // I-Cache
    ,   .imem_instr     (imem_instr)
    ,   .icache_req     (icache_req)
    ,   .fetch_stall    (fetch_stall)
    // ,   .icache_flush   (icache_flush)
    ,   .icache_addr    (icache_addr)
    ,   .icache_stall   (icache_stall)

    ,   .i_debug_reg_addr (i_debug_reg_addr)
    ,   .i_debug_ren      (i_debug_ren)
    ,   .o_debug_reg_data (o_debug_reg_data)
    );

    // ================================================================
    // INSTRUCTION CACHE L1
    // ================================================================
    icache #( 
        .ADDR_W     (ADDR_W)
    ,   .DATA_W     (DATA_W)
    ,   .NUM_WAYS   (NUM_WAYS)
    ,   .NUM_SETS   (NUM_SETS)
    ,   .WORD_OFF_W (WORD_OFF_W)
    ,   .BYTE_OFF_W (BYTE_OFF_W)
    ) u_icache_L1 (
        .clk                (clk)
    ,   .rst_n              (rst_n)

        // Core Interface
    ,   .cpu_req            (icache_req)
    ,   .cpu_addr           (icache_addr)
    ,   .fetch_stall        (fetch_stall)
    // ,   .icache_flush       (icache_flush)
    ,   .dcache_stall       (dcache_stall)
    ,   .pipeline_stall     (icache_stall)
    ,   .data_rdata         (imem_instr)
        
        // Coherence Interconnect Interface (Đưa ra cổng của Core)
    ,   .i_l2_req_ready     (i_ic_req_ready)
    ,   .o_l2_req_valid     (o_ic_req_valid)
    ,   .o_l2_req_addr      (o_ic_req_addr)
    ,   .i_l2_rdata_valid   (i_ic_rdata_valid)
    ,   .i_l2_rdata         (i_ic_rdata)
    ,   .o_l2_rdata_ready   (o_ic_rdata_ready)
    );

    // ================================================================
    // DATA CACHE L1
    // ================================================================
    d_cache #( 
        .ADDR_W     (ADDR_W)
    ,   .DATA_W     (DATA_W)
    ,   .DATA_START (DATA_START)
    ,   .NUM_WAYS   (NUM_WAYS)
    ,   .NUM_SETS   (NUM_SETS)
    ,   .WORD_OFF_W (WORD_OFF_W)
    ,   .BYTE_OFF_W (BYTE_OFF_W)
    ) u_dcache_L1 (
        .clk                    (clk)
    ,   .rst_n                  (rst_n)

        // Core Interface
    ,   .cpu_req                (data_req | cpu_lr | cpu_sc | cpu_amo)
    ,   .cpu_we                 (data_wr)
    ,   .cpu_addr               (data_addr)
    ,   .cpu_din                (data_wdata)
    ,   .cpu_size               (data_size)
    ,   .data_rdata             (data_rdata)
    ,   .cpu_flush              (cpu_dcache_flush)
        
        // Atomics Interface
    ,   .cpu_lr                 (cpu_lr)
    ,   .cpu_sc                 (cpu_sc)
    ,   .cpu_amo                (cpu_amo)
    ,   .cpu_amo_op             (cpu_amo_op)
    ,   .o_sc_success           () // Bỏ trống nếu core không dùng cờ này trực tiếp
    ,   .pipeline_stall         (dcache_stall)
        
        // ========================================================
        // Coherence Interconnect Interface (Đưa ra cổng của Core)
        // ========================================================
        // --- REQUEST CHANNEL ---
    ,   .i_req_ready            (i_dc_req_ready)
    ,   .o_req_valid            (o_dc_req_valid)
    ,   .o_req_addr             (o_dc_req_addr)
    ,   .o_req_cmd              (o_dc_req_cmd)
    ,   .o_req_data             (o_dc_req_data)
    ,   .o_req_wb               (o_dc_req_wb)

        // --- RESPONSE CHANNEL ---
    ,   .i_resp_valid           (i_dc_resp_valid)
    ,   .i_resp_data            (i_dc_resp_data)
    ,   .o_resp_ready           (o_dc_resp_ready)

        // --- SNOOP REQUEST CHANNEL (Từ Core kia bắn sang) ---
    ,   .i_snp_req_valid        (i_snp_req_valid)
    ,   .i_snp_req_addr         (i_snp_req_addr)
    ,   .i_snp_req_cmd          (i_snp_req_cmd)
    ,   .i_resp_is_shared       (i_resp_is_shared)
    // ,   .i_resp_is_dirty        (i_resp_is_dirty)
    ,   .o_snp_req_ready        (o_snp_req_ready)

        // --- DCACHE RESPONSE SNOOP (Trả lời cho Core kia) ---
    ,   .o_snp_resp_valid       (o_snp_resp_valid)
    ,   .o_snp_resp_hit         (o_snp_resp_hit)
    ,   .o_snp_resp_data        (o_snp_resp_data)
        // .snoop_req_invalidate   (w_snoop_req_invalidate) // Tín hiệu nội bộ dcache, không cần nối ra ngoài
    );

endmodule