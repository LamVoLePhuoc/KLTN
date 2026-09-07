`timescale 1ns/1ps
`include "define.vh"
// from Lee Min Hunz with luv
// ============================================================================
// Control Write - AXI Write Burst Controller
// ============================================================================
// Handles AXI AW/W channel handshakes and generates sequential write addresses.
// Supports FIXED, INCR, and WRAP burst types. Uses WLAST to detect burst end.
// ============================================================================
module control_write #(
    parameter DATA_W = 32
)(
    input                       clk
,   input                       rst_n
    // AW Channel
,   input                       awvalid
,   input       [1:0]           awburst
// ,   input       [2:0]           awsize
// ,   input       [7:0]           awlen      // hien tai chua su dung tai su dung wlast de ket thuc burst
,   input       [DATA_W-1:0]    awaddr
,   output reg                  awready

    // W Channel
,   input                       wvalid
,   input                       wlast
,   output reg                  wready

    // Memory Interface
,   output      [DATA_W-1:0]    w_addr
,   output reg                  write_en            
);

    // ================================================================
    // LOCAL PARAMETERS
    // ================================================================
    localparam IDLE    = 1'd0;  // Waiting for AW handshake
    localparam WRITE   = 1'd1;  // Receiving W beats

    // ================================================================
    // REG DECLARATIONS  
    // ================================================================
    reg             state, next_state;
    reg [DATA_W-1:0]    reg_addr;       // Current write address
    reg [1:0]           reg_awburst;    // Burst type
    // reg [2:0]           reg_awsize;     // Beat size

    // ================================================================
    // AWREADY - Accept new request when idle
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin 
            awready <= 1'b0;
        end 
        else begin
            if (state == IDLE && !awvalid) begin
                awready <= 1'b1;
            end 
            else if (awvalid && awready) begin   
                awready <= 1'b0; 
            end 
            else if (state != IDLE) begin 
                awready <= 1'b0;
            end 
        end
    end

    // ================================================================
    // ADDRESS GENERATION - Latch on AW handshake, increment on W beats
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            reg_addr    <= {DATA_W{1'b0}};
            reg_awburst <= 2'b00;
            // reg_awsize  <= 3'b00;
        end 
        else begin
            case(state)
                IDLE: begin
                    if (awvalid && awready) begin
                        reg_addr    <= (awaddr - `MEM_BASE) >> 2;
                        reg_awburst <= awburst;
                        // reg_awsize  <= awsize;
                    end
                end

                WRITE: begin
                    if (wvalid && wready) begin
                        case (reg_awburst) 
                            2'b00: reg_addr <= reg_addr; // FIXED
                            // For INCR/WRAP increment by one word (reg_addr stores word-index)
                            2'b01: reg_addr <= reg_addr + 1'b1; // INCR
                            2'b10: reg_addr <= reg_addr + 1'b1; // WRAP
                            default: reg_addr <= reg_addr + 1'b1;
                        endcase
                    end
                end
            endcase
        end
    end
    
    // ================================================================
    // OUTPUT LOGIC
    // ================================================================
    assign w_addr = reg_addr;

    always @(*) begin
        if (state == WRITE && wvalid && wready) begin
            write_en = 1'b1;
        end 
        else begin
            write_en = 1'b0;
        end
    end

    // AWREADY/WREADY logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wready <= 1'b0;
        end
        else begin
            if (state == WRITE) 
                wready <= 1'b1;
            else
                wready <= 1'b0;
        end
    end
    // ================================================================
    // FSM - IDLE waits for AW, WRITE receives data until WLAST
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin 
            state <= IDLE;
        end 
        else begin       
            state <= next_state;
        end 
    end

    always @(*) begin
        case (state)
            IDLE: begin
                if (awvalid && awready) begin
                    next_state = WRITE;
                end 
                else begin                    
                    next_state = IDLE;
                end 
            end
            
            WRITE: begin
                if (wvalid && wready && wlast) begin 
                    next_state = IDLE;
                end
                else begin                           
                    next_state = WRITE;
                end 
            end
            default: next_state = IDLE;
        endcase
    end

endmodule