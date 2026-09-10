`timescale 1ns/1ps
`include "define.vh"
// from Lee Min Hunz with luv
module d_cache #(
    parameter ADDR_W        = `ADDR_W
,   parameter DATA_W        = `DATA_W
,   parameter NUM_WAYS      = `NUM_WAYS
,   parameter NUM_SETS      = `NUM_SETS
,   parameter DATA_START    = `DATA_START
    
    // Derived parameters
,   parameter INDEX_W       = $clog2(NUM_SETS)
,   parameter WORD_OFF_W    = `WORD_OFF_W // 16 words
,   parameter BYTE_OFF_W    = `BYTE_OFF_W
,   parameter TAG_W         = ADDR_W - INDEX_W - WORD_OFF_W - BYTE_OFF_W
,   parameter LINE_W        = (1 << WORD_OFF_W) * 32
,   parameter ID_W          = 2
,   parameter STRB_W        = (DATA_W/8)
)(
    input clk
,   input rst_n

    // ================= CPU INTERFACE =================
,   input                       cpu_req
,   input                       cpu_we
,   input   [ADDR_W-1:0]        cpu_addr
,   input   [DATA_W-1:0]        cpu_din
,   input   [1:0]               cpu_size
,   input                       cpu_flush
    
    // Them tin hieu Atomic tu CPU
,   input                       cpu_lr
,   input                       cpu_sc
,   input                       cpu_amo
,   input   [2:0]               cpu_amo_op
,   output                      o_sc_success // Tra ve ket qua SC (0=Success, 1=Fail)

,   output  reg [DATA_W-1:0]    data_rdata
,   output                      pipeline_stall

    // ================= Snoop Interface =================
    // REQUEST CHANNEL (D-Cache request Snoop)
,   input                   i_req_ready
,   output                  o_req_valid
,   output [ADDR_W-1:0]     o_req_addr
    // (00=Read Shared, 01=Write Back, 10=Upgrade/Invalidate Others, 11=READ UNIQUE)
,   output [1:0]                o_req_cmd    
,   output  reg [LINE_W-1:0]    o_req_data  // writeback data
,   output                      o_req_wb    // Báo hiệu đang đẩy victim data (để Arbiter ưu tiên cấp bus)
    
    // SNOOP RESPONSE DCACHE
,   input                   i_resp_valid
,   input  [LINE_W-1:0]     i_resp_data
,   output                  o_resp_ready

    // SNOOP REQUEST DCACHE
,   input                   i_snp_req_valid
,   input  [ADDR_W-1:0]     i_snp_req_addr
,   input  [1:0]            i_snp_req_cmd
,   input                   i_resp_is_shared 
// ,   input                   i_resp_is_dirty
,   output                  o_snp_req_ready

    // DCACHE RESPONSE SNOOP

    // hien tai dang dinh check va tra response luon con handshake thi lam o cache coherence 
,   output                      o_snp_resp_valid
// ,   input                    i_snp_resp_ready    // coi lai xu ly
,   output                      o_snp_resp_hit      
,   output  reg [LINE_W-1:0]    o_snp_resp_data
// ,   output                   snoop_req_invalidate
);
    // Bus Commands
    localparam CMD_READ_SHARED = 2'b00, CMD_WRITE_BACK = 2'b01, CMD_UPGRADE = 2'b10, CMD_READ_UNIQUE = 2'b11;

    // MOESI States
    localparam STATE_M = 3'd0, STATE_O = 3'd1, STATE_E = 3'd2, STATE_S = 3'd3, STATE_I = 3'd4;
    // ================================================================
    // 1) REG DECLARATIONS
    // ================================================================
    // MOESI State Selection
    reg [2:0]               moesi_selected_state;
    reg [2:0]               victim_moesi_state;

    // Data Buffers
    reg [LINE_W-1:0]        refill_buffer;      // Buffer for memory refill data
    reg                     is_shared_buffer;

    // Data Output & Selection
    // reg [ADDR_W-1:0]        o_req_addr_reg;
    reg [DATA_W-1:0]        word_select;
    reg [DATA_W-1:0]        raw_rdata;
    reg                     raw_en;

    // Victim Tag (for writeback address)
    reg [TAG_W-1:0]         victim_tag;
    reg [ADDR_W-1:0]        victim_addr_reg;
    reg [ADDR_W-1:0]        refill_addr_reg;

    // ================================================================
    // 2) WIRE DECLARATIONS
    // ================================================================
    // Stage 1 Address Decode (Cycle 1: Access)
    wire [TAG_W-1:0]        s1_tag;
    // wire [TAG_W-1:0]        s1_ac_tag;
    wire [INDEX_W-1:0]      s1_index;
    // wire [INDEX_W-1:0]      s1_ac_index;
    wire [WORD_OFF_W-1:0]   s1_word_off;
    wire [BYTE_OFF_W-1:0]   s1_byte_off;

    // Stage 2 Pipeline Signals (Cycle 2: Compare)
    wire                    s2_req;
    wire                    s2_we;
    wire [1:0]              s2_size;
    wire [DATA_W-1:0]       s2_wdata;
    wire [TAG_W-1:0]        s2_tag;
    wire [TAG_W-1:0]        s2_snoop_tag;
    wire [INDEX_W-1:0]      s2_index;
    wire [INDEX_W-1:0]      s2_snoop_index;
    wire [WORD_OFF_W-1:0]   s2_word_off;
    wire [WORD_OFF_W-1:0]   s2_snoop_word_off;
    wire [BYTE_OFF_W-1:0]   s2_byte_off;
    wire [BYTE_OFF_W-1:0]   s2_snoop_byte_off;
    wire [1:0]              s2_cmd;
    wire                    s2_is_snoop;

    // Stage 2 Atomic Signals
    wire [DATA_W-1:0]       amo_alu_result;
    wire                    s2_atomic_lr;
    wire                    s2_atomic_sc;
    wire                    s2_atomic_amo;
    wire [2:0]              s2_amo_op;
    wire                    sc_done;

    // Control Signals
    wire                    cpu_hit;
    wire valid_snoop_req    = i_snp_req_valid & ctrl_snoop_ready;
    wire snoop_busy         = i_snp_req_valid | s2_is_snoop;
    // wire                    snoop_can_access_ram;
    // wire                    reg_snoop_stall;
    wire                    stall_controller;
    wire                    snoop_req_invalidate;

    // Memory Arrays Output
    wire [TAG_W-1:0]    tag_read    [0:NUM_WAYS-1];
    wire [LINE_W-1:0]   data_read   [0:NUM_WAYS-1];
    wire [INDEX_W-1:0]  mem_read_index;
    
    // MOESI & Hit Logic
    wire [3:0]  cpu_way_hit;
    wire [3:0]  snoop_way_hit;
    wire [3:0]  active_way_hit;
    wire [3:0]  way_select;
    // wire [3:0]  way_select_final;
    wire [3:0]  choosen_way;
    wire        cpu_any_hit;
    wire        snoop_any_hit;
    wire        active_any_hit;
    wire [2:0]  moesi_current_state     [0:NUM_WAYS-1];
    wire [2:0]  moesi_next_state;
    wire        moesi_we, snoop_moesi_we, main_moesi_we;
    // wire        is_unique;
    // wire        is_owner; 
    wire        victim_dirty;
    wire        victim_valid;
    
    // Controller Output Signals
    wire        tag_we;
    wire        data_we;
    wire        refill_we;
    // wire [3:0]  burst_cnt;
    // wire [3:0]  burst_cnt_snoop;

    // Address Muxing
    wire [ADDR_W-1:0]   s1_mux_addr;
    wire [TAG_W-1:0]    tag_select;

    // Address Generation
    wire [ADDR_W-1:0]       s2_full_addr;
    wire [ADDR_W-1:0]       snoop_full_addr;
    wire [ADDR_W-1:0]       victim_addr_full;
    wire [ADDR_W-1:0]       refill_addr_full;

    // Tín hiệu xác nhận Snoop hợp lệ: Chỉ lọt vào pipeline khi Controller đang ở TAG_CHECK
    // ================================================================
    // 3) ASSIGN - DERIVED SIGNALS
    // ================================================================
    // Address Muxing & Generation
    assign s2_full_addr     = {s2_tag, s2_index, s2_word_off, s2_byte_off};
    assign snoop_full_addr  = {s2_snoop_tag, s2_snoop_index, s2_snoop_word_off, s2_snoop_byte_off};
    
    assign mem_read_index   = valid_snoop_req ? s1_index : (pipeline_stall ? s2_index : s1_index);

    assign s1_mux_addr      = (valid_snoop_req)             ? i_snp_req_addr    : (cpu_addr | DATA_START);
    // assign o_req_addr       = (o_req_cmd == CMD_WRITE_BACK) ? victim_addr_full  : refill_addr_full;
    assign victim_addr_full = {victim_tag, s2_index, {WORD_OFF_W{1'b0}}, {BYTE_OFF_W{1'b0}}};
    assign refill_addr_full = {s2_tag, s2_index, {WORD_OFF_W{1'b0}}, {BYTE_OFF_W{1'b0}}};

    // Way Selection & MOESI Control
    assign active_way_hit   = s2_is_snoop ? snoop_way_hit : cpu_way_hit;
    assign active_any_hit   = s2_is_snoop ? snoop_any_hit : cpu_any_hit;
    assign choosen_way      = (active_any_hit) ? active_way_hit : way_select;
    wire [INDEX_W-1:0] index_select = (s2_is_snoop) ? s2_snoop_index : s2_index;
    assign moesi_we         = main_moesi_we | snoop_moesi_we;

    // Pipeline Stall
    // Dùng valid_snoop_req thay vì snoop_busy để không block pipeline khi controller chủ động chặn snoop
    assign pipeline_stall   = stall_controller | valid_snoop_req | s2_is_snoop;

    // STAGE 2: HIT LOGIC
    assign cpu_way_hit[0]   = (tag_read[0] == s2_tag) & (moesi_current_state[0] != STATE_I);
    assign cpu_way_hit[1]   = (tag_read[1] == s2_tag) & (moesi_current_state[1] != STATE_I);
    assign cpu_way_hit[2]   = (tag_read[2] == s2_tag) & (moesi_current_state[2] != STATE_I);
    assign cpu_way_hit[3]   = (tag_read[3] == s2_tag) & (moesi_current_state[3] != STATE_I);

    assign snoop_way_hit[0] = (tag_read[0] == s2_snoop_tag) & (moesi_current_state[0] != STATE_I);
    assign snoop_way_hit[1] = (tag_read[1] == s2_snoop_tag) & (moesi_current_state[1] != STATE_I);
    assign snoop_way_hit[2] = (tag_read[2] == s2_snoop_tag) & (moesi_current_state[2] != STATE_I);
    assign snoop_way_hit[3] = (tag_read[3] == s2_snoop_tag) & (moesi_current_state[3] != STATE_I);

    assign cpu_any_hit      = |cpu_way_hit;
    assign snoop_any_hit    = |snoop_way_hit;
    
    assign o_snp_resp_hit   = snoop_any_hit & s2_is_snoop;
    assign cpu_hit          = cpu_any_hit & s2_req & ~s2_is_snoop;

    // Gán giá trị đã được chốt (Registered) ra port giao tiếp thay vì mạch tổ hợp
    assign o_req_addr       = (o_req_cmd == CMD_WRITE_BACK) ? victim_addr_reg : refill_addr_reg;
    
    // ================================================================
    // 4) ALWAYS @(posedge clk) - SEQUENTIAL LOGIC
    // ================================================================
    // PIPELINE REGISTER - RAW (Read After Write) detection
    // when write hit and after that we read from the same address
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            raw_rdata   <= {DATA_W{1'b0}};
            raw_en      <= 1'b0;
        end 
        else begin
            if (s1_index == s2_index && s2_we && cpu_hit) begin
                raw_rdata   <= s2_wdata;
                raw_en      <= 1'b1;
            end
            else begin
                raw_rdata   <= {DATA_W{1'b0}};
                raw_en      <= 1'b0;
            end
        end
    end

    // REFILL & SNOOP BUFFER LOGIC
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            refill_buffer       <= {LINE_W{1'b0}};
            is_shared_buffer    <= 1'b0;
        end 
        else begin 
            if (i_resp_valid & o_resp_ready) begin
                // refill_buffer[burst_cnt * DATA_W +: DATA_W] <= iRDATA;
                refill_buffer       <= i_resp_data;
                is_shared_buffer    <= i_resp_is_shared;
            end 
        end 
    end

    // ================================================================
    // PIPELINE REGISTER FOR OUTBOUND REQUESTS (GIẢM DELAY)
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            victim_addr_reg <= {ADDR_W{1'b0}};
            refill_addr_reg <= {ADDR_W{1'b0}};
            o_req_data      <= {LINE_W{1'b0}};
        end 
        else begin
            victim_addr_reg <= victim_addr_full;
            refill_addr_reg <= refill_addr_full;
            case(way_select)
                4'b0001: o_req_data <= data_read[0];
                4'b0010: o_req_data <= data_read[1];
                4'b0100: o_req_data <= data_read[2];
                4'b1000: o_req_data <= data_read[3];
                default: o_req_data <= {LINE_W{1'b0}};
            endcase
        end
    end

    // ================================================================
    // 5) ALWAYS @(*) - COMBINATIONAL LOGIC
    // ================================================================
    // MOESI State Selection Mux
    always @(*) begin
        case (active_way_hit)
            4'b0001: moesi_selected_state = moesi_current_state[0];
            4'b0010: moesi_selected_state = moesi_current_state[1];
            4'b0100: moesi_selected_state = moesi_current_state[2];
            4'b1000: moesi_selected_state = moesi_current_state[3];
            default: moesi_selected_state = 3'd4; 
        endcase
    end

    always @(*) begin
        case (way_select)
            4'b0001: victim_moesi_state = moesi_current_state[0];
            4'b0010: victim_moesi_state = moesi_current_state[1];
            4'b0100: victim_moesi_state = moesi_current_state[2];
            4'b1000: victim_moesi_state = moesi_current_state[3];
            default: victim_moesi_state = 3'd4; 
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

    // DATA OUTPUT MUX - Word Select
    always @(*) begin
        case(cpu_way_hit)
            4'b0001: word_select = data_read[0][s2_word_off * DATA_W +: DATA_W];
            4'b0010: word_select = data_read[1][s2_word_off * DATA_W +: DATA_W];
            4'b0100: word_select = data_read[2][s2_word_off * DATA_W +: DATA_W];
            4'b1000: word_select = data_read[3][s2_word_off * DATA_W +: DATA_W];
            default: word_select = 32'd0;
        endcase
    end 

    // DATA OUTPUT MUX - data_rdata (Size/Byte selection)
    // always @(*) begin
    //     if (sc_done) begin
    //         data_rdata = {31'd0, o_sc_success};
    //     end 
    //     else if (raw_en) begin
    //         data_rdata = raw_rdata;
    //     end 
    //     else begin
    //         case(s2_size)
    //             2'b00: data_rdata = word_select; // Word
    //             2'b01: begin // Byte
    //                 case(s2_byte_off)
    //                     2'b00: data_rdata = {24'd0, word_select[7:0]};
    //                     2'b01: data_rdata = {24'd0, word_select[15:8]};
    //                     2'b10: data_rdata = {24'd0, word_select[23:16]};
    //                     2'b11: data_rdata = {24'd0, word_select[31:24]};
    //                 endcase
    //             end 
    //             2'b10: begin // Half
    //                 case(s2_byte_off[1])
    //                     1'b0: data_rdata = {16'd0, word_select[15:0]};
    //                     1'b1: data_rdata = {16'd0, word_select[31:16]};
    //                 endcase
    //             end
    //             default: data_rdata = word_select;
    //         endcase
    //     end
    // end
    always @(*) begin
        case ({sc_done, raw_en})
            2'b10, 2'b11:   data_rdata  = {31'd0, o_sc_success}; 
            2'b01:          data_rdata  = raw_rdata;
            2'b00:          data_rdata  = word_select;
            default:        data_rdata  = word_select;
        endcase
    end

    // Mux o_snp_resp_data Data (Snoop Response Data)
    always @(*) begin
        case(snoop_way_hit)
            4'b0001: o_snp_resp_data = data_read[0];
            4'b0010: o_snp_resp_data = data_read[1];
            4'b0100: o_snp_resp_data = data_read[2];
            4'b1000: o_snp_resp_data = data_read[3];
            default: o_snp_resp_data = {LINE_W{1'b0}};
        endcase
    end

    // ================================================================
    // 6) MODULE INSTANTIATIONS
    // ================================================================

    // ---- STAGE 1: ACCESS ----
    access #(
        .ADDR_W     (ADDR_W)
    ,   .DATA_W     (DATA_W)
    ,   .NUM_SETS   (NUM_SETS)
    ,   .WORD_OFF_W (WORD_OFF_W)
    ,   .BYTE_OFF_W (BYTE_OFF_W)
    ) access_inst (
        .cpu_addr       (s1_mux_addr)

    ,   .cpu_tag        (s1_tag)     
    ,   .cpu_index      (s1_index)
    ,   .cpu_word_off   (s1_word_off)
    ,   .cpu_byte_off   (s1_byte_off)
    );

    // ---- SRAM ARRAYS ----
    // --- Tag RAMs ---
    genvar i;
    generate
        for (i = 0; i < NUM_WAYS; i = i + 1) begin : tag_rams
            tag_mem #( 
                .NUM_SETS(NUM_SETS)
            ,   .TAG_W(TAG_W) 
            ) u_tag_mem (
                .clk                    (clk)
            ,   .rst_n                  (rst_n)

            ,   .tag_we                 (tag_we & way_select[i])
            ,   .moesi_we               (moesi_we & choosen_way[i])
            // ,   .read_index             (s1_index)
            ,   .read_index             (mem_read_index)
            ,   .write_index            (index_select)
            ,   .din_tag                (s2_tag)
            ,   .dout_tag               (tag_read[i])
            ,   .moesi_next_state       (moesi_next_state)
            ,   .moesi_current_state    (moesi_current_state[i])

            // not use
            ,   .valid_we               ()
            ,   .valid                  ()
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
            // ,   .rst_n          (rst_n)
            // ,   .read_index     (s1_index)
            ,   .read_index     (mem_read_index)
            ,   .dout           (data_read[i])
                
                // Ghi nguyen dong cache
            ,   .refill_we      (refill_we & way_select[i])
            ,   .write_index    (index_select)
            ,   .refill_din     (refill_buffer)
                
            ,   .cpu_we         (data_we & cpu_way_hit[i])
            ,   .cpu_din        (s2_atomic_amo ? amo_alu_result : s2_wdata) // chua xu ly amo swap
            ,   .cpu_wstrb      (4'b1111)
            ,   .cpu_offset     (s2_word_off)
            );
        end
    endgenerate


    // ---- PIPELINE REGISTER (acc_cmp) ----
    acc_cmp #(
        .ADDR_W     (ADDR_W)
    ,   .DATA_W     (DATA_W)
    ,   .NUM_SETS   (NUM_SETS)
    ) acc_cmp_inst (
        .clk        (clk)
    ,   .rst_n      (rst_n)
    ,   .stall      (pipeline_stall)

        // Stage 1 Inputs (Mapped from L1 interface)
    ,   .s1_req         (cpu_req & ~cpu_flush)
    ,   .s1_we          (cpu_we  & ~cpu_flush)
    ,   .s1_size        (cpu_size)
    ,   .s1_wdata       (cpu_din)
    ,   .s1_tag         (s1_tag)    
    ,   .s1_index       (s1_index)
    ,   .s1_word_off    (s1_word_off)
    ,   .s1_byte_off    (s1_byte_off)

    // ,   .snoop_stall    (reg_snoop_stall)   // chua co logic nay, tạm để 0
    ,   .s1_is_snoop    (valid_snoop_req)
    ,   .s1_cmd         (i_snp_req_cmd)

        // Inputs Atomic
    ,   .s1_lr          (cpu_lr & ~cpu_flush)
    ,   .s1_sc          (cpu_sc & ~cpu_flush)
    ,   .s1_amo         (cpu_amo & ~cpu_flush)
    ,   .s1_amo_op      (cpu_amo_op)

        // Stage 2 Outputs
    ,   .s2_req         (s2_req)
    ,   .s2_we          (s2_we)
    ,   .s2_cmd         (s2_cmd)
    ,   .s2_size        (s2_size)
    ,   .s2_wdata       (s2_wdata)
    ,   .s2_tag         (s2_tag)
    ,   .s2_index       (s2_index)
    ,   .s2_word_off    (s2_word_off)
    ,   .s2_byte_off    (s2_byte_off)

    ,   .s2_is_snoop    (s2_is_snoop)
    ,   .s2_snoop_tag   (s2_snoop_tag)
    ,   .s2_snoop_index (s2_snoop_index)
    ,   .s2_snoop_word_off (s2_snoop_word_off)
    ,   .s2_snoop_byte_off (s2_snoop_byte_off)

        // Outputs Atomic
    ,   .s2_lr          (s2_atomic_lr)
    ,   .s2_sc          (s2_atomic_sc)
    ,   .s2_amo         (s2_atomic_amo)
    ,   .s2_amo_op      (s2_amo_op)
    );

    // ---- REPLACEMENT POLICY ----

    cache_replacement #( 
        .N_WAYS     (NUM_WAYS)
    ,   .N_LINES    (NUM_SETS) 
    ) u_replacement (
        .clk        (clk)
    ,   .rst_n      (rst_n)
    ,   .we         (cpu_any_hit | snoop_any_hit)
    ,   .way_hit    (active_way_hit)
    ,   .read_addr  (s1_index)
    ,   .write_addr (s2_index)
    ,   .way_select (way_select)
    );

    // ---- MAIN L1 CONTROLLER ----
    dcache_controller #(
        .WORD_OFF_W (WORD_OFF_W)
    ,   .BYTE_OFF_W (BYTE_OFF_W)
    ) u_controller (
        .clk        (clk)
    ,   .rst_n      (rst_n)

        // CPU Inputs
    ,   .cpu_req                (s2_req & ~s2_is_snoop)
    ,   .cpu_we                 (s2_we)
    ,   .cpu_addr               (s2_full_addr)
        
        // Atomics
    ,   .i_atomic_lr            (s2_atomic_lr)
    ,   .i_atomic_sc            (s2_atomic_sc)
    ,   .i_atomic_amo           (s2_atomic_amo)
    ,   .o_sc_success           (o_sc_success)
    ,   .sc_done                (sc_done)

        // Controller Status Data
    ,   .hit                    (cpu_any_hit)
    ,   .victim_dirty           (victim_dirty)
    ,   .victim_valid           (victim_valid)
    ,   .current_moesi_state    (moesi_selected_state)

        // Snoop interface info
    ,   .i_snoop_invalidate     (snoop_req_invalidate)
    ,   .i_snp_req_valid        (i_snp_req_valid)
    ,   .i_snoop_addr           (i_snp_req_addr[ADDR_W-1:WORD_OFF_W + BYTE_OFF_W])
    ,   .snoop_busy             (snoop_busy)
    ,   .o_resp_ready           (o_resp_ready)
        
        // Data Path Control Outputs
    ,   .tag_we                 (tag_we)
    ,   .moesi_we               (main_moesi_we)
    ,   .refill_we              (refill_we)
    ,   .data_we                (data_we)
    ,   .stall                  (stall_controller) // Đẩy ra Pipeline
    ,   .o_snoop_ready_ctrl     (ctrl_snoop_ready)

        // Arbiter Interface
    ,   .o_req_valid            (o_req_valid)
    ,   .i_req_ready            (i_req_ready)
    ,   .o_req_cmd              (o_req_cmd)     // Đẩy CMD đi Arbiter
    ,   .o_req_wb               (o_req_wb)          
    ,   .i_resp_valid           (i_resp_valid)
    );

    // ---- MOESI CONTROLLER L1 ----
    moesi_controller u_moesi_ctrl (
        .current_state      (moesi_selected_state)
    ,   .victim_state       (victim_moesi_state)

    ,   .is_shared_response (is_shared_buffer)
    ,   .refill_we          (refill_we)

        // Request từ CPU nội bộ
    ,   .cpu_req_valid      (s2_req & ~s2_is_snoop)
    ,   .cpu_hit            (cpu_hit)
    ,   .cpu_rw             (s2_we | s2_atomic_amo | s2_atomic_sc) // Bao gồm cả lệnh Atomic Write

        // Request từ Snoop Bus
    ,   .snoop_valid            (s2_is_snoop)
    ,   .snoop_hit              (snoop_any_hit)
    ,   .snoop_req_invalidate   (snoop_req_invalidate)

        // Outputs Cập nhật FSM
    ,   .victim_dirty       (victim_dirty)
    ,   .victim_valid       (victim_valid)
    // ,   .is_unique          (is_unique)
    // ,   .is_owner           (is_owner)
    
    ,   .next_state         (moesi_next_state)
    );

    // Snoop controller
    snoop_controller #(
        .ADDR_W(ADDR_W)
    ) u_snoop_ctrl (
        .i_snp_req_valid        (i_snp_req_valid)
    // ,   .i_snp_req_cmd_1        (i_snp_req_cmd[1])
    ,   .i_snp_req_cmd_1        (s2_cmd[1])
    // ,   .i_snp_req_addr         (i_snp_req_addr)
    ,   .i_dcache_ready         (ctrl_snoop_ready)
    ,   .i_snp_resp_valid       (s2_is_snoop)
    ,   .i_snp_resp_hit         (snoop_any_hit)

    ,   .o_snp_req_ready        (o_snp_req_ready)
    ,   .snoop_req_invalidate   (snoop_req_invalidate)
    ,   .o_snp_resp_valid       (o_snp_resp_valid)
    ,   .snoop_moesi_we         (snoop_moesi_we)
    );  

    // ---- AMO ALU ----
    amo_alu #(
        .DATA_WIDTH (DATA_W)
    ) u_amo_alu (
        .i_data_from_mem    (word_select)
    ,   .i_data_from_core   (s2_wdata)
    ,   .i_amo_op           (s2_amo_op)
    ,   .o_amo_alu_result   (amo_alu_result) 
    );

endmodule