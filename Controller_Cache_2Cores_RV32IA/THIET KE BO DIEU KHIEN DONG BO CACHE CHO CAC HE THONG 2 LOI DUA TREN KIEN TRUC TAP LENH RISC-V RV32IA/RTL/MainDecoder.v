`timescale 1ns/1ps
// from Lee Min Hunz with luv
module MainDecoder(
    input       [6:0] op
,   input       [2:0] funct3
,   output reg  Branch
,   output reg  MemWrite
,   output reg  ALUSrc
,   output reg  RegWrite
,   output reg  Jump
,   output reg  addr_addend_sel
,   output reg  ResPCSel
,   output reg  [2:0]   ALUOp
,   output reg  [2:0]   ImmSrc
,   output reg  [2:0]   ResultSrc
,   output reg  [2:0]   StoreSrc
,   output reg  data_req
,   output reg  AtomicOp
);

    always @(*) begin
        case(op)
            7'b0000011: begin
                case(funct3)
                    3'd0: begin
                        StoreSrc = 3'b001;  // lb
                    end
                    3'd1: begin
                        StoreSrc = 3'b010;  // lh
                    end
                    3'd2: begin
                        StoreSrc = 3'b000;  // lw
                    end
                    3'd4: begin
                        StoreSrc = 3'b101;  // lbu
                    end
                    3'd5: begin
                        StoreSrc = 3'b110;  // lhu
                    end
                    default: begin
                        StoreSrc = 3'b000;
                    end 
                endcase 
                data_req        = 1'b1;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;
                RegWrite        = 1'b1;
                ImmSrc          = 3'b000;
                ALUSrc          = 1'b1;
                MemWrite        = 1'b0;
                ResultSrc       = 3'b001;
                Branch          = 1'b0;
                ALUOp           = 3'b000;
                Jump            = 1'b0;
                AtomicOp        = 1'b0;
            end 
            7'b0100011: begin          
                case(funct3)
                    3'd0: begin
                        StoreSrc = 3'b001;  // sb
                    end
                    3'd1: begin
                        StoreSrc = 3'b010;  // sh
                    end
                    3'd2: begin
                        StoreSrc = 3'b000;  // sw
                    end
                    default: begin
                        StoreSrc = 3'b000;
                    end 
                endcase 
                data_req        = 1'b1;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;
                RegWrite        = 1'b0;
                ImmSrc          = 3'b001;
                ALUSrc          = 1'b1;
                MemWrite        = 1'b1;
                ResultSrc       = 3'b000;
                Branch          = 1'b0;
                ALUOp           = 3'b000;
                Jump            = 1'b0;
                AtomicOp        = 1'b0; 
            end 
            7'b0110011: begin           // R-type
                data_req        = 1'b0;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;
                ResultSrc       = 3'b000;
                RegWrite        = 1'b1;
                ImmSrc          = 3'b000;
                ALUSrc          = 1'b0;
                MemWrite        = 1'b0;
                Branch          = 1'b0;
                ALUOp           = 3'b010;
                Jump            = 1'b0;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b0;
            end 
            7'b1100011: begin           // branch
                data_req        = 1'b0;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;

                RegWrite        = 1'b0;
                ImmSrc          = 3'b010;
                ALUSrc          = 1'b0;
                MemWrite        = 1'b0;
                ResultSrc       = 3'b000;
                Branch          = 1'b1;
                ALUOp           = 3'b001;
                Jump            = 1'b0;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b0;  // ATOMIC
            end 
            7'b0010011: begin           // I-type ALU
                data_req        = 1'b0;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;
                RegWrite        = 1'b1;
                ImmSrc          = 3'b000;
                ALUSrc          = 1'b1;
                MemWrite        = 1'b0;
                ResultSrc       = 3'b000;
                Branch          = 1'b0;
                ALUOp           = 3'b010;
                Jump            = 1'b0;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b0;
            end 
            7'b1101111: begin           // jal
                data_req        = 1'b0;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b1;
                RegWrite        = 1'b1;
                ImmSrc          = 3'b011;
                ALUSrc          = 1'b0;
                MemWrite        = 1'b0;
                ResultSrc       = 3'b000;
                Branch          = 1'b0;
                ALUOp           = 3'b101;
                Jump            = 1'b1;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b0;
            end 
            7'b1100111: begin           // jalr
                data_req        = 1'b0;
                addr_addend_sel = 1'b1;
                ResPCSel        = 1'b1;
                RegWrite        = 1'b1;
                ImmSrc          = 3'b000;
                ALUSrc          = 1'b0;
                MemWrite        = 1'b0;
                ResultSrc       = 3'b000;
                Branch          = 1'b0;
                ALUOp           = 3'b101;
                Jump            = 1'b1;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b0;
            end 
            7'b0110111: begin           // lui
                data_req        = 1'b0;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;
                RegWrite        = 1'b1;
                ImmSrc          = 3'd4;
                ALUSrc          = 1'b0;
                MemWrite        = 1'b0;
                ResultSrc       = 3'd0;
                Branch          = 1'b0;
                ALUOp           = 3'b011;
                Jump            = 1'b0;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b0;
            end 
            7'b0010111: begin           // auipc
                data_req        = 1'b0;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;
                
                RegWrite        = 1'b1;
                ImmSrc          = 3'd4;
                ALUSrc          = 1'b0;
                MemWrite        = 1'b0;
                ResultSrc       = 3'd0;
                Branch          = 1'b0;
                ALUOp           = 3'b100;
                Jump            = 1'b0;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b0;
            end

            7'b0101111: begin // ATOMIC: Atomic instructions (LR/SC/AMO)
                data_req        = 1'b1;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;

                RegWrite        = 1'b1;
                ImmSrc          = 3'd5;
                ALUSrc          = 1'b1;
                MemWrite        = 1'b0;
                ResultSrc       = 3'b101;
                Branch          = 1'b0;
                ALUOp           = 3'b000;
                Jump            = 1'b0;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b1;
            end
            default: begin
                data_req        = 1'b0;
                addr_addend_sel = 1'b0;
                ResPCSel        = 1'b0;

                RegWrite        = 1'b0;
                ImmSrc          = 3'd0;
                ALUSrc          = 1'b0;
                MemWrite        = 1'b0;
                ResultSrc       = 3'b000;
                Branch          = 1'b0;
                ALUOp           = 3'b000;
                Jump            = 1'b0;
                StoreSrc        = 3'b000;
                AtomicOp        = 1'b0;
            end 
        endcase
    end
endmodule
