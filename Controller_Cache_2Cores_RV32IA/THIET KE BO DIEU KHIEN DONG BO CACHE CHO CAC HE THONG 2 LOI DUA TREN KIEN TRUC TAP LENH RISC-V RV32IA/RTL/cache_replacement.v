`timescale 1ns/1ps
// from Lee Min Hunz with luv
module cache_replacement #(
    parameter N_WAYS    = 4,
    parameter N_LINES   = 16,
    parameter N_WAYS_W  = $clog2(N_WAYS),
    parameter N_LINES_W = $clog2(N_LINES)
)(
    input                   clk
,   input                   rst_n
,   input                   we
,   input   [N_WAYS-1:0]    way_hit
,   input   [N_LINES_W-1:0] read_addr
,   input   [N_LINES_W-1:0] write_addr
,   output  [N_WAYS-1:0]    way_select
);

    wire [N_WAYS-1:1] tree_in, tree_out;
    wire [N_WAYS_W:0] node_id [1:N_WAYS_W];

    /*
    == tree traverse ==

                         <--0     1-->              traverse direction
                              [1]                   node id @ level1
                    [2]                 [3]         node id @ level2 ==> which to traverse? from node_id[1]
               [4]       [5]       [6]       [7]    node id @ level3 ==> which to traverse? from node_id[2]
              (00)       (01)      (02)      (03)   way idx

            node value is 0 -> left tree traverse
            node value is 1 -> right tree traverse

            node id mapping to way idx: node_id[NWAYS_W]-N_WAYS
    */

    assign node_id[1] = (tree_out[1]) ? 3'd3 : 3'd2;
    assign node_id[2] = (tree_out[node_id[1]]) ? ((node_id[1] << 1) + 1'd1) : (node_id[1]<<1);

    // Nut 1 (root): trai {0,1}, phai {2,3}
    plru plru_update1(
        .clk        (clk)
    ,   .rst_n      (rst_n)
    ,   .prev_bit   (tree_out[1])
    ,   .left_hit   (|way_hit[1:0])
    ,   .right_hit  (|way_hit[3:2])
    ,   .plru_bit   (tree_in[1])
    );

    // Nút 2 (con trái root): left={way0}, right={way1}
    plru plru_update2(
        .clk        (clk)
    ,   .rst_n      (rst_n)
    ,   .prev_bit   (tree_out[2])
    ,   .left_hit   (way_hit[0])
    ,   .right_hit  (way_hit[1])
    ,   .plru_bit   (tree_in[2])
    );

    // Nút 3 (con phải root): left={way2}, right={way3}
    plru plru_update3(
        .clk        (clk)
    ,   .rst_n      (rst_n)
    ,   .prev_bit   (tree_out[3])
    ,   .left_hit   (way_hit[2])
    ,   .right_hit  (way_hit[3])
    ,   .plru_bit   (tree_in[3])
    );

    PIM #(
        .ADDR_WIDTH(N_LINES_W),
        .DATA_WIDTH(N_WAYS-1)
    ) Policy_info_Memory (
        .clk        (clk)
    // ,   .rst_n      (rst_n)
    ,   .we         (we)
    ,   .read_addr  (read_addr)
    ,   .write_addr (write_addr)
    ,   .plru_in    (tree_in)
    ,   .plru_out   (tree_out)
    );

	wire [N_WAYS_W-1:0]	way_select_bin  = node_id[2][1:0];
    assign              way_select      = ({{(N_WAYS-1){1'b0}}, 1'b1} << way_select_bin);
endmodule