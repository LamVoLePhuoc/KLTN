`timescale 1ns / 1ps

module RV32IMA_DualCore_BoardTop(
    input  wire sys_clock,
    input  wire reset_rtl,
    output wire led_out
);

    wire clk = sys_clock;
    wire rst = reset_rtl;

    wire [31:0] PC0F;
    wire [31:0] PC1F;
    wire [31:0] Instr0F;
    wire [31:0] Instr1F;

    wire [31:0] Shared_Mem_Addr;
    wire [31:0] Shared_Mem_WriteData;
    wire        Shared_Mem_WriteEn;
    wire        Shared_Mem_ReadEn;
    wire [2:0]  Shared_MemOp;
    wire [31:0] Shared_Mem_ReadData;

    wire [31:0] Core0_ResultW;
    wire [31:0] Core1_ResultW;
    wire [31:0] Core0_ALU_ResultE_Debug;
    wire [31:0] Core1_ALU_ResultE_Debug;
    wire        Grant0_Debug;
    wire        Grant1_Debug;
    wire        Turn_Debug;

    reg [31:0] ram [0:4095];

    initial begin
        $readmemh("program.mem", ram);
    end

    assign Instr0F = ram[PC0F[13:2]];
    assign Instr1F = ram[PC1F[13:2]];

    assign Shared_Mem_ReadData =
        Shared_Mem_ReadEn ? ram[Shared_Mem_Addr[13:2]] : 32'b0;

    always @(posedge clk) begin
        if (Shared_Mem_WriteEn) begin
            case (Shared_MemOp)
                3'b000: begin
                    case (Shared_Mem_Addr[1:0])
                        2'b00: ram[Shared_Mem_Addr[13:2]][7:0]   <= Shared_Mem_WriteData[7:0];
                        2'b01: ram[Shared_Mem_Addr[13:2]][15:8]  <= Shared_Mem_WriteData[7:0];
                        2'b10: ram[Shared_Mem_Addr[13:2]][23:16] <= Shared_Mem_WriteData[7:0];
                        2'b11: ram[Shared_Mem_Addr[13:2]][31:24] <= Shared_Mem_WriteData[7:0];
                    endcase
                end

                3'b001: begin
                    if (Shared_Mem_Addr[1] == 1'b0)
                        ram[Shared_Mem_Addr[13:2]][15:0] <= Shared_Mem_WriteData[15:0];
                    else
                        ram[Shared_Mem_Addr[13:2]][31:16] <= Shared_Mem_WriteData[15:0];
                end

                3'b010: begin
                    ram[Shared_Mem_Addr[13:2]] <= Shared_Mem_WriteData;
                end

                default: begin
                    ram[Shared_Mem_Addr[13:2]] <= Shared_Mem_WriteData;
                end
            endcase
        end
    end

    RV32IMA_DualCore_Wrapper dut (
        .clk                    (clk),
        .rst                    (rst),

        .PC0F                   (PC0F),
        .Instr0F                (Instr0F),

        .PC1F                   (PC1F),
        .Instr1F                (Instr1F),

        .Shared_Mem_Addr        (Shared_Mem_Addr),
        .Shared_Mem_WriteData   (Shared_Mem_WriteData),
        .Shared_Mem_WriteEn     (Shared_Mem_WriteEn),
        .Shared_Mem_ReadEn      (Shared_Mem_ReadEn),
        .Shared_MemOp           (Shared_MemOp),
        .Shared_Mem_ReadData    (Shared_Mem_ReadData),

        .Core0_ResultW          (Core0_ResultW),
        .Core1_ResultW          (Core1_ResultW),

        .Core0_ALU_ResultE_Debug(Core0_ALU_ResultE_Debug),
        .Core1_ALU_ResultE_Debug(Core1_ALU_ResultE_Debug),

        .Grant0_Debug           (Grant0_Debug),
        .Grant1_Debug           (Grant1_Debug),
        .Turn_Debug             (Turn_Debug)
    );

    assign led_out = Shared_Mem_WriteEn | Grant0_Debug | Grant1_Debug;

endmodule