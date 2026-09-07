`timescale 1ns/1ps
`include "define.vh"
module cache_L2 #(
    parameter ADDR_W    = `ADDR_W
,   parameter DATA_W    = `DATA_W
,   parameter STRB_W    = DATA_W/8

    // Cache Parameters
,   parameter NUM_WAYS      = `NUM_WAYS
,   parameter NUM_SETS      = `NUM_SETS
,   parameter INDEX_W       = $clog2(NUM_SETS)
,   parameter WORD_OFF_W    = `WORD_OFF_W // 16 words
,   parameter BYTE_OFF_W    = `BYTE_OFF_W
,   parameter TAG_W         = ADDR_W - INDEX_W - WORD_OFF_W - BYTE_OFF_W
,   parameter LINE_W        = (1 << WORD_OFF_W) * 32   
)(
    input clk
,   input rst_n

    // ==========================================
    // UPSTREAM: Giao tiếp với L1 (Từ I-Arbiter & D-Cache của Core này)
    // ==========================================
,   output                      o_l1_req_ready
,   input                       i_l1_req_valid
,   input   [ADDR_W-1:0]        i_l1_req_addr
,   input                       i_l1_req_rw     // 0: Read, 1: Write
,   input   [LINE_W-1:0]        i_l1_req_wdata

// ,   input                       i_l1_resp_ready
,   output                      o_l1_resp_valid
,   output reg  [LINE_W-1:0]    o_l1_resp_rdata
,   output                      pipeline_stall

    // ==========================================
    //  (AXI Interface)
    // ==========================================
    // AW Channel
,   input                       iAWREADY
,   output  [ADDR_W-1:0]        oAWADDR
,   output  [7:0]               oAWLEN
,   output  [2:0]               oAWSIZE
,   output  [1:0]               oAWBURST
,   output                      oAWVALID

    // W channel
,   input                       iWREADY
,   output reg  [DATA_W-1:0]    oWDATA
,   output      [STRB_W-1:0]    oWSTRB
,   output                      oWLAST
,   output                      oWVALID
      
    // B channel
,   input   [1:0]               iBRESP
,   input                       iBVALID
,   output                      oBREADY

    // AR channel
,   input                       iARREADY
,   output  [ADDR_W-1:0]        oARADDR
,   output  [7:0]               oARLEN
,   output  [2:0]               oARSIZE
,   output  [1:0]               oARBURST
,   output                      oARVALID

    // R channel
,   input   [DATA_W-1:0]        iRDATA
,   input   [1:0]               iRRESP
,   input                       iRLAST
,   input                       iRVALID
,   output                      oRREADY
);
    // ================================================================
    // REG DECLARATIONS
    // ================================================================
    // Memory Arrays
    reg [NUM_WAYS-1:0]  dirty_array [0:NUM_SETS-1];
    reg [NUM_WAYS-1:0]  valid_array [0:NUM_SETS-1];
    
    // Refill Buffer
    reg [LINE_W-1:0]    refill_buffer;

    // ================================================================
    // WIRE DECLARATIONS
    // ================================================================
    // Stage 1 Signals
    wire [TAG_W-1:0]        s1_tag;
    wire [INDEX_W-1:0]      s1_index;
    wire [WORD_OFF_W-1:0]   s1_word_off;
    wire [BYTE_OFF_W-1:0]   s1_byte_off;
    
    // Stage 2 Signals
    wire [TAG_W-1:0]        s2_tag;
    wire [INDEX_W-1:0]      s2_index;
    wire [WORD_OFF_W-1:0]   s2_word_off;
    wire [BYTE_OFF_W-1:0]   s2_byte_off;
    wire                    s2_req;
    wire [1:0]              s2_cmd;
    
    // Memory Arrays Output
    wire [TAG_W-1:0]    tag_read    [0:NUM_WAYS-1];
    wire [LINE_W-1:0]   data_read   [0:NUM_WAYS-1];
    wire [NUM_WAYS-1:0] current_valid;
    wire [NUM_WAYS-1:0] current_dirty;
    
    // Hit Logic
    wire [NUM_WAYS-1:0]     way_hit;
    wire [NUM_WAYS-1:0]     way_write_enable;
    wire                    any_hit;
    
    // Controller Signals
    wire                    tag_we;
    wire                    refill_we;
    wire [NUM_WAYS-1:0]     way_select;
    wire                    stall_contoller;
    wire                    refill_src;
    wire [3:0]              burst_cnt;
    wire [INDEX_W-1:0]      mem_read_index;

    reg [TAG_W-1:0]         victim_tag;
    // wire [2:0] s2_tree_out; // Data của PLRU đã sẵn sàng ở Stage 2
    // wire [2:0] s2_tree_in;  // Data tính toán xong chờ ghi lại
    // ================================================================
    // COMBINATORIAL LOGIC (Assign Statements)
    // ================================================================
    assign current_dirty    = dirty_array[s2_index];
    assign current_valid    = valid_array[s2_index];
    assign pipeline_stall   = stall_contoller;
    assign any_hit          = |way_hit;
    
    // AXI Address Assignments
    assign oAWADDR          = {victim_tag, s2_index, {WORD_OFF_W{1'b0}}, {BYTE_OFF_W{1'b0}}};
    // assign oAWADDR          = {s2_tag, s2_index, {WORD_OFF_W{1'b0}}, {BYTE_OFF_W{1'b0}}};
    
    assign oARADDR          = {s2_tag, s2_index, {WORD_OFF_W{1'b0}}, {BYTE_OFF_W{1'b0}}};
    assign mem_read_index   = pipeline_stall ? s2_index : s1_index;

    // Hit Logic
    assign way_hit[0]       = (tag_read[0] == s2_tag) & current_valid[0];
    assign way_hit[1]       = (tag_read[1] == s2_tag) & current_valid[1];
    assign way_hit[2]       = (tag_read[2] == s2_tag) & current_valid[2];
    assign way_hit[3]       = (tag_read[3] == s2_tag) & current_valid[3];
    assign way_write_enable = any_hit ? way_hit : way_select;
    // ================================================================
    // SYNCHRONOUS LOGIC (always @(posedge clk))
    // ================================================================
    // Refill Buffer: Receive data from Memory (AXI R) or L1 (Writeback)
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            refill_buffer <= {LINE_W{1'b0}};
        end 
        else begin 
            // Case 1: Refill from Memory (AXI R Channel)
            if (iRVALID & oRREADY) begin
                refill_buffer[burst_cnt * DATA_W +: DATA_W] <= iRDATA;
            end 

            // Case 2: Writeback from L1 (L1 Interface)
            else if (i_l1_req_valid && o_l1_req_ready) begin
                refill_buffer <= i_l1_req_wdata;
            end
        end 
    end

    // Dirty Array Logic
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            for(k = 0; k < NUM_SETS; k = k + 1) begin 
                dirty_array[k] <= {NUM_WAYS{1'b0}};
            end
        end 
        else begin
            // Case 1: Refill from Memory (AXI R Channel)
            if (refill_we) begin
                if (s2_cmd[0]) // Write Miss từ L1 -> Set Dirty
                    dirty_array[s2_index] <= dirty_array[s2_index] | way_select;
                else           // Read Miss từ Mem -> Clean
                    dirty_array[s2_index] <= dirty_array[s2_index] & (~way_select);
            end 

            // Case 2: Writeback from L1 (L1 Interface)
            else if (s2_cmd[0] && any_hit) begin
                dirty_array[s2_index] <= dirty_array[s2_index] | way_hit;
            end
        end
    end

    // Valid Array Logic
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for(k = 0; k < NUM_SETS; k = k + 1) begin 
                valid_array[k] <= {NUM_WAYS{1'b0}};
            end
        end 
        else begin
            if (refill_we) begin
                // Nạp block mới -> Bật bit valid của way được chọn lên 1
                valid_array[s2_index] <= valid_array[s2_index] | way_select;
            end
        end
    end

    // ================================================================
    // COMBINATORIAL LOGIC (always @(*))
    // ================================================================
    // OUTPUT DATA LOGIC (L2 -> L1)
    always @(*) begin
        if (refill_we) 
            o_l1_resp_rdata = refill_buffer; // Bypass Data mới nạp
        else begin
            case(way_hit)
                4'b0001: o_l1_resp_rdata = data_read[0];
                4'b0010: o_l1_resp_rdata = data_read[1];
                4'b0100: o_l1_resp_rdata = data_read[2];
                4'b1000: o_l1_resp_rdata = data_read[3];
                default: o_l1_resp_rdata = {LINE_W{1'b0}};
            endcase
        end
    end

    // MUX WRITE DATA for AXI Write
    always @(*) begin
        // Dùng way_select vì ghi ngược luôn lấy Victim block
        case(way_select)
            4'b0001: oWDATA = data_read[0][burst_cnt*DATA_W +: DATA_W];
            4'b0010: oWDATA = data_read[1][burst_cnt*DATA_W +: DATA_W];
            4'b0100: oWDATA = data_read[2][burst_cnt*DATA_W +: DATA_W];
            4'b1000: oWDATA = data_read[3][burst_cnt*DATA_W +: DATA_W];
            default: oWDATA = {DATA_W{1'b0}};
        endcase
    end

    // Victim Tag Selection
    always @(*) begin
        case(way_select)
            4'b0001: victim_tag = tag_read[0];
            4'b0010: victim_tag = tag_read[1];
            4'b0100: victim_tag = tag_read[2];
            4'b1000: victim_tag = tag_read[3];
            default: victim_tag = {TAG_W{1'b0}};
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
        .cpu_addr               (i_l1_req_addr)

    ,   .cpu_tag                (s1_tag)         
    ,   .cpu_index              (s1_index)   
    ,   .cpu_word_off           (s1_word_off)
    ,   .cpu_byte_off           (s1_byte_off)
    );

    // ================================================================
    // SRAM ARRAYS
    // ================================================================
    // --- Tag RAMs ---
    genvar i;
    generate
        for (i = 0; i < NUM_WAYS; i = i + 1) begin : tag_rams
            tag_mem #( 
                .NUM_SETS   (NUM_SETS)
            ,   .TAG_W      (TAG_W) 
            ) u_tag_mem (
                .clk                    (clk)
            ,   .rst_n                  (rst_n)

            ,   .tag_we                 (tag_we & way_write_enable[i])
            ,   .read_index             (mem_read_index)
            ,   .write_index            (s2_index)
            ,   .din_tag                (s2_tag)        
            ,   .dout_tag               (tag_read[i])

            ,   .valid_we               ()
            ,   .valid                  ()
            ,   .moesi_we               ()
            ,   .moesi_next_state       ()
            ,   .moesi_current_state    ()
            );
        end
    endgenerate

    // --- Data RAMs ---
    generate
        for (i = 0; i < NUM_WAYS; i = i + 1) begin : data_rams
            data_mem #( 
                .DATA_W     (DATA_W) 
            ,   .NUM_SETS   (NUM_SETS) 
            ) u_data_mem (
                .clk            (clk)
            ,   .read_index     (mem_read_index)
            ,   .dout           (data_read[i])
                
                // Ghi nguyen dong cache
            ,   .refill_we      (refill_we & way_write_enable[i])
            ,   .write_index    (s2_index)
            ,   .refill_din     (refill_buffer)
                
                // Ghi tung word (hien tai ko dung o L2)
            ,   .cpu_din        (32'd0)
            ,   .cpu_we         (1'b0) 
            ,   .cpu_wstrb      (4'b0)           
            ,   .cpu_offset     (4'b0)
            );
        end
    endgenerate

    // ================================================================
    // PIPELINE REGISTER
    // ================================================================
    acc_cmp #(
        .ADDR_W     (ADDR_W), 
        .DATA_W     (DATA_W), 
        .NUM_SETS   (NUM_SETS)
    ) acc_cmp_inst (
        .clk        (clk)
    ,   .rst_n      (rst_n)
    ,   .stall      (pipeline_stall)

        // Stage 1 Inputs (Mapped from L1 interface)
    ,   .s1_req         (i_l1_req_valid)  
    ,   .s1_cmd         ({1'b0, i_l1_req_rw})    
    ,   .s1_tag         (s1_tag)   
    ,   .s1_index       (s1_index) 
    ,   .s1_word_off    (s1_word_off)
    ,   .s1_byte_off    (s1_byte_off)

        // Stage 2 Outputs
    ,   .s2_req         (s2_req)
    ,   .s2_cmd         (s2_cmd)        // hien tai dung i_l1_req_rw
    ,   .s2_tag         (s2_tag)
    ,   .s2_index       (s2_index)
    ,   .s2_word_off    (s2_word_off)
    ,   .s2_byte_off    (s2_byte_off)

    // not use
    ,   .s1_we          ()
    ,   .s1_size        ()
    ,   .s1_is_snoop    ()
    ,   .s1_lr          ()
    ,   .s1_sc          ()
    ,   .s1_amo         ()
    ,   .s1_amo_op      ()
    ,   .s1_wdata       ()

    ,   .s2_we          ()
    ,   .s2_size        ()
    ,   .s2_is_snoop    ()
    ,   .s2_lr          ()
    ,   .s2_sc          ()
    ,   .s2_amo         ()
    ,   .s2_amo_op      ()
    ,   .s2_wdata       ()
    );

    // ================================================================
    // REPLACEMENT POLICY
    // ================================================================
    cache_replacement #( 
        .N_WAYS     (NUM_WAYS) 
    ,   .N_LINES    (NUM_SETS) 
    ) u_replacement (
        .clk        (clk)
    ,   .rst_n      (rst_n)
    ,   .we         (any_hit)
    ,   .way_hit    (way_hit)
    ,   .read_addr  (s1_index)
    ,   .write_addr (s2_index)
    ,   .way_select (way_select)
    );

    // ================================================================
    // CONTROLLER
    // ================================================================
    cache_L2_controller #(
        .ADDR_W     (ADDR_W) 
    ,   .DATA_W     (DATA_W)
    ,   .WORD_OFF_W (WORD_OFF_W)
    ) controller (
        .clk                (clk)
    ,   .rst_n              (rst_n)

        // L1 Interface
    ,   .s2_req_valid       (s2_req)
    ,   .i_l1_req_rw        (s2_cmd[0]) // hien tai dung i_l1_req_rw
    ,   .hit                (any_hit)
    ,   .is_valid           (|current_valid)
    ,   .victim_dirty       (|current_dirty)

        // Controller -> Datapath Control Signals
    ,   .o_l1_req_ready     (o_l1_req_ready)
    ,   .o_l1_resp_valid    (o_l1_resp_valid)

    ,   .tag_we             (tag_we)
    ,   .refill_we          (refill_we)
    ,   .refill_src         (refill_src)    // chua dung
    ,   .stall               (stall_contoller)

    // AXI Master Interface
    // AW Channel
    ,   .iAWREADY          (iAWREADY)
    ,   .oAWVALID          (oAWVALID)
    ,   .oAWLEN            (oAWLEN)
    ,   .oAWSIZE           (oAWSIZE)
    ,   .oAWBURST          (oAWBURST)

    // W channel
    ,   .iWREADY           (iWREADY)
    ,   .oWVALID           (oWVALID)
    ,   .oWLAST            (oWLAST)
    ,   .oWSTRB            (oWSTRB)
    ,   .burst_cnt         (burst_cnt)

    // B channel
    ,   .iBVALID           (iBVALID)
    ,   .iBRESP            (iBRESP)
    ,   .oBREADY           (oBREADY)

    // AR channel
    ,   .iARREADY          (iARREADY)
    ,   .oARLEN            (oARLEN)
    ,   .oARSIZE           (oARSIZE)
    ,   .oARBURST          (oARBURST)
    ,   .oARVALID          (oARVALID)

    // R channel
    ,   .iRVALID           (iRVALID)
    ,   .iRRESP            (iRRESP)
    ,   .iRLAST            (iRLAST)
    ,   .oRREADY           (oRREADY)
    );

endmodule