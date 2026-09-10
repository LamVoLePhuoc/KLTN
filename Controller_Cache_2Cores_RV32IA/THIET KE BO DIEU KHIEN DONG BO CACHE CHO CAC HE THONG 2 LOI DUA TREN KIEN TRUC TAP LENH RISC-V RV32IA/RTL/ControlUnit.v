`timescale 1ns/1ps
// from Lee Min Hunz with luv
module ControlUnit(
    input   [6:0]   op
// ,   input   [6:0]   funct7
,   input           funct7_5    
,   input   [4:0]   funct5
,   input   [2:0]   funct3
    
,   output          MemWrite 
,   output          ALUSrc
,   output          RegWrite
,   output          Jump
,   output          Branch
,   output          addr_addend_sel
,   output          ResPCSel
,   output          data_req
,   output  [3:0]   ALUControl
,   output  [2:0]   ImmSrc
,   output  [2:0]   ResultSrc
,   output  [2:0]   StoreSrc
,   output          amo
,   output  [2:0]   amo_op
,   output          lr
,   output          sc
);
    wire [2:0]  ALUOp;
    wire        AtomicOp;
    MainDecoder maindecoder_inst(
        .op                 (op),
        .funct3             (funct3),
        .Branch             (Branch),
        .ResultSrc          (ResultSrc),
        .MemWrite           (MemWrite),
        .ALUSrc             (ALUSrc),
        .RegWrite           (RegWrite),
        .ImmSrc             (ImmSrc),
        .ALUOp              (ALUOp),
        .Jump               (Jump),
        .StoreSrc           (StoreSrc),
        .addr_addend_sel    (addr_addend_sel),
        .ResPCSel           (ResPCSel),
        .data_req           (data_req),
        .AtomicOp           (AtomicOp)
    );

    AluDecoder aludecoder_inst(
        .ALUOp      (ALUOp),
        .funct3     (funct3),
        // .funct7_5   (funct7[5]),
        .funct7_5   (funct7_5),
        .op_5       (op[5]),
        .ALUControl (ALUControl)
    );

    atomic_decoder atomic_decoder_inst (
        .AtomicOp   (AtomicOp),
        .funct5     (funct5),
        .amo        (amo),
        .amo_op     (amo_op),
        .lr         (lr),
        .sc         (sc)
    );
    
endmodule