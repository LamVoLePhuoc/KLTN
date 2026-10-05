module CPU_reg_manager (
    input  logic        clk,
    input  logic        rst_n,

    // Common bus
    input  logic        CPU2FPU,
    input  logic        FPU2CPU,
    input  logic        rd_en,
    input  logic        rd_long_cmd,
    input  logic [4:0]  rd_addr,
    input  logic [4:0]  rd_ROB_tag,

    input  logic [4:0]  rs1_addr,
    input  logic        rs1_exist,
    input  logic [4:0]  rs2_addr,
    input  logic        rs2_exist,
    input  logic [4:0]  rs3_addr,
    input  logic        rs3_exist,

    input  logic        rd_clr,
    input  logic [4:0]  rd_addr_clr,
    input  logic [4:0]  rd_ROB_clr,
    
    input  logic        rd_clr_FPU,
    input  logic [4:0]  rd_addr_clr_FPU,
    input  logic [4:0]  rd_ROB_clr_FPU,

    input  logic        backdoor_busy_i,
    input  logic        backdoor_long_cmd_i,

    input  logic [4:0]  rd_addrW_CPU,
    output logic [4:0]  current_wr_addr_tag_CPU,

    input  logic [4:0]  rs1_addr2cmp,
    input  logic [4:0]  rs1_addr2cmp_FPU,
    input  logic [4:0]  rs2_addr2cmp,
    output logic [4:0]  rs1_tag2cmp,
    output logic [4:0]  rs1_tag2cmp_FPU,
    output logic [4:0]  rs2_tag2cmp,

    output logic        backdoor_busy_o,
    output logic        backdoor_long_cmd_o,
    
    output logic        rs1_busy,
    output logic        rs2_busy,
    output logic        rs3_busy,
    output logic [4:0]  rs1_tag,
    output logic [4:0]  rs2_tag,
    output logic [4:0]  rs3_tag
);
    timeunit 1ns; timeprecision 1ps;
    
    logic reg_file[31:0];
    logic long_cmd_reg[31:0];
    logic [4:0] ROB_file[31:0];    // <ROB tag> ROB_file <register address>
    
    wire rs1_busy_reg;
    wire rs2_busy_reg;
    wire rs3_busy_reg;

    //=======================================================
    // 1) REGISTER FILE – synchronous update ONLY
    //=======================================================
    always_ff @(negedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (int i = 0; i < 32; i++) begin
                reg_file[i]     <= 1'b0;
                long_cmd_reg[i] <= 1'b0;
                ROB_file[i]     <= 'd0;
            end
        end
        else begin
            // synchronous clears
            if ((rd_clr == 1'b1) & (ROB_file[rd_addr_clr] == rd_ROB_clr)) begin
                reg_file[rd_addr_clr]     <= 1'b0;
                long_cmd_reg[rd_addr_clr] <= 1'b0;
            end
            
            if ((rd_clr_FPU == 1'b1) & (ROB_file[rd_addr_clr_FPU] == rd_ROB_clr_FPU)) begin
                reg_file[rd_addr_clr_FPU]     <= 1'b0;
                long_cmd_reg[rd_addr_clr_FPU] <= 1'b0;
            end

            if (rd_en) begin
                reg_file[rd_addr] <= 1'b1;
                ROB_file[rd_addr] <= rd_ROB_tag;

                if (~CPU2FPU) begin
                    if (rs1_exist & reg_file[rs1_addr] & long_cmd_reg[rs1_addr]) begin
                        long_cmd_reg[rd_addr] <= 1'b1;
                    end
                    else if (rs2_exist & reg_file[rs2_addr] & long_cmd_reg[rs2_addr]) begin
                        long_cmd_reg[rd_addr] <= 1'b1;
                    end
                    else if (rs3_exist & reg_file[rs3_addr] & long_cmd_reg[rs3_addr]) begin
                        long_cmd_reg[rd_addr] <= 1'b1;
                    end
                    else begin
                        long_cmd_reg[rd_addr] <= rd_long_cmd;
                    end
                end
                else begin
                    if (backdoor_busy_i & backdoor_long_cmd_i) begin
                        long_cmd_reg[rd_addr] <= 1'b1;
                    end
                    else begin
                        long_cmd_reg[rd_addr] <= rd_long_cmd;
                    end    
                end
            end
        end
    end

    //=======================================================
    // 2) ASYNCHRONOUS WAKE-UP (mask busy ngay lập tức)
    //=======================================================

    assign rs1_busy_reg = reg_file[rs1_addr] & long_cmd_reg[rs1_addr];
    assign rs2_busy_reg = reg_file[rs2_addr] & long_cmd_reg[rs2_addr];
    assign rs3_busy_reg = reg_file[rs3_addr] & long_cmd_reg[rs3_addr];

    assign rs1_busy = rs1_busy_reg &
                      !(rd_clr     & (rs1_addr == rd_addr_clr) & (ROB_file[rs1_addr] == rd_ROB_clr)) &
                      !(rd_clr_FPU & (rs1_addr == rd_addr_clr_FPU) & (ROB_file[rs1_addr] == rd_ROB_clr_FPU));

    assign rs2_busy = rs2_busy_reg &
                      !(rd_clr     & (rs2_addr == rd_addr_clr) & (ROB_file[rs2_addr] == rd_ROB_clr)) &
                      !(rd_clr_FPU & (rs2_addr == rd_addr_clr_FPU) & (ROB_file[rs2_addr] == rd_ROB_clr_FPU));

    assign rs3_busy = rs3_busy_reg &
                      !(rd_clr     & (rs3_addr == rd_addr_clr) & (ROB_file[rs3_addr] == rd_ROB_clr)) &
                      !(rd_clr_FPU & (rs3_addr == rd_addr_clr_FPU) & (ROB_file[rs3_addr] == rd_ROB_clr_FPU));

    assign rs1_tag  = ROB_file[rs1_addr];

    assign rs2_tag  = ROB_file[rs2_addr];
    
    assign rs3_tag  = ROB_file[rs3_addr];

    assign current_wr_addr_tag_CPU = ROB_file[rd_addrW_CPU];

    assign rs1_tag2cmp = ROB_file[rs1_addr2cmp];

    assign rs2_tag2cmp = ROB_file[rs2_addr2cmp];

    assign rs1_tag2cmp_FPU = ROB_file[rs1_addr2cmp_FPU];

    always_comb begin
        if (FPU2CPU) begin
            backdoor_busy_o     = reg_file[rs1_addr];
            backdoor_long_cmd_o = long_cmd_reg[rs1_addr];     
        end
        else begin
            backdoor_busy_o     = 1'b0;
            backdoor_long_cmd_o = 1'b0;
        end
    end

endmodule: CPU_reg_manager
