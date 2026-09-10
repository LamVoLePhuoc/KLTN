`timescale 1ns/1ps
// from Lee Min Hunz with luv
// L1 Data Cache Controller with MOESI Coherence & Atomic Support
module dcache_controller #(
    parameter DATA_W        = 32
,   parameter ADDR_W        = 32
,   parameter STRB_W        = (DATA_W/8)
,   parameter WORD_OFF_W    = 4
,   parameter BYTE_OFF_W    = 2
)(
    input           clk, rst_n

    // Cache <-> CPU
,   input                   cpu_req
,   input                   cpu_we
,   input   [ADDR_W - 1:0]  cpu_addr 

    // Atomic Interface
,   input                   i_atomic_lr      // Load-Reserved
,   input                   i_atomic_sc      // Store-Conditional  
,   input                   i_atomic_amo     // AMO operation
,   output                  o_sc_success     // SC result (0=success, 1=fail)
,   output  reg             sc_done

    // Cache Control Status Inputs
,   input           hit           
,   input           victim_dirty  
,   input           victim_valid      
,   input   [2:0]   current_moesi_state

    // Snoop invalidation
,   input                                                   i_snoop_invalidate
,   input                                                   i_snp_req_valid
,   input   [ADDR_W - 1 : WORD_OFF_W + BYTE_OFF_W]          i_snoop_addr 
,   input                                                   snoop_busy
,   output  reg                                             o_resp_ready

    // --- Control DataPath Outputs ---
,   output  reg     data_we
,   output  reg     tag_we 
,   output  reg     moesi_we
,   output  reg     refill_we
,   output  reg     stall
,   output  reg     o_snoop_ready_ctrl

    // --- Bus / Arbiter Interface (To Arbiter/Snoop) ---
,   output  reg             o_req_valid
,   input                   i_req_ready
,   output  reg [1:0]       o_req_cmd      // 00: Read, 01: WB, 10: Upgrade, 11: ReadUnique
,   output  reg             o_req_wb       // Báo hiệu đang đẩy victim data
,   input                   i_resp_valid
);

    // FSM States
    localparam TAG_CHECK    = 4'd0;
    localparam WB_SEND      = 4'd1;     // Gửi Writeback Victim dirty
    localparam WB_WAIT      = 4'd2;
    localparam BUS_REQ      = 4'd3;     // Gửi Request Cấp quyền hoặc Đọc RAM/Snoop
    localparam BUS_WAIT     = 4'd4;     // Đợi Bus Arbiter / Snoop Filter trả data
    localparam UPDATE       = 4'd5;
    localparam AMO_EXEC     = 4'd6;     // Cycle thực hiện tính AMO và Ghi Data
    localparam WAIT_RAM     = 4'd7;
    localparam FINISH_REQ   = 4'd8;     // Đảm bảo CPU hoàn tất request sau khi mượn bus, tránh snoop cướp quyền

    // MOESI States
    localparam STATE_M = 3'd0, STATE_O = 3'd1, STATE_E = 3'd2, STATE_S = 3'd3, STATE_I = 3'd4;
    // Bus Commands
    localparam CMD_READ_SHARED = 2'b00, CMD_WRITE_BACK = 2'b01, CMD_UPGRADE = 2'b10, CMD_READ_UNIQUE = 2'b11;

    reg [3:0]   state, next_state;
    reg         res_valid;
    reg [31:0]  res_addr;

    wire is_write = cpu_we || i_atomic_sc || i_atomic_amo;
    wire res_hit  = res_valid && (res_addr == cpu_addr);

    // ================================================================
    // RESERVATION LOGIC (LR / SC)
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            res_valid   <= 1'b0;
            res_addr    <= 32'b0;
        end 
        else begin
            if (i_snoop_invalidate && (i_snoop_addr[31:6] == res_addr[31:6])) begin
                res_valid   <= 1'b0;
            end
            else if (i_atomic_lr && cpu_req && ((state == TAG_CHECK && hit && !snoop_busy) || state == FINISH_REQ)) begin
                res_valid   <= 1'b1;
                res_addr    <= cpu_addr;
            end
            else if (i_atomic_sc && cpu_req && sc_done) begin
                res_valid   <= 1'b0;
            end
        end
    end

    assign o_sc_success = (i_atomic_sc && (!res_valid || !res_hit)) ? 1'b1 : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) 
            state <= TAG_CHECK;
        else 
            state <= next_state;
    end

    // ================================================================
    // NEXT STATE & OUTPUT LOGIC
    // ================================================================
    always @(*) begin
        // Default Outputs
        next_state          = state;
        o_req_cmd           = CMD_READ_SHARED;
        o_req_valid         = 1'b0;
        o_req_wb            = 1'b0;
        data_we             = 1'b0;
        tag_we              = 1'b0;
        moesi_we            = 1'b0;
        refill_we           = 1'b0;
        stall               = 1'b1;
        sc_done             = 1'b0;
        o_resp_ready        = 1'b0;
        o_snoop_ready_ctrl  = 1'b0;

        case (state)
            TAG_CHECK: begin
                o_snoop_ready_ctrl = 1'b1;
                if (snoop_busy) begin
                    stall = 1'b1; // Chờ snoop xử lý xong trước khi đánh giá request
                end
                else if (!cpu_req || (i_atomic_sc && (!res_valid || !res_hit))) begin
                    stall = 1'b0; // Mất yêu cầu hoặc SC fail thì không cản pipeline
                    if (i_atomic_sc && cpu_req) 
                        sc_done = 1'b1;
                end 
                else if (hit) begin
                    // Cache Hit! Check quyền GHI
                    if (is_write) begin
                        if (current_moesi_state == STATE_M || current_moesi_state == STATE_E) begin
                            // Có đủ quyền M/E -> Ghi thỏa mái
                            if (i_atomic_amo) begin // AMO cần qua ALU, nhảy cycle tính toán
                                next_state = AMO_EXEC;
                            end 
                            else begin
                                if (i_atomic_sc && (!res_valid || !res_hit)) begin
                                    // SC Fail -> Không ghi data
                                    stall = 1'b0;
                                end else begin
                                    data_we  = 1'b1;
                                    moesi_we = 1'b1; // Cập nhật sang M (vì E bị ghi sẽ hóa M)
                                    stall    = 1'b0;
                                end
                                if (i_atomic_sc) 
                                    sc_done = 1'b1;
                            end
                        end 
                        else begin
                            // Đang S hoặc O mà đòi write -> Xin Quyền Upgrade
                            next_state = BUS_REQ;
                        end
                    end 
                    else begin
                        // Read Hit (Bao gồm LR)
                        stall = 1'b0;
                    end
                end 
                else begin // CACHE MISS
                    if (victim_valid && victim_dirty) 
                        next_state = WB_SEND;
                    else 
                        next_state = BUS_REQ;
                end
            end

            WB_SEND: begin
                o_req_cmd = CMD_WRITE_BACK;
                if (snoop_busy) begin
                    o_req_valid = 1'b0;
                    o_req_wb    = 1'b0;
                    next_state  = TAG_CHECK; // Abort
                end 
                else begin
                    o_req_valid = 1'b1;
                    o_req_wb    = 1'b1;
                    if (i_req_ready) begin
                        next_state = WB_WAIT; // Sang state mới nếu arbiter accept
                    end
                end
            end

            WB_WAIT: begin
                o_resp_ready    = 1'b1;
                if (i_resp_valid) 
                    next_state  = BUS_REQ;
            end

            BUS_REQ: begin
                if (is_write && hit) 
                    o_req_cmd = CMD_UPGRADE;
                else if (is_write && !hit) 
                    o_req_cmd = CMD_READ_UNIQUE;
                else 
                    o_req_cmd = CMD_READ_SHARED;

                if (snoop_busy) begin
                    // Có snoop ưu tiên cao hơn -> Bỏ dở việc xin bus, lùi về TAG_CHECK
                    o_req_valid = 1'b0;
                    next_state  = TAG_CHECK;
                end 
                else begin
                    o_req_valid = 1'b1;
                    if (i_req_ready) begin
                        next_state = BUS_WAIT;
                    end
                end
            end

            BUS_WAIT: begin
                o_resp_ready = 1'b1;
                if (i_resp_valid) 
                    next_state = UPDATE;
            end

            // UPDATE: begin // Nhận cờ hiệu về, cập nhật SRAM
            //     tag_we    = 1'b1;
            //     moesi_we  = 1'b1;
            //     if (!(is_write && hit)) 
            //         refill_we = 1'b1; // Refill Data khi Miss
                
            //     // Nếu là AMO mà miss -> Vừa lấy đc data về -> qua AMO Ghi đè vào Data
            //     if (i_atomic_amo) 
            //         next_state = AMO_EXEC;
            //     else 
            //         next_state = WAIT_RAM;
            // end

            UPDATE: begin // Nhận cờ hiệu về, cập nhật SRAM
                tag_we    = 1'b1;
                moesi_we  = 1'b1;
                if (!(is_write && hit)) 
                    refill_we = 1'b1; // Refill Data khi Miss
                
                next_state = WAIT_RAM;
            end

            // AMO_EXEC: begin
            //     data_we     = 1'b1;
            //     // moesi_we    = 1'b1; // State M
            //     // stall    = 1'b0;
            //     next_state  = WAIT_RAM;
            // end

            AMO_EXEC: begin
                o_snoop_ready_ctrl = 1'b0; // Chặn snoop để hoàn tất ghi data
                data_we     = 1'b1;
                stall       = 1'b0; 
                next_state  = TAG_CHECK;
            end

            WAIT_RAM: begin
                o_snoop_ready_ctrl = 1'b0; // Chặn snoop
                next_state = FINISH_REQ;
            end
            FINISH_REQ: begin
                o_snoop_ready_ctrl = 1'b0; // Chặn snoop
                
                // Không cần check snoop_busy vì snoop đã bị chặn
                if (is_write) begin
                    if (i_atomic_sc) begin
                        if (res_valid && res_hit) begin
                            data_we = 1'b1;
                        end
                        sc_done = 1'b1;
                    end else begin
                        data_we = 1'b1;
                    end
                end
                stall = 1'b0; // Hoàn tất giao dịch của CPU, unstall pipeline
                next_state = TAG_CHECK;
            end

            default : begin
                next_state = TAG_CHECK;
            end
        endcase
    end
endmodule