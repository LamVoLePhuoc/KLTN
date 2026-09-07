`timescale 1ns/1ps
`include "define.vh"

module cache_L2_controller #(
    parameter ADDR_W        = `ADDR_W
,   parameter DATA_W        = `DATA_W
,   parameter STRB_W        = DATA_W/8

,   parameter WORD_OFF_W    = `WORD_OFF_W
,   parameter LINE_W        = (1 << WORD_OFF_W) * DATA_W // Cache line width in bits

)(
    input                           clk
,   input                           rst_n

    // ==========================================
    // UPSTREAM: Giao tiếp với Main L2 Arbiter
    // ==========================================
,   input                           s2_req_valid
,   output  reg                     o_l1_req_ready
,   input                           i_l1_req_rw     
,   output  reg                     o_l1_resp_valid

    // ==========================================
    // Giao tiếp với SRAM (Tag & Data) trong Datapath
    // ==========================================
,   input                           hit
,   input                           is_valid
,   input                           victim_dirty
    
,   output  reg                     tag_we
,   output  reg                     refill_we
,   output  reg                     refill_src    
,   output  reg                     stall
    
    // ==========================================
    // DOWNSTREAM: Giao tiếp AXI Master
    // ==========================================
    // AW Channel
,   input                           iAWREADY
,   output  reg                     oAWVALID
,   output      [7:0]               oAWLEN
,   output      [2:0]               oAWSIZE
,   output      [1:0]               oAWBURST

    // W channel
,   input                           iWREADY
,   output  reg                     oWVALID
,   output  wire                    oWLAST
,   output  reg [STRB_W-1:0]        oWSTRB
,   output  reg [WORD_OFF_W-1:0]    burst_cnt 
      
    // B channel
,   input                           iBVALID
,   input       [1:0]               iBRESP      // hien tai chua dung
,   output  reg                     oBREADY

    // AR channel
,   input                           iARREADY
,   output      [7:0]               oARLEN
,   output      [2:0]               oARSIZE
,   output      [1:0]               oARBURST
,   output  reg                     oARVALID

    // R channel
,   input       [1:0]               iRRESP
,   input                           iRVALID
,   input                           iRLAST
,   output  reg                     oRREADY
);

    // ================================================================
    // AXI CONSTANT ASSIGNMENTS
    // ================================================================
    assign oAWLEN       = (1 << WORD_OFF_W) - 1; 
    assign oAWSIZE      = `oAWSIZE;
    assign oAWBURST     = `oAWBURST;
    assign oARLEN       = (1 << WORD_OFF_W) - 1;
    assign oARSIZE      = `oARSIZE;
    assign oARBURST     = `oARBURST;

    // ================================================================
    // FSM STATES
    // ================================================================
    localparam TAG_CHECK    = 4'd0;
    localparam AW_REQ       = 4'd1;  
    localparam W_DATA       = 4'd2;  
    localparam B_WAIT       = 4'd3;  
    localparam AR_REQ       = 4'd4;  
    localparam R_WAIT       = 4'd5;  
    localparam UPDATE_WM    = 4'd6;  
    localparam REFILL_EXEC  = 4'd7;  // State ghi dữ liệu từ Buffer -> SRAM
    localparam WAIT_RAM     = 4'd8;

    reg [3:0] state, next_state;

    // ================================================================
    // BURST COUNTER LOGIC
    // ================================================================
    assign oWLAST = (burst_cnt == {WORD_OFF_W{1'b1}});
    
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            burst_cnt <= {WORD_OFF_W{1'b0}};
        end else begin
            if (state == W_DATA && iWREADY && oWVALID) begin
                if (oWLAST) 
                    burst_cnt <= {WORD_OFF_W{1'b0}};
                else        
                    burst_cnt <= burst_cnt + 1'b1;
            end
            else if (state == R_WAIT && iRVALID && oRREADY) begin   // TODO: xu ly lai logic RRESP 
                if (iRLAST) 
                    burst_cnt <= {WORD_OFF_W{1'b0}};
                else        
                    burst_cnt <= burst_cnt + 1'b1;
            end
            else if (state == TAG_CHECK) begin
                burst_cnt <= {WORD_OFF_W{1'b0}};
            end
        end
    end

    // ================================================================
    // SEQUENTIAL LOGIC FSM
    // ================================================================
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
        next_state      = state;
        
        o_l1_req_ready  = 1'b0;
        o_l1_resp_valid = 1'b0;
        tag_we          = 1'b0;
        refill_we       = 1'b0;
        refill_src      = 1'b0;
        stall           = 1'b1;
        
        oAWVALID        = 1'b0;
        oWVALID         = 1'b0;
        oWSTRB          = {STRB_W{1'b0}};
        oBREADY         = 1'b0;
        oARVALID        = 1'b0;
        oRREADY         = 1'b0;

        case (state)
            TAG_CHECK: begin
                if (s2_req_valid) begin
                    if (hit) begin
                        stall           = 1'b0;
                        o_l1_resp_valid = 1'b1;
                        if (i_l1_req_rw == 1'b1) begin
                            // WRITE HIT: Chấp nhận request để nạp data từ L1 vào refill_buffer
                            o_l1_req_ready  = 1'b1;
                            refill_we       = 1'b1;
                        end 
                        else begin
                            // READ HIT: Bypass trả luôn
                            o_l1_req_ready  = 1'b1;
                        end
                    end 
                    else begin
                        // MISS
                        if (is_valid && victim_dirty) begin
                            next_state = AW_REQ;
                        end 
                        // Victim clean / Invalid
                        else begin
                            if (i_l1_req_rw == 1'b1) 
                                next_state = UPDATE_WM;
                            else 
                                next_state = AR_REQ;
                        end
                    end
                end
                else begin
                    stall = 1'b0;
                end
            end

            AW_REQ: begin
                oAWVALID = 1'b1;
                if (iAWREADY) 
                    next_state = W_DATA;
            end

            W_DATA: begin
                oWVALID = 1'b1;
                oWSTRB  = {STRB_W{1'b1}};
                if (iWREADY && oWLAST) 
                    next_state = B_WAIT;
            end

            // B_WAIT: begin
            //     oBREADY = 1'b1;
            //     if (iBVALID && iBRESP == 2'b00) begin
            //         if (i_l1_req_rw == 1'b1) 
            //             next_state = UPDATE_WM;
            //         else                     
            //             next_state = AR_REQ;
            //     end
            // end

            B_WAIT: begin
                oBREADY = 1'b1;
                // BỎ check iBRESP == 2'b00 để tránh treo nếu AXI Slave báo lỗi
                if (iBVALID) begin 
                    if (i_l1_req_rw == 1'b1) 
                        next_state = UPDATE_WM;
                    else                     
                        next_state = AR_REQ;
                end
            end

            AR_REQ: begin
                oARVALID = 1'b1;
                if (iARREADY) begin
                    // Báo Ready để gỡ Arbiter khỏi state chờ. `refill_buffer` sẽ hứng rác từ L1 
                    // nhưng không sao vì state R_WAIT phía sau sẽ đè lên bằng data đúng từ Mem.
                    o_l1_req_ready  = 1'b1; 
                    next_state      = R_WAIT;
                end
            end

            // R_WAIT: begin
            //     oRREADY = 1'b1;
            //     if (iRVALID && iRLAST && iRRESP == 2'b00) begin // TODO: chua xu ly dung vi moi transfer la RRESP khac nhau
            //         // Đã hứng trọn gói burst cuối cùng vào buffer
            //         next_state = REFILL_EXEC;
            //     end
            // end
            R_WAIT: begin
                oRREADY = 1'b1;
                // BỎ check iRRESP == 2'b00. Chỉ cần đợi gói cuối cùng (RLAST)
                if (iRVALID && iRLAST) begin 
                    // Đã hứng trọn gói burst cuối cùng vào buffer
                    next_state = REFILL_EXEC;
                end
            end

            UPDATE_WM: begin
                // WRITE MISS: Bật Ready để refill_buffer hứng gói dữ liệu Writeback từ L1
                o_l1_req_ready  = 1'b1;
                next_state      = REFILL_EXEC;
            end

            REFILL_EXEC: begin
                // LÚC NÀY `refill_buffer` ĐÃ CÓ ĐỦ DỮ LIỆU TỪ MEM (HOẶC TỪ L1).
                // Bây giờ mới kích hoạt tín hiệu ghi vào SRAM.
                tag_we          = 1'b1;
                refill_we       = 1'b1;
                refill_src      = i_l1_req_rw; 
                next_state      = WAIT_RAM;
            end

            WAIT_RAM: begin
                // Chờ SRAM hoàn thành việc ghi dữ liệu mới vào cache line (có thể cần vài chu kỳ)
                // Trong thời gian này, không chấp nhận request mới từ L1 và không trả response về L1 
                next_state = TAG_CHECK;
            end

            default: next_state = TAG_CHECK;
        endcase
    end
endmodule