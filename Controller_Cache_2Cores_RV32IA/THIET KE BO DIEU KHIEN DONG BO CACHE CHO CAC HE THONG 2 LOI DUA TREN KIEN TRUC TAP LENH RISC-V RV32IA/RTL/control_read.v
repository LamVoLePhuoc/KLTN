`timescale 1ns/1ps
`include "define.vh"
// from Lee Min Hunz with luv
// ============================================================================
// Control Read - AXI Read Burst Controller
// ============================================================================
// Handles AXI AR channel handshake and generates sequential read addresses
// for burst transfers. Supports FIXED, INCR, and WRAP burst types.
// ============================================================================
module control_read #(
    parameter DATA_W = 32
)(
    input                               clk
,   input                               rst_n
    
    // AR Channel
,   input                               arvalid
,   output reg                          arready
,   input       [1:0]                   arburst
// ,   input       [2:0]                   arsize
,   input       [7:0]                   arlen
,   input       [DATA_W-1:0]            araddr
    
    // R Channel 
,   input                               fifo_r_push_able
// ,   input                               fifo_r_pop_able
// ,   input                               rvalid_from_mem
,   output reg                          last_data_from_mem

    // Memory Interface
,   input                               fifo_ar_full
,   output      [DATA_W-1:0]            r_addr
,   output reg                          read_en
);

    // ================================================================
    // LOCAL PARAMETERS
    // ================================================================
    localparam IDLE = 1'd0;     // Waiting for AR handshake
    localparam READ = 1'd1;     // Generating read addresses

    // ================================================================
    // REG DECLARATIONS
    // ================================================================
    reg                 state, next_state;
    reg [7:0]           count_addr;
    // Reg [7:0]           read_count;                 // Address counter, read beat counter
    reg [DATA_W-1:0]    reg_addr;                   // Current address (word-aligned)

    // Latched burst parameters
    reg [1:0]       reg_arburst;    // Burst type
    // reg [2:0]       reg_arsize;     // Beat size
    reg [7:0]       reg_arlen;      // Burst length - 1

    // ================================================================
    // ARREADY LOGIC - Accept new request when FIFO not full
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            arready <= 1'b0;
        else begin
            if (state == IDLE && ~fifo_ar_full) 
                arready <= 1'b1;
            else 
                arready <= 1'b0;
        end
    end

    // ================================================================
    // ADDRESS GENERATION - Latch params on handshake, increment on each beat
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            reg_addr    <= {DATA_W{1'b0}};
            count_addr  <= 8'd0;
            reg_arburst <= 2'b00;
            // reg_arsize  <= 3'b00;
            reg_arlen   <= 8'd0;
        end 
        else begin
            state <= next_state;
            case(state)
                IDLE: begin
                    count_addr <= 8'd0;
                    if (arvalid && arready) begin
                        reg_addr    <= (araddr - `MEM_BASE) >> 2; // Subtract MEM_BASE and shift to get word address
                        reg_arburst <= arburst;
                        // reg_arsize  <= arsize;
                        reg_arlen   <= arlen;
                    end
                end

                READ: begin
                    if (fifo_r_push_able) begin
                        if (count_addr < reg_arlen) begin
                             count_addr <= count_addr + 1'b1;
                            case (reg_arburst) 
                                2'b00: reg_addr <= reg_addr; // FIXED
                                // For INCR/WRAP increment by one word (reg_addr stores word-index)
                                2'b01: reg_addr <= reg_addr + 1'b1; // INCR
                                2'b10: reg_addr <= reg_addr + 1'b1; // WRAP
                                default: reg_addr <= reg_addr + 1'b1;
                            endcase
                        end
                        else begin
                            count_addr <= 8'd0;
                        end
                    end
                end
            endcase
        end
    end
    
    // ================================================================
    // RLAST GENERATION - Assert on last beat of burst
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // read_count <= 8'd0;
            last_data_from_mem <= 1'b0;
        end 
        else begin
            if (state == READ)
                last_data_from_mem <= (count_addr == reg_arlen);

            // if (fifo_r_pop_able) begin
            //     if (read_count < reg_arlen) begin
            //         read_count <= read_count + 1'b1;
            //     end
            //     else begin
            //         read_count <= 8'd0;
            //     end
            // end
        end
    end

    assign r_addr = reg_addr;


    // ================================================================
    // FSM - IDLE waits for request, READ generates address sequence
    // ================================================================
    always @(*) begin
        case (state)
            IDLE: begin
                read_en = 1'b0;
                if (arvalid && arready) begin 
                    next_state = READ;
                end
                else begin                    
                    next_state = IDLE;
                end 
            end
            
            READ: begin
                read_en = 1'b1;  
                if ((count_addr == reg_arlen) && fifo_r_push_able) begin 
                    next_state = IDLE; 
                end 
                else begin                 
                    next_state = READ;
                end 
            end
            
            default: begin
                read_en    = 1'b0;
                next_state = IDLE;
            end 
        endcase
    end
endmodule