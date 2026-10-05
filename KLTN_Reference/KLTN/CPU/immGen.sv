module immGen (
    input  [31:0] instr,
    output logic [63:0] imm
);
    timeunit 1ns; timeprecision 1ps;
    
    logic [19:0] iU;
    logic [20:0] iJ;
    logic [11:0] iI, iS;
    logic [12:0] iB;
    logic [4:0] shamt;
    logic [5:0] shamt_RV64;
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [31:0] imm_32bit;

    assign iU = instr[31:12];
    assign iJ = {instr[31],instr[19:12],instr[20],instr[30:21],1'b0};
    assign iI = instr[31:20];
    assign iS = {instr[31:25],instr[11:7]};
    assign iB = {instr[31],instr[7],instr[30:25],instr[11:8],1'b0};
    assign shamt = instr[24:20];
    assign shamt_RV64 = instr[25:20];
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];

    localparam LUI   = 7'b0110111;
    localparam AUIPC = 7'b0010111;
    localparam JAL   = 7'b1101111;
    localparam JALR  = 7'b1100111;
    localparam Br    = 7'b1100011;
    localparam Ld    = 7'b0000011;
    localparam St    = 7'b0100011;
    localparam Im    = 7'b0010011;
    localparam ImW   = 7'b0011011;

    always_comb begin
        if (opcode == LUI || opcode == AUIPC) begin
            imm_32bit = {iU, 12'b0};
        end
        else if (opcode == JAL) begin
            imm_32bit = {{11{iJ[20]}}, iJ};
        end
        else if (opcode == JALR || opcode == Ld || (opcode == Im && (funct3 == 3'b000 || funct3 == 3'b010 || funct3 == 3'b100 || funct3 == 3'b110 || funct3 == 3'b111))) begin
            imm_32bit = {{20{iI[11]}}, iI};
        end
        else if (opcode == Im && funct3 == 3'b011) begin
            imm_32bit = {20'b0, iI};
        end
        else if (opcode == Im && (funct3 == 3'b001 || funct3 == 3'b101)) begin
            imm_32bit = {26'b0, shamt_RV64};
        end
        else if (opcode == Br) begin
            imm_32bit = {{19{iB[12]}}, iB};
        end
        else if (opcode == St) begin
            imm_32bit = {{20{iS[11]}}, iS};
        end
        else if (opcode == ImW && funct3 == 3'b000) begin
            imm_32bit = {{20{iI[11]}}, iI};
        end
        else if (opcode == ImW && (funct3 == 3'b001 || funct3 == 3'b101)) begin
            imm_32bit = {27'b0, shamt};
        end
        else begin
            imm_32bit = 0;
        end
    end

    assign imm = {{32{imm_32bit[31]}}, imm_32bit};

endmodule