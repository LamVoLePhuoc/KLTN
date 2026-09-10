`ifndef DEFINES_VH
`define DEFINES_VH

`define DATA_W          32
`define ADDR_W          32

// Danh cho dhystone benchmark test
`define MEM_BASE        32'h0000_0000
`define CODE_A_START    32'h0000_0000
`define CODE_B_START    32'h0000_0100
`define DATA_START      32'h0000_0200 

// Danh cho riscv-tests
// `define MEM_BASE        32'h8000_0000
// `define CODE_A_START    32'h8000_0000
// `define CODE_B_START    32'h8000_4000
// `define DATA_START      32'h8000_8000

`define NUM_WAYS        4
`define NUM_SETS        16
`define NUM_SETS_L2     64
`define WORD_OFF_W      4
`define BYTE_OFF_W      2

`define oAWSIZE         3'b010  // 4 byte (32-bit)
`define oAWBURST        2'b01
`define oARSIZE         3'b010  // 4 byte (32-bit)
`define oARBURST        2'b01   // INCR

`define C_M00_AXI_TARGET_SLAVE_BASE_ADDR    32'h40000000
`define C_M00_AXI_BURST_LEN                 16
`define C_M00_AXI_ID_WIDTH	                1
`define C_M00_AXI_ADDR_WIDTH	            32
`define C_M00_AXI_DATA_WIDTH	            32
`define C_M00_AXI_AWUSER_WIDTH	            0
`define C_M00_AXI_ARUSER_WIDTH	            0
`define C_M00_AXI_WUSER_WIDTH	            0
`define C_M00_AXI_RUSER_WIDTH	            0
`define C_M00_AXI_BUSER_WIDTH	            0

`define RAM_ADDR_W                          8
`define FF_DEPTH                            32
`define RESET_VALUE                         32'h0000_0000
`endif // DEFINES_VH