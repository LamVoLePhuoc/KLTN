// from Lee Min Hunz with luv
`timescale 1ns / 1ps
// ============================================================================
// BPU - Branch Prediction Unit (Updated for MEM-stage resolution)
// ============================================================================
module BPU #(
    parameter W_ADDR = 32
)(
    input               clk, rst_n
    // IF state (Fetch)
,   input [W_ADDR-1:2]  F_PC                 
,   output              predict_taken  
,   output [W_ADDR-1:0] target_pc      
,   output [2:0]        F_GHSR 

    // MEM state (Resolution & Update)
,   input [W_ADDR-1:2]  M_PC           
,   input [W_ADDR-1:0]  M_PCTarget  
,   input               M_Branch        
,   input               M_Jump          
,   input               M_PCSrc   
,   input [2:0]         M_GHSR          
);

    wire                btb_hit;
    wire                pht_predict_taken;
    wire [W_ADDR-1:0]   btb_pred_addr;
    
    // Final prediction: BTB must hit AND PHT must predict taken
    assign predict_taken    = btb_hit & pht_predict_taken;
    assign target_pc        = btb_pred_addr; 

    BTB #(
        .W_ADDR(W_ADDR)
    ) Branch_Target_Buffer (
        .clk            (clk)
    ,   .rst_n          (rst_n)
    ,   .F_PC           (F_PC[W_ADDR-1:2])
    ,   .pc_prediction  (btb_pred_addr)
    ,   .hit            (btb_hit)       

    ,   .M_PC           (M_PC[W_ADDR-1:2])            
    ,   .M_PCTarget     (M_PCTarget)
    ,   .M_Branch       (M_Branch)    
    ,   .M_Jump         (M_Jump)
    );

    PHT Pattern_History_Table (
        .clk            (clk)
    ,   .rst_n          (rst_n)
    ,   .F_PC           (F_PC[4:2])     
    ,   .predict        (pht_predict_taken)
    ,   .GHSR_out       (F_GHSR)

    ,   .M_Branch       (M_Branch)    
    ,   .M_Jump         (M_Jump)      
    ,   .M_PCSrc        (M_PCSrc)      
    ,   .M_PC           (M_PC[4:2])
    ,   .M_GHSR         (M_GHSR)                  
    );
endmodule