`timescale 1ns/1ps
// from Lee Min Hunz with luv
// ============================================================================
// Access Compare - Stage 1 to Stage 2 Pipeline Register
// ============================================================================
//
// Registers address decode results from Stage 1 (address decode) to
// Stage 2 (tag compare). Handles stall, flush, and snoop pipelining.
//
// Control Signals:
//   - stall: Hold S2 values (cache miss, hazard)
//   - flush: Clear S2 values (branch mispredict)
//   - snoop_stall: Hold S2 snoop values (snoop in progress)
//
// ============================================================================
module acc_cmp #(
    parameter ADDR_W        = 32,
    parameter DATA_W        = 32,
    parameter NUM_SETS      = 16,
    parameter INDEX_W       = $clog2(NUM_SETS),
    parameter WORD_OFF_W    = 4,  // 16 words/line
    parameter BYTE_OFF_W    = 2,  // 4B/word
    parameter TAG_W         = ADDR_W - INDEX_W - WORD_OFF_W - BYTE_OFF_W
)(
    input                       clk
,   input                       rst_n
,   input                       stall
// ,   input                       flush
,   input                       s1_req
,   input                       s1_we      
,   input   [1:0]               s1_cmd
,   input   [1:0]               s1_size
,   input   [DATA_W-1:0]        s1_wdata
,   input   [TAG_W-1:0]         s1_tag
,   input   [INDEX_W-1:0]       s1_index
,   input   [WORD_OFF_W-1:0]    s1_word_off
,   input   [BYTE_OFF_W-1:0]    s1_byte_off

// ,   input                       snoop_stall
,   input                       s1_is_snoop
// ,   input   [TAG_W-1:0]         s1_snoop_tag
// ,   input   [INDEX_W-1:0]       s1_snoop_index

,   input                       s1_lr
,   input                       s1_sc
,   input                       s1_amo
,   input   [2:0]               s1_amo_op

,   output reg                  s2_req
,   output reg                  s2_we
,   output reg [1:0]            s2_cmd
,   output reg [1:0]            s2_size
,   output reg [DATA_W-1:0]     s2_wdata
,   output reg [TAG_W-1:0]      s2_tag
,   output reg [INDEX_W-1:0]    s2_index
,   output reg [WORD_OFF_W-1:0] s2_word_off
,   output reg [BYTE_OFF_W-1:0] s2_byte_off

,   output reg                      s2_is_snoop
,   output reg [TAG_W-1:0]          s2_snoop_tag
,   output reg [INDEX_W-1:0]        s2_snoop_index
,   output reg [WORD_OFF_W-1:0]     s2_snoop_word_off
,   output reg [BYTE_OFF_W-1:0]     s2_snoop_byte_off

,   output reg                      s2_lr
,   output reg                      s2_sc
,   output reg                      s2_amo
,   output reg [2:0]                s2_amo_op
);
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            s2_req          <= 1'b0;
            s2_we           <= 1'b0;
            s2_size         <= 2'b00;
            s2_cmd          <= 2'b00;
            s2_wdata        <= {DATA_W{1'b0}};
            s2_tag          <= {TAG_W{1'b0}};
            s2_index        <= {INDEX_W{1'b0}};
            s2_word_off     <= {WORD_OFF_W{1'b0}};
            s2_byte_off     <= {BYTE_OFF_W{1'b0}};

            s2_is_snoop     <= 1'b0;
            s2_snoop_tag    <= {TAG_W{1'b0}};
            s2_snoop_index  <= {INDEX_W{1'b0}};
            s2_snoop_word_off <= {WORD_OFF_W{1'b0}};
            s2_snoop_byte_off <= {BYTE_OFF_W{1'b0}};

            s2_lr        <= 1'b0;
            s2_sc        <= 1'b0;
            s2_amo       <= 1'b0;
            s2_amo_op    <= 3'b000;
        end
        else begin
            s2_is_snoop     <= s1_is_snoop;    
            s2_cmd          <= s1_cmd;
            if (s1_is_snoop) begin
                s2_snoop_tag      <= s1_tag;
                s2_snoop_index    <= s1_index;
                s2_snoop_word_off <= s1_word_off;
                s2_snoop_byte_off <= s1_byte_off;
            end
            if (~stall) begin
                s2_req          <= s1_req;
                s2_we           <= s1_we;
                s2_size         <= s1_size;
                
                s2_wdata        <= s1_wdata;
                s2_tag          <= s1_tag;
                s2_index        <= s1_index;
                s2_word_off     <= s1_word_off;
                s2_byte_off     <= s1_byte_off;     

                s2_lr        <= s1_lr;
                s2_sc        <= s1_sc;
                s2_amo       <= s1_amo;
                s2_amo_op    <= s1_amo_op;
            end
        end

    end 

endmodule