`timescale 1ns/1ps
`include "define.vh"
// from Lee Min Hunz with luv
// ============================================================================
// ICache - L1 Instruction Cache (Read-Only)
// ============================================================================
// N-way set-associative instruction cache with PLRU replacement.
// 2-stage pipeline: S1 (address decode) -> S2 (tag compare + data read)
// ============================================================================
module icache #(
    parameter ADDR_W        = `ADDR_W
,   parameter DATA_W        = `DATA_W
,   parameter NUM_WAYS      = `NUM_WAYS
,   parameter NUM_SETS      = `NUM_SETS
    
    // Derived parameters
,   parameter INDEX_W       = $clog2(NUM_SETS)
,   parameter WORD_OFF_W    = `WORD_OFF_W
,   parameter BYTE_OFF_W    = `BYTE_OFF_W
,   parameter TAG_W         = ADDR_W - INDEX_W - WORD_OFF_W - BYTE_OFF_W
,   parameter LINE_W        = (1 << WORD_OFF_W) * 32
)(
    input clk, rst_n

    // cache <-> CPU
,   input                   cpu_req
,   input                   fetch_stall
// ,   input                   icache_flush
,   input   [ADDR_W-1:0]    cpu_addr
,   output  [DATA_W-1:0]    data_rdata
,   output                  pipeline_stall

    // icache <-> dcache
,   input                   dcache_stall

    // cache <-> L2
    // Request
,   input                   i_l2_req_ready
,   output                  o_l2_req_valid
,   output  [ADDR_W-1:0]    o_l2_req_addr

    // Read Data (Refill L2 -> icache)
,   input                   i_l2_rdata_valid
,   input   [LINE_W-1:0]    i_l2_rdata
,   output                  o_l2_rdata_ready
);

    // ================================================================
    // REG DECLARATIONS
    // ================================================================
    // Pipeline Buffers
    reg [LINE_W-1:0]    refill_buffer;
    
    // Data Output Selection
    reg [DATA_W-1:0]    word_select;

    // ================================================================
    // WIRE DECLARATIONS
    // ================================================================
    // Stage 1 Address Decode
    wire [TAG_W-1:0]        s1_tag;
    wire [INDEX_W-1:0]      s1_index;
    wire [WORD_OFF_W-1:0]   s1_word_off;
    wire [BYTE_OFF_W-1:0]   s1_byte_off;
    
    // Stage 2 Pipeline Signals
    wire [TAG_W-1:0]        s2_tag;
    wire [INDEX_W-1:0]      s2_index;
    wire [WORD_OFF_W-1:0]   s2_word_off;
    wire [BYTE_OFF_W-1:0]   s2_byte_off;
    wire                    s2_req;

    // Memory Arrays Output
    wire [TAG_W-1:0]        tag_read    [0:NUM_WAYS-1];
    wire [LINE_W-1:0]       data_read   [0:NUM_WAYS-1];
    wire [NUM_WAYS-1:0]     current_valid;

    // Controller Signals
    wire                    tag_we, refill_we;
    wire [NUM_WAYS-1:0]     way_hit;
    wire [NUM_WAYS-1:0]     way_select;
    wire                    cpu_hit;
    wire                    read_index_src;
    wire                    stall_controller;
    wire [INDEX_W-1:0]      mem_read_index;

    wire [2:0] s2_tree_out; // Data của PLRU đã sẵn sàng ở Stage 2
    wire [2:0] s2_tree_in;  // Data tính toán xong chờ ghi lại

    // ================================================================
    // REFILL BUFFER LOGIC (always @(posedge clk))
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin 
            refill_buffer <= {LINE_W{1'b0}};
        end 
        else if (i_l2_rdata_valid && o_l2_rdata_ready) begin
             refill_buffer <= i_l2_rdata;
        end
    end

    // ================================================================
    // COMBINATORIAL LOGIC (always @(*))
    // ================================================================
    // DERIVED SIGNALS
    assign o_l2_req_addr    = {s2_tag, s2_index, {WORD_OFF_W{1'b0}}, {BYTE_OFF_W{1'b0}}};
    assign pipeline_stall   = stall_controller;
    wire internal_stall     = stall_controller | fetch_stall | dcache_stall;
    assign cpu_hit          = (|way_hit) & s2_req;
    assign data_rdata       = word_select;
    assign mem_read_index   = internal_stall ? s2_index : s1_index;

    // STAGE 2: HIT LOGIC
    assign way_hit[0] = (tag_read[0] == s2_tag) & current_valid[0];
    assign way_hit[1] = (tag_read[1] == s2_tag) & current_valid[1];
    assign way_hit[2] = (tag_read[2] == s2_tag) & current_valid[2];
    assign way_hit[3] = (tag_read[3] == s2_tag) & current_valid[3];

    // OUTPUT MUX
    always @(*) begin
        case({s2_req, way_hit})
            5'b10001: word_select = data_read[0][s2_word_off * DATA_W +: DATA_W];
            5'b10010: word_select = data_read[1][s2_word_off * DATA_W +: DATA_W];
            5'b10100: word_select = data_read[2][s2_word_off * DATA_W +: DATA_W];
            5'b11000: word_select = data_read[3][s2_word_off * DATA_W +: DATA_W];
            default: word_select = 32'd0;
        endcase
    end

    // ================================================================
    // MODULE INSTANTIATIONS
    // ================================================================
    // STAGE 1: ACCESS
    // ================================================================
    access #(
        .ADDR_W     (ADDR_W)
    ,   .DATA_W     (DATA_W)
    ,   .NUM_SETS   (NUM_SETS)
    ,   .WORD_OFF_W (WORD_OFF_W)
    ,   .BYTE_OFF_W (BYTE_OFF_W)
    ) access_inst (
        .cpu_addr       (cpu_addr)
    ,   .cpu_tag        (s1_tag)           
    ,   .cpu_index      (s1_index)
    ,   .cpu_word_off   (s1_word_off)
    ,   .cpu_byte_off   (s1_byte_off)
    );
    
    // ================================================================
    // SRAM ARRAYS
    // ================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_WAYS; i = i + 1) begin : rams
            // Tag RAM
            tag_mem #(
                .NUM_SETS   (NUM_SETS)
            ,   .TAG_W      (TAG_W)
            ) u_tag_mem (
                .clk            (clk)
            ,   .rst_n          (rst_n)

                // Port read
            ,   .read_index     (mem_read_index)
            ,   .dout_tag       (tag_read[i])
            ,   .valid          (current_valid[i])

                // Port write
            ,   .tag_we         (tag_we & way_select[i])
            ,   .valid_we       (refill_we & way_select[i])
            ,   .write_index    (s2_index)
            ,   .din_tag        (s2_tag)  

            // not use
            ,   .moesi_we               ()
            ,   .moesi_next_state       ()
            ,   .moesi_current_state    ()
            );

            // Data RAM (Read Only cho CPU)
            data_mem #(
                .DATA_W     (DATA_W)
            ,   .NUM_SETS   (NUM_SETS)
            ) u_data_mem (
                .clk            (clk)
            // ,   .rst_n          (rst_n)

                // Port read
            ,   .read_index     (mem_read_index)
            ,   .dout           (data_read[i])

                 // refill
            ,   .write_index    (s2_index)
            ,   .refill_we      (refill_we & way_select[i])
            ,   .refill_din     (refill_buffer)

                // not used
            ,   .cpu_we         ()
            ,   .cpu_din        ()
            ,   .cpu_wstrb      ()  
            ,   .cpu_offset     ()
            );
        end
    endgenerate

    // ================================================================
    // PIPELINE REGISTER
    // ================================================================
    acc_cmp #(
        .ADDR_W     (ADDR_W)
    ,   .DATA_W     (DATA_W)
    ,   .NUM_SETS   (NUM_SETS)
    ) acc_cmp_inst (
        .clk            (clk)
    ,   .rst_n          (rst_n)
    ,   .stall          (internal_stall)

        // Inputs
    ,   .s1_req         (cpu_req)
    ,   .s1_tag         (s1_tag)
    ,   .s1_index       (s1_index)
    ,   .s1_word_off    (s1_word_off)
    ,   .s1_byte_off    (s1_byte_off)
    
        // Outputs (Stage 2) 
    ,   .s2_req         (s2_req)
    ,   .s2_tag         (s2_tag)
    ,   .s2_index       (s2_index)
    ,   .s2_word_off    (s2_word_off)
    ,   .s2_byte_off    (s2_byte_off)

    // not use
    ,   .s1_we          ()
    ,   .s1_cmd         ()
    ,   .s1_size        ()
    ,   .s1_wdata       ()
    ,   .s1_is_snoop    ()
    ,   .s1_lr          ()
    ,   .s1_sc          ()
    ,   .s1_amo         ()
    ,   .s1_amo_op      ()

    ,   .s2_we          ()
    ,   .s2_cmd         ()
    ,   .s2_size        ()
    ,   .s2_wdata       ()
    ,   .s2_is_snoop    ()
    ,   .s2_lr          ()
    ,   .s2_sc          ()
    ,   .s2_amo         ()
    ,   .s2_amo_op      ()
    );

    // ================================================================
    // REPLACEMENT & CONTROLLER
    // ================================================================
    cache_replacement #( 
        .N_WAYS     (NUM_WAYS)
    ,   .N_LINES    (NUM_SETS) 
    ) u_replacement (
        .clk        (clk)
    ,   .rst_n      (rst_n)
    ,   .we         (cpu_hit)
    ,   .way_hit    (way_hit)
    ,   .read_addr  (s1_index)
    ,   .write_addr (s2_index)
    ,   .way_select (way_select)
    );

    icache_controller #(
        .DATA_W     (DATA_W)
    ,   .ADDR_W     (ADDR_W)
    ) icache_controller (
        .clk                (clk)
    ,   .rst_n              (rst_n)
    // ,   .flush              (1'b0)
        
    ,   .cpu_req            (s2_req)
    ,   .hit                (cpu_hit)

    ,   .tag_we             (tag_we) 
    ,   .refill_we          (refill_we)
    ,   .stall              (stall_controller)
    ,   .read_index_src     (read_index_src)

    ,   .o_mem_req_valid    (o_l2_req_valid)
    ,   .i_mem_req_ready    (i_l2_req_ready)

    ,   .i_mem_rdata_valid  (i_l2_rdata_valid)
    ,   .o_mem_rdata_ready  (o_l2_rdata_ready)
    );

endmodule