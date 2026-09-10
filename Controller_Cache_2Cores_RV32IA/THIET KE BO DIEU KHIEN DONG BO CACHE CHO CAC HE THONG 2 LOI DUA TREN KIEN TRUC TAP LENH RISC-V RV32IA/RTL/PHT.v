// from Lee Min Hunz with luv
`timescale 1ns / 1ps
// ============================================================================
// PHT - Pattern History Table (GShare Predictor)
// ============================================================================
module PHT(
    input           clk, rst_n
,   input [2:0]     F_PC   
,   output          predict
,   output [2:0]    GHSR_out

,   input           M_Branch
,   input           M_Jump
,   input           M_PCSrc      // 1 if actually taken, 0 if not taken
,   input [2:0]     M_PC 
,   input [2:0]     M_GHSR   
);
    reg [2:0] GHSR;                     
    reg [1:0] next_state;               
    reg [1:0] state [0:7];              

    // ================================================================
    // INDEX COMPUTATION
    // ================================================================
    wire [2:0]  read_index      = F_PC ^ GHSR;        // IF stage read
    wire [2:0]  write_index     = M_PC ^ M_GHSR;      // MEM stage write
    
    wire [1:0]  current_state   = state[read_index];
    wire [1:0]  M_State         = state[write_index]; // Fast LUT read (timing safe now)
    wire        final_taken     = M_PCSrc | M_Jump;   // Jumps always taken

    assign predict  = current_state[1];
    assign GHSR_out = GHSR;

    // ================================================================
    // 2-BIT SATURATING COUNTER
    // ================================================================
    always @(*) begin
        case(M_State)
            2'b00: next_state = final_taken ? 2'b01 : 2'b00; // SNT
            2'b01: next_state = final_taken ? 2'b10 : 2'b00; // WNT
            2'b10: next_state = final_taken ? 2'b11 : 2'b01; // WT
            2'b11: next_state = final_taken ? 2'b11 : 2'b10; // ST
            default: next_state = 2'b10; // prevent X latching
        endcase
    end

    // ================================================================
    // SYNCHRONOUS UPDATE
    // ================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            GHSR <= 3'b000;
            for(i = 0; i < 8; i = i + 1) 
                state[i] <= 2'b10; // Init as Weakly Taken
        end
        else begin
            if(M_Branch | M_Jump) begin
                GHSR <= {GHSR[1:0], final_taken};
                state[write_index] <= next_state;
            end
        end
    end
endmodule