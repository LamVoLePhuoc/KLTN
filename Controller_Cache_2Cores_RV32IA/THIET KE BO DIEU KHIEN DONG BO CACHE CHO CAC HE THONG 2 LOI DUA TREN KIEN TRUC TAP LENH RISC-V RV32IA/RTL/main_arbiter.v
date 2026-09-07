`timescale 1ns/1ps

module main_l2_arbiter #(
    parameter ADDR_W = 32
,   parameter LINE_W = 128
)(
    input clk   
,   input rst_n

    // INPUT TỪ I_ARBITER (Luồng Instruction)
,   output  reg             o_l2_i_req_ready
,   input                   i_l2_i_req_valid
,   input   [ADDR_W-1:0]    i_l2_i_req_addr
   
,   input                   i_l2_i_rdata_ready
,   output  reg             o_l2_i_rdata_valid
,   output  [LINE_W-1:0]    o_l2_i_rdata

    // INPUT TỪ D_COHERENCE (Luồng Data)
,   output  reg             o_l2_d_req_ready
,   input                   i_l2_d_req_valid
,   input   [ADDR_W-1:0]    i_l2_d_req_addr
,   input                   i_l2_d_req_rw
,   input   [LINE_W-1:0]    i_l2_d_req_wdata

,   input                   i_l2_d_resp_ready
,   output  reg             o_l2_d_resp_valid
,   output  [LINE_W-1:0]    o_l2_d_resp_rdata

    // OUTPUT XUỐNG SHARED L2 CACHE
,   input                   i_l2_req_ready
,   input                   L2_pipeline_stall
,   output  reg             o_l2_req_valid
,   output  reg [ADDR_W-1:0]o_l2_req_addr
,   output  reg             o_l2_req_rw     
,   output  reg [LINE_W-1:0]o_l2_req_wdata

,   input                   i_l2_resp_valid
,   input   [LINE_W-1:0]    i_l2_resp_rdata
// ,   output  reg             o_l2_resp_ready
);

    // ================================================================
    // FSM STATES TÁCH RỜI
    // ================================================================
    localparam IDLE         = 3'd0;
    localparam SEND_REQ_D   = 3'd1; // Arbiter chờ L2 hết Stall để đẩy Data
    localparam WAIT_RESP_D  = 3'd2; // Chờ L2 trả Response Data
    localparam SEND_REQ_I   = 3'd3; // Arbiter chờ L2 hết Stall để đẩy Inst
    localparam WAIT_RESP_I  = 3'd4; // Chờ L2 trả Response Inst

    reg [2:0] state, next_state;

    // Direct routing data
    assign o_l2_d_resp_rdata = i_l2_resp_rdata;
    assign o_l2_i_rdata      = i_l2_resp_rdata;

    // ================================================================
    // SEQUENTIAL LOGIC & OUTPUT REGISTERS
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state           <= IDLE;
            o_l2_req_valid  <= 1'b0;
            o_l2_req_addr   <= {ADDR_W{1'b0}};
            o_l2_req_rw     <= 1'b0;
            o_l2_req_wdata  <= {LINE_W{1'b0}};
        end 
        else begin
            state <= next_state;

            // Bắt data ngay lập tức khi IDLE
            if (state == IDLE) begin
                if (i_l2_d_req_valid) begin
                    o_l2_req_valid  <= 1'b1;
                    o_l2_req_addr   <= i_l2_d_req_addr;
                    o_l2_req_rw     <= i_l2_d_req_rw;
                    o_l2_req_wdata  <= i_l2_d_req_wdata;
                end 
                else if (i_l2_i_req_valid) begin
                    o_l2_req_valid  <= 1'b1;
                    o_l2_req_addr   <= i_l2_i_req_addr;
                    o_l2_req_rw     <= 1'b0; 
                    o_l2_req_wdata  <= {LINE_W{1'b0}};
                end
            end 
            // Chỉ hạ cờ Valid xuống khi L2 thực sự đã bắt được (không Stall và Ready)
            else if ((state == SEND_REQ_D || state == SEND_REQ_I) && i_l2_req_ready && !L2_pipeline_stall) begin
                o_l2_req_valid  <= 1'b0;
            end
        end
    end

    // ================================================================
    // FSM NEXT STATE & CONTROL LOGIC
    // ================================================================
    always @(*) begin
        next_state          = state;
        o_l2_d_req_ready    = 1'b0;
        o_l2_i_req_ready    = 1'b0;
        o_l2_d_resp_valid   = 1'b0;
        o_l2_i_rdata_valid  = 1'b0;
        // o_l2_resp_ready     = 1'b0;

        case (state)
            IDLE: begin
                // Bật ready=1 ngay lập tức để giải phóng I/D-cache sang state WAIT
                if (i_l2_d_req_valid) begin
                    o_l2_d_req_ready    = 1'b1; 
                    next_state          = SEND_REQ_D;
                end 
                else if (i_l2_i_req_valid) begin
                    o_l2_i_req_ready    = 1'b1;
                    next_state          = SEND_REQ_I;
                end
            end

            SEND_REQ_D: begin
                // Arbiter tự ôm data, đứng chờ L2
                if (i_l2_req_ready && !L2_pipeline_stall) begin
                    next_state = WAIT_RESP_D;
                end
            end

            WAIT_RESP_D: begin
                // o_l2_resp_ready = i_l2_d_resp_ready;
                if (i_l2_resp_valid) begin
                    o_l2_d_resp_valid = 1'b1;
                    if (i_l2_d_resp_ready) 
                        next_state = IDLE;
                end
            end

            SEND_REQ_I: begin
                if (i_l2_req_ready && !L2_pipeline_stall) begin
                    next_state = WAIT_RESP_I;
                end
            end

            WAIT_RESP_I: begin
                // o_l2_resp_ready = i_l2_i_rdata_ready;
                if (i_l2_resp_valid) begin
                    o_l2_i_rdata_valid = 1'b1;
                    if (i_l2_i_rdata_ready) 
                        next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

endmodule