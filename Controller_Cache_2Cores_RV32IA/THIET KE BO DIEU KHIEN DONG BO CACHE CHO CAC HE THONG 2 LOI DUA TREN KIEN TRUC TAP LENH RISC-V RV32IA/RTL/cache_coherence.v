`timescale 1ns/1ps
// from Lee Min Hunz with luv

module cache_coherence #(
    parameter ADDR_W = 32
,   parameter LINE_W = 128 // (4 words * 32 bits)
)(
    input clk
,   input rst_n

    // ==========================================
    // PORT CORE 0
    // ==========================================
    // --- I-Cache 0 Interface ---
,   input                   i_ic0_req_valid
,   output                  o_ic0_req_ready
,   input   [ADDR_W-1:0]    i_ic0_req_addr

,   input                   i_ic0_rdata_ready
,   output                  o_ic0_rdata_valid
,   output  [LINE_W-1:0]    o_ic0_rdata

    // --- D-Cache 0 Request/Response ---
,   input                   i_dc0_req_valid
,   output                  o_dc0_req_ready
,   input   [ADDR_W-1:0]    i_dc0_req_addr
,   input   [1:0]           i_dc0_req_cmd    
,   input   [LINE_W-1:0]    i_dc0_req_data
// ,   input                   i_dc0_req_wb  // (Tín hiệu này đã được tối ưu, không cần dùng ở module này nữa)

,   input                   i_dc0_resp_ready
,   output                  o_dc0_resp_valid
,   output  [LINE_W-1:0]    o_dc0_resp_data
    
    // --- D-Cache 0 Snoop Bus ---
,   input                   i_dc0_snp_req_ready
,   output                  o_dc0_snp_req_valid
,   output  [ADDR_W-1:0]    o_dc0_snp_req_addr
,   output  [1:0]           o_dc0_snp_req_cmd
,   output                  o_dc0_resp_is_shared 
// ,   output                  o_dc0_resp_is_dirty  

,   input                   i_dc0_snp_resp_valid
,   input                   i_dc0_snp_resp_hit
,   input   [LINE_W-1:0]    i_dc0_snp_resp_data

    // ==========================================
    // PORT CORE 1
    // ==========================================
    // --- I-Cache 1 Interface ---
,   input                   i_ic1_req_valid
,   output                  o_ic1_req_ready
,   input   [ADDR_W-1:0]    i_ic1_req_addr

,   input                   i_ic1_rdata_ready
,   output                  o_ic1_rdata_valid
,   output  [LINE_W-1:0]    o_ic1_rdata

    // --- D-Cache 1 Request/Response ---
,   input                   i_dc1_req_valid
,   output                  o_dc1_req_ready
,   input   [ADDR_W-1:0]    i_dc1_req_addr
,   input   [1:0]           i_dc1_req_cmd    
,   input   [LINE_W-1:0]    i_dc1_req_data
// ,   input                   i_dc1_req_wb  // (Đã tối ưu, bỏ qua)

,   input                   i_dc1_resp_ready
,   output                  o_dc1_resp_valid
,   output  [LINE_W-1:0]    o_dc1_resp_data
    
    // --- D-Cache 1 Snoop Bus ---
,   input                   i_dc1_snp_req_ready
,   output                  o_dc1_snp_req_valid
,   output  [ADDR_W-1:0]    o_dc1_snp_req_addr
,   output  [1:0]           o_dc1_snp_req_cmd
,   output                  o_dc1_resp_is_shared 
// ,   output                  o_dc1_resp_is_dirty  

,   input                   i_dc1_snp_resp_valid
,   input                   i_dc1_snp_resp_hit
,   input   [LINE_W-1:0]    i_dc1_snp_resp_data

    // ==========================================
    // PORT L2 CACHE (Shared)
    // ==========================================
,   input                   i_l2_req_ready
,   input                   L2_pipeline_stall
,   output                  o_l2_req_valid
,   output  [ADDR_W-1:0]    o_l2_req_addr
,   output                  o_l2_req_rw      // 0: Read, 1: Write
,   output  [LINE_W-1:0]    o_l2_req_wdata

,   input                   i_l2_resp_valid
,   input   [LINE_W-1:0]    i_l2_resp_rdata
// ,   output                  o_l2_resp_ready
);

    // ================================================================
    // WIRES KHAI BÁO NỐI GHÉP NỘI BỘ (INTERNAL SIGNALS)
    // ================================================================
    
    // --- Wires giữa i_arbiter và main_l2_arbiter ---
    wire                w_l2_i_req_valid;
    wire                w_l2_i_req_ready;
    wire [ADDR_W-1:0]   w_l2_i_req_addr;
    wire                w_l2_i_rdata_ready;
    wire                w_l2_i_rdata_valid;
    wire [LINE_W-1:0]   w_l2_i_rdata;

    // --- Wires giữa d_coherence và main_l2_arbiter ---
    wire                w_l2_d_req_valid;
    wire                w_l2_d_req_ready;
    wire [ADDR_W-1:0]   w_l2_d_req_addr;
    wire                w_l2_d_req_rw;
    wire [LINE_W-1:0]   w_l2_d_req_wdata;
    wire                w_l2_d_resp_ready;
    wire                w_l2_d_resp_valid;
    wire [LINE_W-1:0]   w_l2_d_resp_rdata;

    // ================================================================
    // MODULE INSTANTIATIONS
    // ================================================================

    // 1. Khởi tạo Instruction Arbiter
    i_arbiter #(
        .ADDR_W(ADDR_W)
    ,   .LINE_W(LINE_W)
    ) u_i_arbiter (
        .clk                (clk)
    ,   .rst_n              (rst_n)
        
        // I-Cache 0
    ,   .i_ic0_req_valid    (i_ic0_req_valid)
    ,   .o_ic0_req_ready    (o_ic0_req_ready)
    ,   .i_ic0_req_addr     (i_ic0_req_addr)
    ,   .i_ic0_rdata_ready  (i_ic0_rdata_ready)
    ,   .o_ic0_rdata_valid  (o_ic0_rdata_valid)
    ,   .o_ic0_rdata        (o_ic0_rdata)

        // I-Cache 1
    ,   .i_ic1_req_valid    (i_ic1_req_valid)
    ,   .o_ic1_req_ready    (o_ic1_req_ready)
    ,   .i_ic1_req_addr     (i_ic1_req_addr)
    ,   .i_ic1_rdata_ready  (i_ic1_rdata_ready)
    ,   .o_ic1_rdata_valid  (o_ic1_rdata_valid)
    ,   .o_ic1_rdata        (o_ic1_rdata)

        // Downstream to Main Arbiter
    ,   .o_l2_i_req_valid   (w_l2_i_req_valid)
    ,   .i_l2_i_req_ready   (w_l2_i_req_ready)
    ,   .o_l2_i_req_addr    (w_l2_i_req_addr)
    ,   .o_l2_i_rdata_ready (w_l2_i_rdata_ready)
    ,   .i_l2_i_rdata_valid (w_l2_i_rdata_valid)
    ,   .i_l2_i_rdata       (w_l2_i_rdata)
    );

    // 2. Khởi tạo Data Coherence
    d_coherence #(
        .ADDR_W(ADDR_W)
    ,   .LINE_W(LINE_W)
    ) u_d_coherence (
        .clk                    (clk)
    ,   .rst_n                  (rst_n)

        // D-Cache 0 
    ,   .i_dc0_req_valid        (i_dc0_req_valid)
    ,   .o_dc0_req_ready        (o_dc0_req_ready)
    ,   .i_dc0_req_addr         (i_dc0_req_addr)
    ,   .i_dc0_req_cmd          (i_dc0_req_cmd)
    ,   .i_dc0_req_data         (i_dc0_req_data)
    ,   .o_dc0_resp_valid       (o_dc0_resp_valid)
    ,   .i_dc0_resp_ready       (i_dc0_resp_ready)
    ,   .o_dc0_resp_data        (o_dc0_resp_data)

    ,   .o_dc0_snp_req_valid    (o_dc0_snp_req_valid)
    ,   .i_dc0_snp_req_ready    (i_dc0_snp_req_ready)
    ,   .o_dc0_snp_req_addr     (o_dc0_snp_req_addr)
    ,   .o_dc0_snp_req_cmd      (o_dc0_snp_req_cmd)
    ,   .o_dc0_resp_is_shared   (o_dc0_resp_is_shared)
    // ,   .o_dc0_resp_is_dirty    (o_dc0_resp_is_dirty)
    ,   .i_dc0_snp_resp_valid   (i_dc0_snp_resp_valid)
    ,   .i_dc0_snp_resp_hit     (i_dc0_snp_resp_hit)
    ,   .i_dc0_snp_resp_data    (i_dc0_snp_resp_data)

        // D-Cache 1 
    ,   .i_dc1_req_valid        (i_dc1_req_valid)
    ,   .o_dc1_req_ready        (o_dc1_req_ready)
    ,   .i_dc1_req_addr         (i_dc1_req_addr)
    ,   .i_dc1_req_cmd          (i_dc1_req_cmd)
    ,   .i_dc1_req_data         (i_dc1_req_data)
    ,   .o_dc1_resp_valid       (o_dc1_resp_valid)
    ,   .i_dc1_resp_ready       (i_dc1_resp_ready)
    ,   .o_dc1_resp_data        (o_dc1_resp_data)

    ,   .o_dc1_snp_req_valid    (o_dc1_snp_req_valid)
    ,   .i_dc1_snp_req_ready    (i_dc1_snp_req_ready)
    ,   .o_dc1_snp_req_addr     (o_dc1_snp_req_addr)
    ,   .o_dc1_snp_req_cmd      (o_dc1_snp_req_cmd)
    ,   .o_dc1_resp_is_shared   (o_dc1_resp_is_shared)
    // ,   .o_dc1_resp_is_dirty    (o_dc1_resp_is_dirty)
    ,   .i_dc1_snp_resp_valid   (i_dc1_snp_resp_valid)
    ,   .i_dc1_snp_resp_hit     (i_dc1_snp_resp_hit)
    ,   .i_dc1_snp_resp_data    (i_dc1_snp_resp_data)

        // Downstream to Main Arbiter
    ,   .o_l2_d_req_valid       (w_l2_d_req_valid)
    ,   .i_l2_d_req_ready       (w_l2_d_req_ready)
    ,   .o_l2_d_req_addr        (w_l2_d_req_addr)
    ,   .o_l2_d_req_rw          (w_l2_d_req_rw)
    ,   .o_l2_d_req_wdata       (w_l2_d_req_wdata)
    ,   .i_l2_d_resp_valid      (w_l2_d_resp_valid)
    ,   .o_l2_d_resp_ready      (w_l2_d_resp_ready)
    ,   .i_l2_d_resp_rdata      (w_l2_d_resp_rdata)
    );

    // 3. Khởi tạo Main L2 Arbiter
    main_l2_arbiter #(
        .ADDR_W(ADDR_W)
    ,   .LINE_W(LINE_W)
    ) u_main_arbiter (
        .clk                    (clk)
    ,   .rst_n                  (rst_n)

        // Luồng Instruction từ i_arbiter
    ,   .i_l2_i_req_valid       (w_l2_i_req_valid)
    ,   .o_l2_i_req_ready       (w_l2_i_req_ready)
    ,   .i_l2_i_req_addr        (w_l2_i_req_addr)
    ,   .o_l2_i_rdata_valid     (w_l2_i_rdata_valid)   
    ,   .i_l2_i_rdata_ready     (w_l2_i_rdata_ready)
    ,   .o_l2_i_rdata           (w_l2_i_rdata)

        // Luồng Data từ d_coherence
    ,   .i_l2_d_req_valid       (w_l2_d_req_valid)
    ,   .o_l2_d_req_ready       (w_l2_d_req_ready)
    ,   .i_l2_d_req_addr        (w_l2_d_req_addr)
    ,   .i_l2_d_req_rw          (w_l2_d_req_rw)
    ,   .i_l2_d_req_wdata       (w_l2_d_req_wdata)
    ,   .o_l2_d_resp_valid      (w_l2_d_resp_valid)
    ,   .i_l2_d_resp_ready      (w_l2_d_resp_ready)
    ,   .o_l2_d_resp_rdata      (w_l2_d_resp_rdata)

        // Giao tiếp trực tiếp với L2 Cache
    ,   .L2_pipeline_stall      (L2_pipeline_stall)
    ,   .o_l2_req_valid         (o_l2_req_valid)
    ,   .i_l2_req_ready         (i_l2_req_ready)
    ,   .o_l2_req_addr          (o_l2_req_addr)
    ,   .o_l2_req_rw            (o_l2_req_rw)
    ,   .o_l2_req_wdata         (o_l2_req_wdata)
    ,   .i_l2_resp_valid        (i_l2_resp_valid)
    // ,   .o_l2_resp_ready        (o_l2_resp_ready)
    ,   .i_l2_resp_rdata        (i_l2_resp_rdata)
    );

endmodule