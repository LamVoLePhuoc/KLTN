module Instruction_Memory #(
    parameter HEX_FILE = "memfile.hex" // Tên file mã máy chung
)(
    // --- Port A (Dành cho Core 0) ---
    input  wire [31:0] addr_a,
    output wire [31:0] inst_a,

    // --- Port B (Dành cho Core 1) ---
    input  wire [31:0] addr_b,
    output wire [31:0] inst_b
);

    // Mảng nhớ chung (Shared Memory)
    reg [31:0] rom [0:255]; 

    // Nạp mã máy từ file hex
    initial begin
        $readmemh(HEX_FILE, rom);
    end

    // --- Logic đọc song song ---
    // Cả 2 cổng hoạt động độc lập, không ai chặn ai
    assign inst_a = rom[addr_a[11:2]]; 
    assign inst_b = rom[addr_b[11:2]];

endmodule