// `timescale 1ns/1ps
// // from Lee Min Hunz with luv
// module ram #(
//     parameter DATA_W        = 32
// ,   parameter ADDR_W        = 8
// ,   parameter RESET_VALUE   = 32'h0000_0000
// ,   parameter INIT_FILE_A   = ""
// ,   parameter INIT_FILE_B   = ""
// ,   parameter INIT_IDX_A    = 0
// ,   parameter INIT_IDX_B    = 0
// )(
//     input               clk 
// // ,   input               rst_n
// ,   input  [(DATA_W/8)-1:0] we
// ,   input                   re
// ,   input  [ADDR_W-1:0]     w_addr
// ,   input  [ADDR_W-1:0]     r_addr
// ,   input  [DATA_W-1:0]     w_data
// ,   output [DATA_W-1:0]     r_data
// ,   output reg              valid
// );
//     reg [DATA_W-1:0] mem [0:(1 << ADDR_W) - 1];
//     integer i;

//     initial begin
//         // 1. Khởi tạo giá trị mặc định cho toàn bộ mem
//         for (i = 0; i < (1 << ADDR_W); i = i + 1) begin
//             mem[i] = RESET_VALUE;
//         end

//         // 2. Nạp chương trình Core A nếu có file
//         if (INIT_FILE_A != "") begin
//             $readmemh(INIT_FILE_A, mem, INIT_IDX_A);
//         end

//         // 3. Nạp chương trình Core B nếu có file
//         if (INIT_FILE_B != "") begin
//             $readmemh(INIT_FILE_B, mem, INIT_IDX_B);
//         end
//     end

//     reg [DATA_W-1:0] OutMem;

//     always @(posedge clk) begin
//         for (i = 0; i < (DATA_W/8); i = i + 1) begin
//             if (we[i]) begin
//                 mem[w_addr][(i*8) +: 8] <= w_data[(i*8) +: 8];
//             end
//         end
        
//         if (re) begin
//             OutMem  <= mem[r_addr];
//             valid   <= 1'b1;
//         end 
//         else begin
//             valid   <= 1'b0;
//         end 
//     end

//     assign r_data = OutMem;

// endmodule

`timescale 1ns/1ps
// from Lee Min Hunz with luv
module ram #(
    parameter DATA_W        = 32
,   parameter ADDR_W        = 8
,   parameter RESET_VALUE   = 32'h0000_0000
,   parameter INIT_FILE_A   = ""
,   parameter INIT_FILE_B   = ""
,   parameter INIT_IDX_A    = 0
,   parameter INIT_IDX_B    = 0
)(
    input               clk 
// ,   input               rst_n

    // ==========================================
    // Port A (Dành cho AXI4-Lite - Vitis nạp code)
    // ==========================================
,   input  [(DATA_W/8)-1:0] we_a
,   input                   re_a
,   input  [ADDR_W-1:0]     addr_a
,   input  [DATA_W-1:0]     wdata_a
,   output [DATA_W-1:0]     rdata_a
,   output reg              valid_a

    // ==========================================
    // Port B (Dành cho AXI4-Full - Core truy xuất)
    // ==========================================
,   input  [(DATA_W/8)-1:0] we_b
,   input                   re_b
,   input  [ADDR_W-1:0]     addr_b
,   input  [DATA_W-1:0]     wdata_b
,   output [DATA_W-1:0]     rdata_b
,   output reg              valid_b
);
    reg [DATA_W-1:0] mem [0:(1 << ADDR_W) - 1];
    integer i, j;

    initial begin
        for (i = 0; i < (1 << ADDR_W); i = i + 1) mem[i] = RESET_VALUE;
        if (INIT_FILE_A != "") $readmemh(INIT_FILE_A, mem, INIT_IDX_A);
        if (INIT_FILE_B != "") $readmemh(INIT_FILE_B, mem, INIT_IDX_B);
    end

    reg [DATA_W-1:0] OutMemA;
    reg [DATA_W-1:0] OutMemB;

    always @(posedge clk) begin
        // --- Xử lý Port A ---
        if (we_a[0]) mem[addr_a][7:0]   <= wdata_a[7:0];
        if (we_a[1]) mem[addr_a][15:8]  <= wdata_a[15:8];
        if (we_a[2]) mem[addr_a][23:16] <= wdata_a[23:16];
        if (we_a[3]) mem[addr_a][31:24] <= wdata_a[31:24];

        if (re_a) begin
            OutMemA <= mem[addr_a];
            valid_a <= 1'b1;
        end else valid_a <= 1'b0;

        // --- Xử lý Port B ---
        if (we_b[0]) mem[addr_b][7:0]   <= wdata_b[7:0];
        if (we_b[1]) mem[addr_b][15:8]  <= wdata_b[15:8];
        if (we_b[2]) mem[addr_b][23:16] <= wdata_b[23:16];
        if (we_b[3]) mem[addr_b][31:24] <= wdata_b[31:24];

        if (re_b) begin
            OutMemB <= mem[addr_b];
            valid_b <= 1'b1;
        end else valid_b <= 1'b0;
    end

    assign rdata_a = OutMemA;
    assign rdata_b = OutMemB;

endmodule