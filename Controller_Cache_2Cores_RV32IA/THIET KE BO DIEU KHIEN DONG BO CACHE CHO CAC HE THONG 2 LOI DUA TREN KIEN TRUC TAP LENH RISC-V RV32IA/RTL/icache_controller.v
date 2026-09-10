`timescale 1ns/1ps
// from Lee Min Hunz with luv
// ============================================================================
// ICache Controller - Instruction Cache FSM
// ============================================================================
//
// Controls L1 instruction cache operations. Read-only cache with
// simple refill logic (no writeback needed).
//
// State Descriptions:
//   TAG_CHECK  : Compare tag, check hit/miss
//   ALLOC_REQ  : Send refill request to L2
//   ALLOC_WAIT : Wait for L2 data response
//   UPDATE     : Write refill data to cache RAM
//   WAIT_RAM   : Wait one cycle for SRAM write to complete
//
// ============================================================================
module icache_controller #(
    parameter DATA_W    = 32
,   parameter ADDR_W    = 32
)(
    input               clk, rst_n
// ,   input               flush
    // Cache <-> CPU
,   input               cpu_req
,   input               hit               

,   output  reg         tag_we 
,   output  reg         refill_we
,   output  reg         stall
,   output  reg         read_index_src
   
    // request L1 -> L2 
,   input           i_mem_req_ready // L2 san sang nhan
,   output  reg     o_mem_req_valid // Bao co request

    // read data L2 -> L1
,   input           i_mem_rdata_valid
    // input           i_mem_rdata_last,
,   output  reg     o_mem_rdata_ready
);

    // ================================================================
    // LOCAL PARAMETERS - FSM State Encoding
    // ================================================================
    localparam TAG_CHECK    = 4'd0;   // Check tag for hit/miss
    localparam ALLOC_REQ    = 4'd1;   // Send refill request to L2
    localparam ALLOC_WAIT   = 4'd2;   // Wait for L2 data
    localparam UPDATE       = 4'd3;   // Write data to cache
    localparam WAIT_RAM     = 4'd4;   // Wait one cycle for SRAM write

    // ================================================================
    // REG DECLARATIONS
    // ================================================================
    reg [3:0] state, next_state;

    // ================================================================
    // STATE REGISTER
    // ================================================================

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            state <= TAG_CHECK;
        end 
        else begin       
            state <= next_state;
        end
    end

    // ================================================================
    // NEXT STATE & OUTPUT LOGIC
    // ================================================================
    // always @(*) begin
    //     // 1. Default assignments to prevent latches
    //     next_state        = state;
    //     o_mem_req_valid   = 1'b0;
    //     o_mem_rdata_ready = 1'b0;
    //     tag_we            = 1'b0;
    //     stall             = 1'b0;
    //     refill_we         = 1'b0;
    //     read_index_src    = 1'b0;     // 0=S2 index, 1=S1 index

    //     // 2. State-specific logic
    //     case(state)
    //         TAG_CHECK: begin
    //             if (flush) begin
    //                 next_state = TAG_CHECK; // <--- CÓ FLUSH THÌ HỦY MISS, CHỜ LỆNH MỚI
    //             end
    //             // On miss, initiate refill from L2
    //             else if (cpu_req) begin
    //                 if (hit) begin
    //                     next_state = TAG_CHECK;     // Hit: serve immediately
    //                 end 
    //                 else begin
    //                     next_state = ALLOC_REQ;     // Miss: fetch from L2
    //                 end
    //             end
    //         end

    //         ALLOC_REQ: begin
    //             if (flush) begin
    //                 next_state      = TAG_CHECK; // <--- HỦY REQUEST NẾU L2 CHƯA KỊP NHẬN
    //                 o_mem_req_valid = 1'b0;
    //             end 
    //             else begin
    //                 o_mem_req_valid = 1'b1;
    //                 if (i_mem_req_ready) begin
    //                     next_state = ALLOC_WAIT;
    //                 end 
    //             end
    //         end
            
    //         ALLOC_WAIT: begin
    //             o_mem_req_valid   = 1'b1;           // Output: Keep request active
    //             o_mem_rdata_ready = 1'b1;           // Output: Ready to receive data
                
    //             if (i_mem_rdata_valid) begin
    //                 next_state = UPDATE;            // Next State
    //             end
    //         end

    //         UPDATE: begin
    //             tag_we     = 1'b1;                  // Output: Write new tag
    //             refill_we  = 1'b1;                  // Output: Write refill data to RAM
                
    //             next_state = WAIT_RAM;              // Next State
    //         end

    //         WAIT_RAM: begin
    //             stall          = 1'b1;              // Output: Hold pipeline
    //             read_index_src = 1'b1;              // Output: Use S1 index for next lookup
                
    //             next_state     = TAG_CHECK;         // Next State
    //         end 

    //         default: begin
    //             next_state = TAG_CHECK;
    //         end
    //     endcase
    // end
    always @(*) begin
        next_state        = state;
        o_mem_req_valid   = 1'b0;
        o_mem_rdata_ready = 1'b0;
        tag_we            = 1'b0;
        refill_we         = 1'b0;
        read_index_src    = 1'b0; // 0=S2 index, 1=S1 index
        stall             = 1'b1;

        // 2. State-specific logic
        case(state)
            // TAG_CHECK: begin
            //     if (flush) begin
            //         stall = 1'b0; // Có flush thì nhả stall để pipeline xả rác
            //         next_state = TAG_CHECK;
            //     end
            //     else if (!cpu_req) begin
            //         stall = 1'b0; // Không có yêu cầu đọc lệnh -> không cản pipeline
            //     end
            //     else begin // cpu_req == 1
            //         if (hit) begin
            //             stall = 1'b0; // Cache Hit -> nhả stall
            //             next_state = TAG_CHECK;
            //         end 
            //         else begin
            //             // Cache Miss -> stall giữ nguyên 1'b1 (từ default), nhảy state
            //             next_state = ALLOC_REQ;
            //         end
            //     end
            // end

            // ALLOC_REQ: begin
            //     if (flush) begin
            //         next_state      = TAG_CHECK;
            //         o_mem_req_valid = 1'b0;
            //     end 
            //     else begin
            //         o_mem_req_valid = 1'b1;
            //         if (i_mem_req_ready) begin
            //             next_state = ALLOC_WAIT;
            //         end 
            //     end
            // end

            TAG_CHECK: begin
                if (!cpu_req) begin
                    stall           = 1'b0; // Không có yêu cầu đọc lệnh -> không cản pipeline
                end
                else begin // cpu_req == 1
                    if (hit) begin
                        stall       = 1'b0; // Cache Hit -> nhả stall
                        next_state  = TAG_CHECK;
                    end 
                    else begin
                        // Cache Miss -> stall giữ nguyên 1'b1 (từ default), nhảy state
                        next_state  = ALLOC_REQ;
                    end
                end
            end

            ALLOC_REQ: begin
                o_mem_req_valid = 1'b1;
                if (i_mem_req_ready) begin
                    next_state = ALLOC_WAIT;
                end 
            end
            
            ALLOC_WAIT: begin
                o_mem_req_valid     = 1'b1;
                o_mem_rdata_ready   = 1'b1;
                
                if (i_mem_rdata_valid) begin
                    next_state = UPDATE;
                end
            end

            UPDATE: begin
                tag_we      = 1'b1;
                refill_we   = 1'b1;
                
                next_state  = WAIT_RAM;
            end

            WAIT_RAM: begin
                read_index_src  = 1'b1;
                next_state      = TAG_CHECK;
            end 

            default: begin
                next_state = TAG_CHECK;
            end
        endcase
    end
endmodule