`timescale 1ns/1ps
// from Lee Min Hunz with luv

module snoop_controller #(
    parameter ADDR_W = 32
)(
    input               i_snp_req_valid
// ,   input [1:0]         i_snp_req_cmd
,   input               i_snp_req_cmd_1
// ,   input [ADDR_W-1:0]  i_snp_req_addr
,   input               i_dcache_ready

    // Các tín hiệu ở Pipeline Stage 2
,   input               i_snp_resp_valid
,   input               i_snp_resp_hit     

,   output              o_snp_req_ready
,   output              snoop_req_invalidate
,   output              o_snp_resp_valid
,   output              snoop_moesi_we
);

    assign o_snp_req_ready      = i_dcache_ready;
    // Invalidate khi là UPGRADE (10) / READ_UNIQUE (11)
    // assign snoop_req_invalidate = i_snp_req_cmd[1];
    assign snoop_req_invalidate = i_snp_resp_valid & i_snp_req_cmd_1;
    
    assign o_snp_resp_valid     = i_snp_resp_valid;

    // ---> LOGIC CHO snoop_moesi_we <---
    // Chỉ cho phép ghi cập nhật MOESI khi Snoop đang ở Stage 2 và có HIT
    assign snoop_moesi_we       = i_snp_resp_valid & i_snp_resp_hit;

endmodule