`timescale 1ns/1ps
// from Lee Min Hunz with luv

module i_arbiter #(
    parameter ADDR_W = 32
,   parameter LINE_W = 128
)(
    input clk
,   input rst_n

    // ==========================================
    // I-CACHE 0 INTERFACE
    // ==========================================
,   input                   i_ic0_req_valid
,   output  reg             o_ic0_req_ready
,   input   [ADDR_W-1:0]    i_ic0_req_addr
    
,   input                   i_ic0_rdata_ready
,   output  reg             o_ic0_rdata_valid
,   output  [LINE_W-1:0]    o_ic0_rdata

    // ==========================================
    // I-CACHE 1 INTERFACE
    // ==========================================
,   input                   i_ic1_req_valid
,   output  reg             o_ic1_req_ready
,   input   [ADDR_W-1:0]    i_ic1_req_addr
    
,   input                   i_ic1_rdata_ready
,   output  reg             o_ic1_rdata_valid
,   output  [LINE_W-1:0]    o_ic1_rdata

    // ==========================================
    // DOWNSTREAM INTERFACE (To Main L2 Arbiter)
    // ==========================================
,   output  reg             o_l2_i_req_valid
,   input                   i_l2_i_req_ready
,   output  reg [ADDR_W-1:0]o_l2_i_req_addr
    
,   input                   i_l2_i_rdata_valid
,   output  reg             o_l2_i_rdata_ready
,   input   [LINE_W-1:0]    i_l2_i_rdata
);

    // ================================================================
    // FSM STATES & REGISTERS
    // ================================================================
    localparam IDLE         = 2'd0;
    localparam WAIT_ACCEPT  = 2'd1; // Đợi Main Arbiter chấp nhận Request
    localparam WAIT_RESP    = 2'd2; // Đợi L2 trả Data về

    reg [1:0] state, next_state;
    reg       last_grant;       // 0: Core 0, 1: Core 1 (cho Round-Robin)
    reg       current_grant;    // Ai đang giữ quyền trong transaction hiện tại

    // ================================================================
    // SEQUENTIAL LOGIC
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state       <= IDLE;
            last_grant  <= 1'b1; // Mặc định reset xong ưu tiên Core 0 trước
        end 
        else begin
            state       <= next_state;
            // Cập nhật last_grant khi chuyển từ IDLE sang trạng thái xử lý
            if (state == IDLE && next_state != IDLE) begin
                last_grant  <= current_grant;
            end
        end
    end

    // ================================================================
    // COMBINATIONAL LOGIC: ROUND-ROBIN ARBITRATION
    // ================================================================
    always @(*) begin
        current_grant = last_grant; // Giữ nguyên mặc định
        if (state == IDLE) begin
            case ({i_ic1_req_valid, i_ic0_req_valid})
                2'b01: current_grant    = 1'b0; // Chỉ IC0 xin
                2'b10: current_grant    = 1'b1; // Chỉ IC1 xin
                2'b11: current_grant    = ~last_grant; // Cả hai xin -> Đảo quyền
                default: current_grant  = last_grant;
            endcase
        end
    end

    // ================================================================
    // FSM NEXT STATE & OUTPUT LOGIC
    // ================================================================
    
    // Gán trực tiếp data trả về (ai cần thì lấy, an toàn vì có valid cản lại)
    assign o_ic0_rdata = i_l2_i_rdata;
    assign o_ic1_rdata = i_l2_i_rdata;

    always @(*) begin
        // Default values
        next_state          = state;
        o_ic0_req_ready     = 1'b0;
        o_ic1_req_ready     = 1'b0;
        o_ic0_rdata_valid   = 1'b0;
        o_ic1_rdata_valid   = 1'b0;
        
        o_l2_i_req_valid    = 1'b0;
        o_l2_i_req_addr     = {ADDR_W{1'b0}};
        o_l2_i_rdata_ready  = 1'b0;

        case (state)
            IDLE: begin
                if (i_ic0_req_valid || i_ic1_req_valid) begin
                    o_l2_i_req_valid    = 1'b1;
                    
                    // Route Address dựa trên current_grant
                    if (current_grant == 1'b0) begin
                        o_l2_i_req_addr = i_ic0_req_addr;
                    end 
                    else begin
                        o_l2_i_req_addr = i_ic1_req_addr;
                    end

                    // Nếu tầng dưới (Main Arbiter) rảnh và nhận ngay lập tức
                    if (i_l2_i_req_ready) begin
                        if (current_grant == 1'b0) 
                            o_ic0_req_ready = 1'b1;
                        else                       
                            o_ic1_req_ready = 1'b1;
                        next_state      = WAIT_RESP;
                    end 
                    else begin
                        next_state      = WAIT_ACCEPT;
                    end
                end
            end

            WAIT_ACCEPT: begin
                o_l2_i_req_valid        = 1'b1;
                
                if (current_grant == 1'b0) begin
                    o_l2_i_req_addr     = i_ic0_req_addr;
                    if (i_l2_i_req_ready) begin
                        o_ic0_req_ready = 1'b1;
                        next_state      = WAIT_RESP;
                    end
                end 
                else begin
                    o_l2_i_req_addr     = i_ic1_req_addr;
                    if (i_l2_i_req_ready) begin
                        o_ic1_req_ready = 1'b1;
                        next_state      = WAIT_RESP;
                    end
                end
            end

            WAIT_RESP: begin
                // Cấp quyền cho L2 trả data
                if (current_grant == 1'b0) begin
                    o_l2_i_rdata_ready  = i_ic0_rdata_ready;
                end 
                else begin
                    o_l2_i_rdata_ready  = i_ic1_rdata_ready;
                end

                // Bắt cờ Valid từ L2 và định tuyến về đúng I-Cache
                if (i_l2_i_rdata_valid) begin
                    if (current_grant == 1'b0) begin
                        o_ic0_rdata_valid = 1'b1;
                        if (i_ic0_rdata_ready) 
                            next_state = IDLE;
                    end 
                    else begin
                        o_ic1_rdata_valid = 1'b1;
                        if (i_ic1_rdata_ready) 
                            next_state = IDLE;
                    end
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

endmodule