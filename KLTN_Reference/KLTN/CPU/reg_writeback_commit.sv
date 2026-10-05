module reg_writeback_commit (
    input  logic        clk, 
    input  logic        aclr,

    input  logic        wr_commitW,
    input  logic        fpu_wr_commitW,
    input  logic        rd_wrenW,
    input  logic [4:0]  rd_addrW,
    input  logic [63:0] wb_dataW,
    input  logic        bridge_wrenW,
    input  logic [4:0]  bridge_wr_addrW,
    input  logic [63:0] bridge_wr_dataW,

    output logic        wr_commitC,
    output logic        fpu_wr_commitC,
    output logic        rd_wrenC,
    output logic [4:0]  rd_addrC,
    output logic [63:0] wb_dataC,
    output logic        bridge_wrenC,
    output logic [4:0]  bridge_wr_addrC,
    output logic [63:0] bridge_wr_dataC
);
    timeunit 1ns; timeprecision 1ps;
    
    always_ff @ (posedge clk, negedge aclr) begin
        if (!aclr) begin
            {wr_commitC, rd_wrenC, rd_addrC, wb_dataC, bridge_wrenC, bridge_wr_addrC, bridge_wr_dataC, fpu_wr_commitC} <= 'd0;
        end
        else begin 
            {wr_commitC, rd_wrenC, rd_addrC, wb_dataC, bridge_wrenC, bridge_wr_addrC, bridge_wr_dataC, fpu_wr_commitC} <= {wr_commitW, rd_wrenW, rd_addrW, wb_dataW, bridge_wrenW, bridge_wr_addrW, bridge_wr_dataW, fpu_wr_commitW};
        end
    end

endmodule: reg_writeback_commit 