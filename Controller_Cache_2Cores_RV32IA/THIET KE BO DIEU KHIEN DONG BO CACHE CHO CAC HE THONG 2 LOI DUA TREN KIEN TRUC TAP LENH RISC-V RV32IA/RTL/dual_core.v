`timescale 1ns/1ps
`include "define.vh"
// from Lee Min Hunz with luv

module dual_core #(
    // Core Configuration
    parameter MEM_BASE      = `MEM_BASE     // Memory base address

    // Core A Instruction Memory
,   parameter CODE_A_START  = `CODE_A_START     // Core A instruction base

    // Core B Instruction Memory
,   parameter CODE_B_START  = `CODE_B_START     // Core B instruction base

    // Shared Data Memory
,   parameter DATA_START    = `DATA_START     // Shared data base

    // Cache Configuration
,   parameter NUM_WAYS      = `NUM_WAYS                 // Cache associativity
,   parameter NUM_SETS      = `NUM_SETS                 // L1 cache sets
,   parameter NUM_SETS_L2   = `NUM_SETS_L2              // L2 cache sets
,   parameter WORD_OFF_W    = `WORD_OFF_W               // Word offset (16 words/line)
,   parameter BYTE_OFF_W    = `BYTE_OFF_W               // Byte offset (4 bytes/word)
,   parameter DATA_W        = `DATA_W                   // Data width
,   parameter STRB_W        = DATA_W/8                  // Write strobe width
,   parameter LINE_W        = (1 << WORD_OFF_W) * 32    // Line width
)(
    input ACLK
,   input ARESETn

    // ==========================================
    // AXI 4 full MASTER INTERFACE (Giao tiep voi Memory)
    // ==========================================
    // AW Channel
,   input                       m00_axi_awready
,   output  [31:0]              m00_axi_awaddr
,   output  [7:0]               m00_axi_awlen
,   output  [2:0]               m00_axi_awsize
,   output  [1:0]               m00_axi_awburst
,   output                      m00_axi_awvalid

    // W channel
,   input                       m00_axi_wready
,   output  [DATA_W-1:0]        m00_axi_wdata
,   output  [STRB_W-1:0]        m00_axi_wstrb
,   output                      m00_axi_wlast
,   output                      m00_axi_wvalid
      
    // B channel
,   input   [1:0]               m00_axi_bresp
,   input                       m00_axi_bvalid
,   output                      m00_axi_bready

    // AR channel
,   input                       m00_axi_arready
,   output  [31:0]              m00_axi_araddr
,   output  [7:0]               m00_axi_arlen
,   output  [2:0]               m00_axi_arsize
,   output  [1:0]               m00_axi_arburst
,   output                      m00_axi_arvalid

    // R channel
,   input   [DATA_W-1:0]        m00_axi_rdata
,   input   [1:0]               m00_axi_rresp
,   input                       m00_axi_rlast
,   input                       m00_axi_rvalid
,   output                      m00_axi_rready
);

    // --- CORE 0 WIRES ---
    wire                c0_ic_req_valid;
    wire                c0_ic_req_ready;
    wire [31:0]         c0_ic_req_addr;
    wire                c0_ic_rdata_valid;
    wire                c0_ic_rdata_ready;
    wire [LINE_W-1:0]   c0_ic_rdata;

    wire                c0_dc_req_valid;
    wire                c0_dc_req_ready;
    wire                c0_dc_req_wb;
    wire [31:0]         c0_dc_req_addr;
    wire [1:0]          c0_dc_req_cmd;
    wire [LINE_W-1:0]   c0_dc_req_data;
    wire                c0_dc_resp_valid;
    wire                c0_dc_resp_ready;
    wire [LINE_W-1:0]   c0_dc_resp_data;

    wire                c0_snp_req_valid;
    wire                c0_snp_req_ready;
    wire [31:0]         c0_snp_req_addr;
    wire [1:0]          c0_snp_req_cmd;
    wire                c0_resp_is_shared;
    // wire                c0_resp_is_dirty;
    wire                c0_snp_resp_valid;
    wire                c0_snp_resp_hit;
    wire [LINE_W-1:0]   c0_snp_resp_data;

    // --- CORE 1 WIRES ---
    wire                c1_ic_req_valid;
    wire                c1_ic_req_ready;
    wire [31:0]         c1_ic_req_addr;
    wire                c1_ic_rdata_valid;
    wire                c1_ic_rdata_ready;
    wire [LINE_W-1:0]   c1_ic_rdata;

    wire                c1_dc_req_valid;
    wire                c1_dc_req_ready;
    wire                c1_dc_req_wb;
    wire [31:0]         c1_dc_req_addr;
    wire [1:0]          c1_dc_req_cmd;
    wire [LINE_W-1:0]   c1_dc_req_data;
    wire                c1_dc_resp_valid;
    wire                c1_dc_resp_ready;
    wire [LINE_W-1:0]   c1_dc_resp_data;

    wire                c1_snp_req_valid;
    wire                c1_snp_req_ready;
    wire [31:0]         c1_snp_req_addr;
    wire [1:0]          c1_snp_req_cmd;
    wire                c1_resp_is_shared;

    wire                c1_snp_resp_valid;
    wire                c1_snp_resp_hit;
    wire [LINE_W-1:0]   c1_snp_resp_data;

    // --- L2 CACHE WIRES (Từ Coherence xuống L2) ---
    wire                l2_req_valid;
    wire                l2_req_ready;
    wire                l2_req_rw;
    wire [31:0]         l2_req_addr;
    wire [LINE_W-1:0]   l2_req_wdata;
    wire                l2_resp_valid;
    
    wire [LINE_W-1:0]   l2_resp_rdata;
    wire                L2_pipeline_stall; // Dùng để stall cả 2 core khi L2 cache đang xử lý request

    // ================================================================
    // CORE 0 (Khởi tạo ở vị trí CODE_A_START)
    // ================================================================
    single_core #(
        .ADDR_W         (32)
    ,   .DATA_W         (DATA_W)
    ,   .CODE_START     (CODE_A_START)
    ,   .DATA_START     (DATA_START)
    ,   .NUM_WAYS       (NUM_WAYS)
    ,   .NUM_SETS       (NUM_SETS)
    ,   .WORD_OFF_W     (WORD_OFF_W)
    ,   .BYTE_OFF_W     (BYTE_OFF_W)
    ) core_0 (
        .clk                    (ACLK)
    ,   .rst_n                  (ARESETn)

        // I-Cache
    ,   .i_ic_rdata_valid       (c0_ic_rdata_valid)
    ,   .i_ic_rdata             (c0_ic_rdata)
    ,   .i_ic_req_ready         (c0_ic_req_ready)

    ,   .o_ic_rdata_ready       (c0_ic_rdata_ready)
    ,   .o_ic_req_valid         (c0_ic_req_valid)
    ,   .o_ic_req_addr          (c0_ic_req_addr)

        // D-Cache Request
    ,   .i_dc_req_ready         (c0_dc_req_ready)

    ,   .o_dc_req_valid         (c0_dc_req_valid)
    ,   .o_dc_req_addr          (c0_dc_req_addr)
    ,   .o_dc_req_data          (c0_dc_req_data)
    ,   .o_dc_req_cmd           (c0_dc_req_cmd)
    ,   .o_dc_req_wb            (c0_dc_req_wb)          // hien tai chua dung
    
        // D-Cache Response
    ,   .i_dc_resp_valid        (c0_dc_resp_valid)
    ,   .i_dc_resp_data         (c0_dc_resp_data)

    ,   .o_dc_resp_ready        (c0_dc_resp_ready)

        // Snoop Request (từ Core 1 bắn sang)
    ,   .i_snp_req_valid        (c0_snp_req_valid)
    ,   .i_snp_req_addr         (c0_snp_req_addr)
    ,   .i_snp_req_cmd          (c0_snp_req_cmd)
    ,   .i_resp_is_shared       (c0_resp_is_shared)

    ,   .o_snp_req_ready        (c0_snp_req_ready)
    
        // Snoop Response (tra loi Core 1)
    ,   .o_snp_resp_valid       (c0_snp_resp_valid)
    ,   .o_snp_resp_hit         (c0_snp_resp_hit)
    ,   .o_snp_resp_data        (c0_snp_resp_data)
    );

    // ================================================================
    // CORE 1 (Khởi tạo ở vị trí CODE_B_START)
    // ================================================================
    single_core #(
        .ADDR_W         (32)
    ,   .DATA_W         (DATA_W)
    ,   .CODE_START     (CODE_B_START)
    ,   .DATA_START     (DATA_START)
    ,   .NUM_WAYS       (NUM_WAYS)
    ,   .NUM_SETS       (NUM_SETS)
    ,   .WORD_OFF_W     (WORD_OFF_W)
    ,   .BYTE_OFF_W     (BYTE_OFF_W)
    ) core_1 (
        .clk                    (ACLK)
    ,   .rst_n                  (ARESETn)

        // I-Cache
    ,   .i_ic_req_ready         (c1_ic_req_ready)
    ,   .i_ic_rdata_valid       (c1_ic_rdata_valid)
    ,   .i_ic_rdata             (c1_ic_rdata)

    ,   .o_ic_rdata_ready       (c1_ic_rdata_ready)
    ,   .o_ic_req_valid         (c1_ic_req_valid)
    ,   .o_ic_req_addr          (c1_ic_req_addr)

        // D-Cache Request
    ,   .i_dc_req_ready         (c1_dc_req_ready)

    ,   .o_dc_req_valid         (c1_dc_req_valid)
    ,   .o_dc_req_addr          (c1_dc_req_addr)
    ,   .o_dc_req_cmd           (c1_dc_req_cmd)
    ,   .o_dc_req_data          (c1_dc_req_data)
    ,   .o_dc_req_wb            (c1_dc_req_wb)
    
        // D-Cache Response
    ,   .i_dc_resp_valid        (c1_dc_resp_valid)
    ,   .i_dc_resp_data         (c1_dc_resp_data)
    ,   .o_dc_resp_ready        (c1_dc_resp_ready)

        // Snoop Request (từ Core 0 bắn sang)
    ,   .i_snp_req_valid        (c1_snp_req_valid)
    ,   .i_snp_req_addr         (c1_snp_req_addr)
    ,   .i_snp_req_cmd          (c1_snp_req_cmd)
    ,   .i_resp_is_shared       (c1_resp_is_shared)

    ,   .o_snp_req_ready        (c1_snp_req_ready)
    
        // Snoop Response (tra loi Core 0)
    ,   .o_snp_resp_valid       (c1_snp_resp_valid)
    ,   .o_snp_resp_hit         (c1_snp_resp_hit)
    ,   .o_snp_resp_data        (c1_snp_resp_data)
    );

    // ================================================================
    // CACHE COHERENCE INTERCONNECT
    // ================================================================
    cache_coherence #(
        .ADDR_W(32)
    ,   .LINE_W(LINE_W)
    ) u_coherence (
        .clk                    (ACLK)
    ,   .rst_n                  (ARESETn)

        // --- Core 0 ---
    ,   .i_ic0_rdata_ready      (c0_ic_rdata_ready)
    ,   .i_ic0_req_valid        (c0_ic_req_valid)
    ,   .i_ic0_req_addr         (c0_ic_req_addr)
    
    ,   .o_ic0_req_ready        (c0_ic_req_ready)
    ,   .o_ic0_rdata_valid      (c0_ic_rdata_valid)
    ,   .o_ic0_rdata            (c0_ic_rdata)

    ,   .i_dc0_req_valid        (c0_dc_req_valid)
    ,   .o_dc0_req_ready        (c0_dc_req_ready)
    ,   .i_dc0_req_addr         (c0_dc_req_addr)
    ,   .i_dc0_req_cmd          (c0_dc_req_cmd)
    ,   .i_dc0_req_data         (c0_dc_req_data)
    
    ,   .i_dc0_resp_ready       (c0_dc_resp_ready)
    ,   .o_dc0_resp_valid       (c0_dc_resp_valid)
    ,   .o_dc0_resp_data        (c0_dc_resp_data)

    ,   .i_dc0_snp_req_ready    (c0_snp_req_ready)
    ,   .o_dc0_snp_req_valid    (c0_snp_req_valid)
    ,   .o_dc0_snp_req_addr     (c0_snp_req_addr)
    ,   .o_dc0_snp_req_cmd      (c0_snp_req_cmd)
    ,   .o_dc0_resp_is_shared   (c0_resp_is_shared)

    ,   .i_dc0_snp_resp_valid   (c0_snp_resp_valid)
    ,   .i_dc0_snp_resp_hit     (c0_snp_resp_hit)
    ,   .i_dc0_snp_resp_data    (c0_snp_resp_data)

        // --- Core 1 --- 
    ,   .i_ic1_rdata_ready      (c1_ic_rdata_ready)
    ,   .i_ic1_req_valid        (c1_ic_req_valid)
    ,   .i_ic1_req_addr         (c1_ic_req_addr)

    ,   .o_ic1_req_ready        (c1_ic_req_ready)
    ,   .o_ic1_rdata_valid      (c1_ic_rdata_valid)
    ,   .o_ic1_rdata            (c1_ic_rdata)

    ,   .i_dc1_req_valid        (c1_dc_req_valid)
    ,   .o_dc1_req_ready        (c1_dc_req_ready)
    ,   .i_dc1_req_addr         (c1_dc_req_addr)
    ,   .i_dc1_req_cmd          (c1_dc_req_cmd)
    ,   .i_dc1_req_data         (c1_dc_req_data)
    
    ,   .i_dc1_resp_ready       (c1_dc_resp_ready)
    ,   .o_dc1_resp_valid       (c1_dc_resp_valid)
    ,   .o_dc1_resp_data        (c1_dc_resp_data)

    ,   .i_dc1_snp_req_ready    (c1_snp_req_ready)
    ,   .o_dc1_snp_req_valid    (c1_snp_req_valid)
    ,   .o_dc1_snp_req_addr     (c1_snp_req_addr)
    ,   .o_dc1_snp_req_cmd      (c1_snp_req_cmd)
    ,   .o_dc1_resp_is_shared   (c1_resp_is_shared)

    ,   .i_dc1_snp_resp_valid   (c1_snp_resp_valid)
    ,   .i_dc1_snp_resp_hit     (c1_snp_resp_hit)
    ,   .i_dc1_snp_resp_data    (c1_snp_resp_data)

        // --- Giao tiếp xuống L2 ---
    ,   .L2_pipeline_stall      (L2_pipeline_stall)
    ,   .i_l2_req_ready         (l2_req_ready)
    ,   .o_l2_req_valid         (l2_req_valid)
    ,   .o_l2_req_addr          (l2_req_addr)
    ,   .o_l2_req_rw            (l2_req_rw)
    ,   .o_l2_req_wdata         (l2_req_wdata)

    ,   .i_l2_resp_valid        (l2_resp_valid)
    ,   .i_l2_resp_rdata        (l2_resp_rdata)
    );

    // ================================================================
    // CACHE L2 (SHARED)
    // ================================================================
    cache_L2 #(
        .ADDR_W         (32)
    ,   .DATA_W         (DATA_W)
    ,   .STRB_W         (STRB_W)
    ,   .NUM_WAYS       (NUM_WAYS)
    ,   .NUM_SETS       (NUM_SETS_L2)
    ,   .WORD_OFF_W     (WORD_OFF_W)
    ,   .BYTE_OFF_W     (BYTE_OFF_W)
    ) u_cache_L2 (
        .clk                    (ACLK)
    ,   .rst_n                  (ARESETn)

        // --- Giao tiếp với Coherence Interconnect ---
    ,   .o_l1_req_ready         (l2_req_ready)
    ,   .i_l1_req_valid         (l2_req_valid)
    ,   .i_l1_req_addr          (l2_req_addr)
    ,   .i_l1_req_rw            (l2_req_rw)
    ,   .i_l1_req_wdata         (l2_req_wdata)

    ,   .o_l1_resp_valid        (l2_resp_valid)
    ,   .o_l1_resp_rdata        (l2_resp_rdata)
    ,   .pipeline_stall         (L2_pipeline_stall)

        // --- Giao tiếp với AXI Bus Memory (day ra Port của Dual_Core) ---
    ,   .iAWREADY               (m00_axi_awready)
    ,   .oAWADDR                (m00_axi_awaddr)
    ,   .oAWLEN                 (m00_axi_awlen)
    ,   .oAWSIZE                (m00_axi_awsize)
    ,   .oAWBURST               (m00_axi_awburst)
    ,   .oAWVALID               (m00_axi_awvalid)

    ,   .iWREADY                (m00_axi_wready)
    ,   .oWDATA                 (m00_axi_wdata)
    ,   .oWSTRB                 (m00_axi_wstrb)
    ,   .oWLAST                 (m00_axi_wlast)
    ,   .oWVALID                (m00_axi_wvalid)

    ,   .iBRESP                 (m00_axi_bresp)
    ,   .iBVALID                (m00_axi_bvalid)
    ,   .oBREADY                (m00_axi_bready)

    ,   .iARREADY               (m00_axi_arready)
    ,   .oARADDR                (m00_axi_araddr)
    ,   .oARLEN                 (m00_axi_arlen)
    ,   .oARSIZE                (m00_axi_arsize)
    ,   .oARBURST               (m00_axi_arburst)
    ,   .oARVALID               (m00_axi_arvalid)

    ,   .iRDATA                 (m00_axi_rdata)
    ,   .iRRESP                 (m00_axi_rresp)
    ,   .iRLAST                 (m00_axi_rlast)
    ,   .iRVALID                (m00_axi_rvalid)
    ,   .oRREADY                (m00_axi_rready)
    );
endmodule