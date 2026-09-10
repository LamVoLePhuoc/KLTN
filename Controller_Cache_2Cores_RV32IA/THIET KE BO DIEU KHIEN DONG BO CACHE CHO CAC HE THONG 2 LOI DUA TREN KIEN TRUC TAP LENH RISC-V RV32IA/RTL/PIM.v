`timescale 1ns/1ps
// from Lee Min Hunz with luv
module PIM #(   // Policy info Memory
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 3
)(
    input       clk
// ,   input       rst_n
,   input                           we
,   input       [ADDR_WIDTH-1:0]    read_addr
,   input       [ADDR_WIDTH-1:0]    write_addr
,   input       [DATA_WIDTH-1:0]    plru_in
,   output      [DATA_WIDTH-1:0]    plru_out
);
    localparam DEPTH = 1 << ADDR_WIDTH;
    reg [DATA_WIDTH-1:0] pim [0:DEPTH-1];
    
    integer i;
    // always @(posedge clk or negedge rst_n) begin
    //     if (~rst_n) begin
    //         plru_out    <= {DATA_WIDTH{1'b0}};
    //         for(i = 0 ; i < DEPTH; i = i + 1) begin
    //             pim[i]  <= 3'd0;
    //         end 
    //     end 
    //     else begin
    //         if (we) begin
    //             pim[write_addr]  <= plru_in;
    //         end 

    //         // Forwarding nội bộ (Bypass) để chống Data Hazard
    //         if (we && (read_addr == write_addr)) begin
    //             plru_out <= plru_in; 
    //         end 
    //         else begin
    //             plru_out <= pim[read_addr];
    //         end
    //     end 
    // end 
    initial begin
    for (i = 0; i < DEPTH; i = i + 1) begin
            pim[i] = {DATA_WIDTH{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (we) begin
            pim[write_addr]  <= plru_in;
        end 
        // Forwarding nội bộ (Bypass) để chống Data Hazard
        // if (we && (read_addr == write_addr)) begin
        //     plru_out <= plru_in; 
        // end 
        // else begin
        //     plru_out <= pim[read_addr];
        // end
    end 

    assign plru_out = pim[read_addr];
endmodule