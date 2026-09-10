`timescale 1ns/1ps
// from Lee Min Hunz with luv

module HazardUnit_v2 #(
    parameter DATA_WIDTH = 32
)(
    input       E_Mispredict
// ,   input       M_Mispredict
,   input       M_RegWrite 
,   input       W_RegWrite 
    
,   input       icache_stall
,   input       dcache_stall

,   input [2:0] E_ResultSrc
,   input [4:0] D_Rs1 
,   input [4:0] D_Rs2 

,   input [4:0] E_Rs1 
,   input [4:0] E_Rs2 
,   input [4:0] E_rd 
,   input [4:0] M_Rd
,   input [4:0] W_Rd

,   output reg [1:0]    ForwardAE 
,   output reg [1:0]    ForwardBE 
,   output              F_Stall 
,   output              D_Stall 
,   output              E_Stall 
,   output              M_Stall
,   output              D_Flush 
,   output              fetch_pipe_Flush
,   output              E_Flush
,   output              M_Flush
);

    // ================================================================
    // FORWARDING MATCH SIGNALS
    // ================================================================
    // Chỉ forward nếu thanh ghi đích khác x0 (|Rd) và có tín hiệu RegWrite
    wire match_M_A  = (E_Rs1 == M_Rd) && (|E_Rs1) && M_RegWrite;
    wire match_W_A  = (E_Rs1 == W_Rd) && (|E_Rs1) && W_RegWrite;
    
    wire match_M_B  = (E_Rs2 == M_Rd) && (|E_Rs2) && M_RegWrite;
    wire match_W_B  = (E_Rs2 == W_Rd) && (|E_Rs2) && W_RegWrite;

    // ================================================================
    // FORWARDING MUX SELECT LOGIC
    // ================================================================
    // Ưu tiên data mới nhất: Stage M -> Stage WB
    // Giá trị select: 2'b01 (từ M_ALUResult), 2'b11 (từ W_mux_result) - Khớp với Mux4_1
    always @(*) begin
        // --- Forwarding cho A ---
        if      (match_M_A) ForwardAE = 2'b01; 
        else if (match_W_A) ForwardAE = 2'b10; 
        else                ForwardAE = 2'b00; 

        // --- Forwarding cho B ---
        if      (match_M_B) ForwardBE = 2'b01; 
        else if (match_W_B) ForwardBE = 2'b10; 
        else                ForwardBE = 2'b00; 
    end

    // ================================================================
    // STALL & FLUSH LOGIC
    // ================================================================
    // Load-Use Hazard: Stall khi lệnh ở E là Load hoặc Atomic (E_ResultSrc[0] == 1) 
    // VÀ lệnh ở ID cần dùng rd của lệnh Load đó (Đã thêm check |E_rd khác x0).
    wire lw_Stall;
    assign lw_Stall = (E_ResultSrc[0] == 1'b1) & ((D_Rs1 == E_rd) | (D_Rs2 == E_rd)) & (|E_rd);

    // 1. D-Cache stalls kẹt toàn bộ pipeline từ M ngược về trước
    assign M_Stall          = dcache_stall;
    assign E_Stall          = dcache_stall;
    assign D_Stall          = dcache_stall | lw_Stall | E_Stall;

    // 2. F_Stall logic: Mispredict có thể mở kẹt cho F_Stall nếu D-Cache không kẹt
    assign F_Stall = E_Stall | ((icache_stall | lw_Stall) & ~E_Mispredict);

    // 3. Flush logic: MUST be masked by Stall!
    // Không bao giờ được flush một tầng đang bị kẹt để bảo toàn state.
    assign E_Flush          = (lw_Stall | E_Mispredict) & ~E_Stall;
    assign D_Flush          = E_Mispredict & ~D_Stall;

    // M_Flush không cần dùng cho mispredict vì check ở E
    assign M_Flush          = 1'b0;
    assign fetch_pipe_Flush = E_Mispredict & ~F_Stall;


endmodule