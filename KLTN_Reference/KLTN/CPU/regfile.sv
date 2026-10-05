module regfile (
    input wire clk_i,
    input wire rst_ni,
    input wire [4:0] rs1_addr,
    input wire rs1_rf_sel,
    input wire [4:0] rs2_addr,
    input wire rs2_rf_sel,
    input wire [4:0] rd_addr,
    input wire [63:0] rd_data,
    input wire rd_wren,
    input wire rd_commit,
    output wire [63:0] rs1_data,
    output wire [63:0] rs2_data,

    // For bridge to FPU
    input  logic        bridge_wren_i,
    input  logic        bridge_wr_commit_i,
    input  logic [4:0]  bridge_wr_addr_i,
    input  logic [63:0] bridge_wr_data_i,
    
    input  logic        bridge_rden_i,
    input  logic        bridge_rd_sel_i,
    input  logic [4:0]  bridge_rd_addr_i,
    output logic [63:0] bridge_rd_data_o
);
    timeunit 1ns; timeprecision 1ps;
    
    reg [63:0] registers[2][0:31];          // <data> regfile <main rf> <temp rf>

    always @(negedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int j = 0; j < 2; j = j + 1) begin
                for (int i = 0; i < 32; i = i + 1) begin
                    registers[j][i] <= 64'd0;
                end
            end
        end 
        else begin
            if (rd_wren && rd_addr != 0) begin
                if (rd_commit) begin
                    registers[0][rd_addr] <= rd_data;
                    registers[1][rd_addr] <= rd_data;
                end
                else begin
                    registers[0][rd_addr] <= registers[0][rd_addr];
                    registers[1][rd_addr] <= rd_data;
                end
            end

            if (bridge_wren_i && (bridge_wr_addr_i != 5'd0)) begin
                if (bridge_wr_commit_i) begin
                    registers[0][bridge_wr_addr_i] <= bridge_wr_data_i;
                    registers[1][bridge_wr_addr_i] <= bridge_wr_data_i;
                end
                else begin
                    registers[0][bridge_wr_addr_i] <= registers[0][bridge_wr_addr_i];
                    registers[1][bridge_wr_addr_i] <= bridge_wr_data_i;
                end
            end
        end 
    end

    assign rs1_data = (rs1_rf_sel) ? registers[1][rs1_addr] : registers[0][rs1_addr];
    assign rs2_data = (rs2_rf_sel) ? registers[1][rs2_addr] : registers[0][rs2_addr];
    assign bridge_rd_data_o = (bridge_rden_i) ? ((bridge_rd_sel_i) ? registers[1][bridge_rd_addr_i] : registers[0][bridge_rd_addr_i]) : 'z;
endmodule
