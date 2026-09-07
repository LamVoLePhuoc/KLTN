`timescale 1ns/1ps
// from Lee Min Hunz with luv

module d_coherence #(
    parameter ADDR_W = 32
,   parameter LINE_W = 128
)(
    input   clk
,   input   rst_n

    // ==========================================
    // D-CACHE 0 INTERFACE
    // ==========================================
,   output  reg                 o_dc0_req_ready
,   input                       i_dc0_req_valid
,   input   [ADDR_W-1:0]        i_dc0_req_addr
,   input   [1:0]               i_dc0_req_cmd    // 00:Read, 01:WB, 10:Upgrade, 11:ReadUnique
,   input   [LINE_W-1:0]        i_dc0_req_data
    
,   output  reg                 o_dc0_resp_valid
,   input                       i_dc0_resp_ready
,   output  reg [LINE_W-1:0]    o_dc0_resp_data

    // D-Cache 0 Snoop Bus
,   input                       i_dc0_snp_req_ready
,   output  reg                 o_dc0_snp_req_valid
,   output  reg [ADDR_W-1:0]    o_dc0_snp_req_addr
,   output      [1:0]           o_dc0_snp_req_cmd
,   output  reg                 o_dc0_resp_is_shared 
// ,   output  reg                 o_dc0_resp_is_dirty  

,   input                       i_dc0_snp_resp_valid
,   input                       i_dc0_snp_resp_hit
,   input   [LINE_W-1:0]        i_dc0_snp_resp_data

    // ==========================================
    // D-CACHE 1 INTERFACE
    // ==========================================
,   output  reg                 o_dc1_req_ready
,   input                       i_dc1_req_valid
,   input   [ADDR_W-1:0]        i_dc1_req_addr
,   input   [1:0]               i_dc1_req_cmd    
,   input   [LINE_W-1:0]        i_dc1_req_data

,   input                       i_dc1_resp_ready
,   output  reg                 o_dc1_resp_valid
,   output  reg [LINE_W-1:0]    o_dc1_resp_data

    // D-Cache 1 Snoop Bus
,   input                       i_dc1_snp_req_ready
,   output  reg                 o_dc1_snp_req_valid
,   output  reg [ADDR_W-1:0]    o_dc1_snp_req_addr
,   output      [1:0]           o_dc1_snp_req_cmd
,   output  reg                 o_dc1_resp_is_shared 
// ,   output  reg                 o_dc1_resp_is_dirty  

,   input                       i_dc1_snp_resp_valid
,   input                       i_dc1_snp_resp_hit
,   input   [LINE_W-1:0]        i_dc1_snp_resp_data

    // ==========================================
    // DOWNSTREAM TO MAIN L2 ARBITER
    // ==========================================
,   input                       i_l2_d_req_ready
,   output  reg                 o_l2_d_req_valid
,   output  reg [ADDR_W-1:0]    o_l2_d_req_addr
,   output  reg                 o_l2_d_req_rw      // 0: Read, 1: Write
,   output  reg [LINE_W-1:0]    o_l2_d_req_wdata

,   input                       i_l2_d_resp_valid
,   input   [LINE_W-1:0]        i_l2_d_resp_rdata
,   output  reg                 o_l2_d_resp_ready
);

    // ================================================================
    // PARAMETERS & REGISTERS
    // ================================================================
    localparam CMD_READ_SHARED = 2'b00, CMD_WRITE_BACK = 2'b01;
    localparam CMD_UPGRADE     = 2'b10, CMD_READ_UNIQUE = 2'b11;

    localparam IDLE         = 3'd0;
    localparam SNOOP_ISSUE  = 3'd1;
    localparam SNOOP_WAIT   = 3'd2;
    localparam L2_REQ       = 3'd3;
    localparam L2_WAIT      = 3'd4;
    localparam RESP_FWD     = 3'd5;

    reg         last_grant, current_grant; // 0: Core 0, 1: Core 1
    reg [2:0]   state, next_state;
    
    // Buffers to latch current request
    reg [LINE_W-1:0]    req_data_buf;
    reg [ADDR_W-1:0]    req_addr_buf;
    reg [1:0]           req_cmd_buf;

    // Cache-to-Cache flags
    reg [LINE_W-1:0]    c2c_data_buf;
    reg                 c2c_hit_buf;

    // ================================================================
    // SEQUENTIAL LOGIC & ARBITRATION
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state           <= IDLE;
            last_grant      <= 1'b1;

            // buffers
            c2c_hit_buf     <= 1'b0;
            c2c_data_buf    <= {LINE_W{1'b0}};

            req_data_buf    <= {LINE_W{1'b0}};
            req_addr_buf    <= {ADDR_W{1'b0}};
            req_cmd_buf     <= 2'b00;

        end 
        else begin
            state <= next_state;
            
            if (state == IDLE && next_state != IDLE) begin
                last_grant      <= current_grant;
                
                // Latch request info
                req_addr_buf    <= (current_grant == 1'b0) ? i_dc0_req_addr : i_dc1_req_addr;
                req_cmd_buf     <= (current_grant == 1'b0) ? i_dc0_req_cmd  : i_dc1_req_cmd;
                req_data_buf    <= (current_grant == 1'b0) ? i_dc0_req_data : i_dc1_req_data;
                c2c_hit_buf     <= 1'b0; // Reset flag
            end

            // Capture Snoop Data
            if (state == SNOOP_WAIT) begin
                if (current_grant == 1'b0 && i_dc1_snp_resp_valid && i_dc1_snp_resp_hit) begin
                    c2c_hit_buf     <= 1'b1;
                    c2c_data_buf    <= i_dc1_snp_resp_data;
                end 
                else if (current_grant == 1'b1 && i_dc0_snp_resp_valid && i_dc0_snp_resp_hit) begin
                    c2c_hit_buf     <= 1'b1;
                    c2c_data_buf    <= i_dc0_snp_resp_data;
                end
            end
        end
    end

    // Round-Robin Arbitration
    always @(*) begin
        current_grant = last_grant;
        if (state == IDLE) begin
            case ({i_dc1_req_valid, i_dc0_req_valid})
                2'b01: current_grant    = 1'b0;
                2'b10: current_grant    = 1'b1;
                2'b11: current_grant    = ~last_grant;
                default: current_grant  = last_grant;
            endcase
        end
    end

    // ================================================================
    // FSM NEXT STATE & OUTPUT LOGIC
    // ================================================================
    assign o_dc0_snp_req_cmd = req_cmd_buf; 
    assign o_dc1_snp_req_cmd = req_cmd_buf;
    always @(*) begin
        next_state = state;
        
        // Default Outputs (Zeroing everything to avoid latches)
        o_dc0_resp_data         = {LINE_W{1'b0}}; 
        o_dc1_resp_data         = {LINE_W{1'b0}};
        o_dc0_req_ready         = 1'b0; 
        o_dc1_req_ready         = 1'b0;
        o_dc0_resp_valid        = 1'b0; 
        o_dc1_resp_valid        = 1'b0;
        o_dc0_resp_is_shared    = 1'b0; 
        o_dc1_resp_is_shared    = 1'b0;
        // o_dc0_resp_is_dirty     = 1'b0;  
        // o_dc1_resp_is_dirty     = 1'b0;

        // Snoop Outputs
        o_dc0_snp_req_valid     = 1'b0; 
        o_dc1_snp_req_valid     = 1'b0;
        o_dc0_snp_req_addr      = req_addr_buf; 
        o_dc1_snp_req_addr      = req_addr_buf;
        // o_dc0_snp_req_cmd       = req_cmd_buf; 
        // o_dc1_snp_req_cmd       = req_cmd_buf;

        // L2 Outputs
        o_l2_d_req_valid        = 1'b0;
        o_l2_d_req_addr         = req_addr_buf;
        o_l2_d_req_rw           = 1'b0;
        o_l2_d_req_wdata        = req_data_buf;
        o_l2_d_resp_ready       = 1'b0;

        case (state)
            IDLE: begin
                if (i_dc0_req_valid || i_dc1_req_valid) begin
                    // Accept request
                    if (current_grant == 1'b0) 
                        o_dc0_req_ready = 1'b1;
                    else                       
                        o_dc1_req_ready = 1'b1;
                    
                    // Nếu là WriteBack -> Không cần snoop, đi thẳng xuống L2
                    if ((current_grant == 1'b0 && i_dc0_req_cmd == CMD_WRITE_BACK) || 
                        (current_grant == 1'b1 && i_dc1_req_cmd == CMD_WRITE_BACK)) begin
                        next_state = L2_REQ;
                    end 
                    else begin
                        next_state = SNOOP_ISSUE; // Các lệnh Read/Upgrade cần Snoop
                    end
                end
            end

            SNOOP_ISSUE: begin
                // Bắn snoop sang Core đối diện
                if (last_grant == 1'b0) begin
                    o_dc1_snp_req_valid = 1'b1;
                    if (i_dc1_snp_req_ready) 
                        next_state = SNOOP_WAIT;
                end 
                else begin
                    o_dc0_snp_req_valid = 1'b1;
                    if (i_dc0_snp_req_ready) 
                        next_state = SNOOP_WAIT;
                end
            end

            SNOOP_WAIT: begin
                // Đợi Core đối diện trả lời Snoop
                if (last_grant == 1'b0 && i_dc1_snp_resp_valid) begin
                    if (i_dc1_snp_resp_hit && req_cmd_buf != CMD_UPGRADE) 
                        next_state = RESP_FWD; // Cache-to-Cache Hit!
                    else 
                        next_state = L2_REQ;   // Miss hoặc là lệnh Upgrade
                end 
                else if (last_grant == 1'b1 && i_dc0_snp_resp_valid) begin
                    if (i_dc0_snp_resp_hit && req_cmd_buf != CMD_UPGRADE) 
                        next_state = RESP_FWD; 
                    else 
                        next_state = L2_REQ;
                end
            end

            L2_REQ: begin
                o_l2_d_req_valid    = 1'b1;
                o_l2_d_req_rw       = (req_cmd_buf == CMD_WRITE_BACK); // 1 = Write L2

                // if (i_l2_d_req_ready) begin
                //     if (req_cmd_buf == CMD_WRITE_BACK || req_cmd_buf == CMD_UPGRADE)
                //         next_state  = RESP_FWD; // Ghi/Upgrade xong không cần đợi RDATA
                //     else
                //         next_state  = L2_WAIT;
                // end
                if (i_l2_d_req_ready) begin
                    // BẮT BUỘC MỌI LỆNH (Read/WriteBack/Upgrade) ĐỀU PHẢI ĐỢI L2
                    // Để hoàn thành Handshake (Valid/Ready) và giải phóng main_arbiter
                    next_state  = L2_WAIT;
                end
            end

            L2_WAIT: begin
                o_l2_d_resp_ready = 1'b1;
                if (i_l2_d_resp_valid) begin
                    next_state = RESP_FWD;
                end
            end

            RESP_FWD: begin
                // Trả Data & Cờ MOESI về cho Core yêu cầu
                if (last_grant == 1'b0) begin
                    o_dc0_resp_valid        = 1'b1;
                    o_dc0_resp_is_shared    = c2c_hit_buf; // Nếu hit từ Core 1 -> Chuyển sang S/O
                    // o_dc0_resp_is_dirty     = 1'b0;        // Setup tùy policy MOESI

                    if (c2c_hit_buf) 
                        o_dc0_resp_data     = c2c_data_buf;
                    else             
                        o_dc0_resp_data     = i_l2_d_resp_rdata;

                    if (i_dc0_resp_ready) 
                        next_state          = IDLE;
                end 
                else begin
                    o_dc1_resp_valid        = 1'b1;
                    o_dc1_resp_is_shared    = c2c_hit_buf;
                    // o_dc1_resp_is_dirty     = 1'b0;

                    if (c2c_hit_buf) 
                        o_dc1_resp_data     = c2c_data_buf;
                    else             
                        o_dc1_resp_data     = i_l2_d_resp_rdata;

                    if (i_dc1_resp_ready) 
                        next_state          = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

endmodule