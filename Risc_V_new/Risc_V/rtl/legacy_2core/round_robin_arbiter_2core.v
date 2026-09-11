`timescale 1ns / 1ps

module round_robin_arbiter_2core(
    input  wire        clk,
    input  wire        rst,

    // ============================================================
    // Core 0 data memory bus
    // ============================================================
    input  wire [31:0] c0_addr,
    input  wire [31:0] c0_wdata,
    input  wire        c0_we,
    input  wire        c0_re,
    input  wire [2:0]  c0_memop,
    output wire [31:0] c0_rdata,
    output wire        c0_stall,

    // ============================================================
    // Core 1 data memory bus
    // ============================================================
    input  wire [31:0] c1_addr,
    input  wire [31:0] c1_wdata,
    input  wire        c1_we,
    input  wire        c1_re,
    input  wire [2:0]  c1_memop,
    output wire [31:0] c1_rdata,
    output wire        c1_stall,

    // ============================================================
    // Shared RAM side
    // RAM này có thể nằm trong testbench
    // ============================================================
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire        mem_we,
    output wire        mem_re,
    output wire [2:0]  memop,
    input  wire [31:0] mem_rdata,

    // ============================================================
    // Snoop commit outputs for LR/SC
    // ============================================================
    output wire [31:0] c0_write_addr_commit,
    output wire        c0_write_commit,
    output wire [31:0] c1_write_addr_commit,
    output wire        c1_write_commit,

    // Debug
    output wire        grant0_debug,
    output wire        grant1_debug,
    output reg         turn_debug
);

    // ============================================================
    // Request detect
    // ============================================================
    wire c0_req;
    wire c1_req;

    assign c0_req = c0_we | c0_re;
    assign c1_req = c1_we | c1_re;

    // ============================================================
    // Round-robin turn
    //
    // turn_debug = 0: nếu cả hai cùng request, ưu tiên core 0
    // turn_debug = 1: nếu cả hai cùng request, ưu tiên core 1
    //
    // Sau khi grant một core trong lúc cả hai cùng request,
    // turn sẽ đổi sang core còn lại.
    // ============================================================
    reg grant0;
    reg grant1;

    always @(*) begin
        grant0 = 1'b0;
        grant1 = 1'b0;

        case ({c0_req, c1_req})
            2'b00: begin
                grant0 = 1'b0;
                grant1 = 1'b0;
            end

            2'b10: begin
                // Chỉ core 0 request
                grant0 = 1'b1;
                grant1 = 1'b0;
            end

            2'b01: begin
                // Chỉ core 1 request
                grant0 = 1'b0;
                grant1 = 1'b1;
            end

            2'b11: begin
                // Hai core cùng request, chọn theo turn
                if (turn_debug == 1'b0) begin
                    grant0 = 1'b1;
                    grant1 = 1'b0;
                end
                else begin
                    grant0 = 1'b0;
                    grant1 = 1'b1;
                end
            end

            default: begin
                grant0 = 1'b0;
                grant1 = 1'b0;
            end
        endcase
    end

    // ============================================================
    // Update turn
    //
    // Nếu cả hai cùng request:
    // - grant core 0 xong thì lần sau ưu tiên core 1
    // - grant core 1 xong thì lần sau ưu tiên core 0
    //
    // Nếu chỉ một core request thì không nhất thiết đổi turn.
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            turn_debug <= 1'b0;
        end
        else begin
            if (c0_req && c1_req) begin
                if (grant0)
                    turn_debug <= 1'b1;
                else if (grant1)
                    turn_debug <= 1'b0;
            end
        end
    end

    // ============================================================
    // Stall
    //
    // Core nào request nhưng không được grant thì stall.
    // ============================================================
    assign c0_stall = c0_req & ~grant0;
    assign c1_stall = c1_req & ~grant1;

    // ============================================================
    // Mux request to shared RAM
    // ============================================================
    assign mem_addr =
        grant0 ? c0_addr :
        grant1 ? c1_addr :
                 32'b0;

    assign mem_wdata =
        grant0 ? c0_wdata :
        grant1 ? c1_wdata :
                 32'b0;

    assign mem_we =
        grant0 ? c0_we :
        grant1 ? c1_we :
                 1'b0;

    assign mem_re =
        grant0 ? c0_re :
        grant1 ? c1_re :
                 1'b0;

    assign memop =
        grant0 ? c0_memop :
        grant1 ? c1_memop :
                 3'b000;

    // ============================================================
    // Return read data
    //
    // Core không được grant nhận 0, nhưng nó đang stall nên không dùng.
    // ============================================================
    assign c0_rdata = grant0 ? mem_rdata : 32'b0;
    assign c1_rdata = grant1 ? mem_rdata : 32'b0;

    // ============================================================
    // Snoop commit
    //
    // Chỉ báo write commit khi write thật sự được grant.
    // ============================================================
    assign c0_write_addr_commit = c0_addr;
    assign c0_write_commit      = grant0 & c0_we;

    assign c1_write_addr_commit = c1_addr;
    assign c1_write_commit      = grant1 & c1_we;

    // ============================================================
    // Debug grants
    // ============================================================
    assign grant0_debug = grant0;
    assign grant1_debug = grant1;

endmodule