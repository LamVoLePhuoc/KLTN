module CPU_reservation_station #(parameter NO_RESERV = 5) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en,
    input  logic        stall,
    input  logic        hold,

    // Common bus
    input  logic [31:0] instr_i,

    input  logic [4:0]  rd_addr_i,
    input  logic        rd_exist_i,
    input  logic [4:0]  rd_ROB_tag_i,

    input  logic [4:0]  rs1_addr_i,
    input  logic [4:0]  rs1_tag_i,
    input  logic        rs1_exist_i,
    input  logic        rs1_busy_i,

    input  logic [4:0]  rs2_addr_i,
    input  logic [4:0]  rs2_tag_i,
    input  logic        rs2_exist_i,
    input  logic        rs2_busy_i,

    input  logic [4:0]  rd_addr_clr,
    input  logic [4:0]  rd_ROB_clr,
    input  logic        rd_clr,

    input  logic [4:0]  rd_addr_FPU_clr,
    input  logic [4:0]  rd_ROB_FPU_clr,
    input  logic        rd_FPU_clr,

    output logic [31:0] instr_o,
    output logic [4:0]  wr_addr_tag_o,

    output logic [4:0]  rs1_tag_o,
    output logic [4:0]  rs1_addr_o,
    output logic [4:0]  rs2_tag_o,
    output logic [4:0]  rs2_addr_o,

    output logic        all_busy
);
    timeunit 1ns; timeprecision 1ps;

    `ifdef DEBUG_EN
        logic [4:0]  rd_addr_debug[NO_RESERV];
        logic        rd_exist_debug[NO_RESERV];
        logic [4:0]  rd_ROB_tag_debug[NO_RESERV];
        logic [4:0]  rs1_addr_debug[NO_RESERV];
        logic [4:0]  rs1_tag_debug[NO_RESERV];
        logic        rs1_exist_debug[NO_RESERV];
        logic        rs1_busy_debug[NO_RESERV];
        logic [4:0]  rs2_addr_debug[NO_RESERV];
        logic [4:0]  rs2_tag_debug[NO_RESERV];
        logic        rs2_exist_debug[NO_RESERV];
        logic        rs2_busy_debug[NO_RESERV];
        logic [31:0] instr_debug[NO_RESERV];
        logic        busy_debug[NO_RESERV];
    `endif
    
    typedef struct packed {
        logic [4:0]  rd_addr;
        logic        rd_exist;
        logic [4:0]  rd_ROB_tag;
        logic [4:0]  rs1_addr;
        logic [4:0]  rs1_tag;
        logic        rs1_exist;
        logic        rs1_busy;
        logic [4:0]  rs2_addr;
        logic [4:0]  rs2_tag;
        logic        rs2_exist;
        logic        rs2_busy;
        logic [31:0] instr;
        logic        busy;
    } reserv_type;
    
    reserv_type                   reserv_arr[NO_RESERV];
    logic [$clog2(NO_RESERV)-1:0] write_idx;
    logic                         write_valid;
    logic [$clog2(NO_RESERV)-1:0] read_idx;
    logic                         read_valid;
    wire  [(NO_RESERV-1):0]       busy_vec;
    
    `ifdef DEBUG_EN
        genvar i_debug;
        generate
            for (i_debug = 0; i_debug < NO_RESERV; i_debug = i_debug + 1) begin
                assign rd_addr_debug[i_debug] = reserv_arr[i_debug].rd_addr;
                assign rd_exist_debug[i_debug] = reserv_arr[i_debug].rd_exist;
                assign rd_ROB_tag_debug[i_debug] = reserv_arr[i_debug].rd_ROB_tag;
                assign rs1_addr_debug[i_debug] = reserv_arr[i_debug].rs1_addr;
                assign rs1_tag_debug[i_debug] = reserv_arr[i_debug].rs1_tag;
                assign rs1_exist_debug[i_debug] = reserv_arr[i_debug].rs1_exist;
                assign rs1_busy_debug[i_debug] = reserv_arr[i_debug].rs1_busy;
                assign rs2_addr_debug[i_debug] = reserv_arr[i_debug].rs2_addr;
                assign rs2_tag_debug[i_debug] = reserv_arr[i_debug].rs2_tag;
                assign rs2_exist_debug[i_debug] = reserv_arr[i_debug].rs2_exist;
                assign rs2_busy_debug[i_debug] = reserv_arr[i_debug].rs2_busy;
                assign instr_debug[i_debug] = reserv_arr[i_debug].instr;
                assign busy_debug[i_debug] = reserv_arr[i_debug].busy;
            end
        endgenerate
    `endif
    
    generate
        genvar i_busy;
        for (i_busy = 0; i_busy < NO_RESERV; i_busy++) begin
            assign busy_vec[i_busy] = reserv_arr[i_busy].busy;
        end
    endgenerate
    
    assign all_busy = &busy_vec;

    always_comb begin
        write_idx   = '0;
        write_valid = 1'b0;
    
        for (int i = (NO_RESERV-1); i >= 0; i--) begin
            if (!reserv_arr[i].busy) begin
                if (i == 0) begin
                    write_idx   = 0;
                    write_valid = 1'b1;
                    break;
                end
                else if (reserv_arr[i-1].busy) begin
                    write_idx   = i;
                    write_valid = 1'b1;
                    break;
                end
            end
        end
    end

    always_ff @(negedge clk, negedge rst_n) begin
        if (~rst_n) begin
            reserv_arr <= '{default: '0};
        end
        else begin
            // 1) WRITE NEW ENTRY (ưu tiên index lớn nhất) ----
            if (en & write_valid & ~stall) begin
                // khi ghi, nếu rd_clr cùng cycle và addr trùng, clear rs?_busy ngay
                reserv_arr[write_idx].rd_addr    <= rd_addr_i;
                reserv_arr[write_idx].rd_exist   <= rd_exist_i;
                reserv_arr[write_idx].rd_ROB_tag <= rd_ROB_tag_i;
    
                reserv_arr[write_idx].rs1_addr   <= rs1_addr_i;
                reserv_arr[write_idx].rs1_tag    <= rs1_tag_i;
                reserv_arr[write_idx].rs1_exist  <= rs1_exist_i;
                reserv_arr[write_idx].rs1_busy   <= rs1_busy_i & rs1_exist_i
                                                   & !(rd_clr     & (rs1_addr_i == rd_addr_clr) & (rs1_tag_i == rd_ROB_clr))
                                                   & !(rd_FPU_clr & (rs1_addr_i == rd_addr_FPU_clr) & (rs1_tag_i == rd_ROB_FPU_clr));
    
                reserv_arr[write_idx].rs2_addr   <= rs2_addr_i;
                reserv_arr[write_idx].rs2_tag    <= rs2_tag_i;
                reserv_arr[write_idx].rs2_exist  <= rs2_exist_i;
                reserv_arr[write_idx].rs2_busy   <= rs2_busy_i & rs2_exist_i
                                                   & !(rd_clr     & (rs2_addr_i == rd_addr_clr) & (rs2_tag_i == rd_ROB_clr))
                                                   & !(rd_FPU_clr & (rs2_addr_i == rd_addr_FPU_clr) & (rs2_tag_i == rd_ROB_FPU_clr));
    
                reserv_arr[write_idx].instr      <= instr_i;
                reserv_arr[write_idx].busy       <= 1'b1;
            end

            // 2) WAKE-UP (CDB clear) cho các entry hiện có (không ghi) ----
            if (rd_clr) begin
                for (int i = 0; i < NO_RESERV; i++) begin
                    if (reserv_arr[i].busy) begin
                        if (reserv_arr[i].rs1_exist & reserv_arr[i].rs1_busy & (reserv_arr[i].rs1_addr == rd_addr_clr) & (reserv_arr[i].rs1_tag == rd_ROB_clr)) begin
                            reserv_arr[i].rs1_busy <= 1'b0;
                        end
    
                        if (reserv_arr[i].rs2_exist & reserv_arr[i].rs2_busy & (reserv_arr[i].rs2_addr == rd_addr_clr) & (reserv_arr[i].rs2_tag == rd_ROB_clr)) begin
                            reserv_arr[i].rs2_busy <= 1'b0;
                        end
                    end
                end
            end

            if (rd_FPU_clr) begin
                for (int i = 0; i < NO_RESERV; i++) begin
                    if (reserv_arr[i].busy) begin
                        if (reserv_arr[i].rs1_busy & reserv_arr[i].rs1_exist & (reserv_arr[i].rs1_addr == rd_addr_FPU_clr) & (reserv_arr[i].rs1_tag == rd_ROB_FPU_clr)) begin
                            reserv_arr[i].rs1_busy <= 1'b0;
                        end

                        if (reserv_arr[i].rs2_busy & reserv_arr[i].rs2_exist & (reserv_arr[i].rs2_addr == rd_addr_FPU_clr) & (reserv_arr[i].rs2_tag == rd_ROB_FPU_clr)) begin
                            reserv_arr[i].rs2_busy <= 1'b0;
                        end
                    end
                end
            end
    
            // 3) ISSUE CLEAR (clear entry that was issued last cycle)
            if (read_valid & (~stall | all_busy) & ~hold) begin
                reserv_arr[read_idx] <= '0;
            end
        end
    end

    always_comb begin
        instr_o       = '0;
        read_idx      = 3'd0;
        read_valid    = 1'b0;
        wr_addr_tag_o = '0;
        rs1_tag_o     = '0;
        rs1_addr_o    = '0;
        rs2_tag_o     = '0;
        rs2_addr_o    = '0;

        for (int i = 0; i < NO_RESERV; i++) begin
            if (reserv_arr[i].busy & ~reserv_arr[i].rs1_busy & ~reserv_arr[i].rs2_busy) begin
                instr_o       = reserv_arr[i].instr;
                wr_addr_tag_o = (reserv_arr[i].rd_exist == 1'b1) ? reserv_arr[i].rd_ROB_tag : 5'd0;
                rs1_tag_o     = (reserv_arr[i].rs1_exist == 1'b1) ? reserv_arr[i].rs1_addr : 5'd0;
                rs1_addr_o    = (reserv_arr[i].rs1_exist == 1'b1) ? reserv_arr[i].rs1_tag : 5'd0;
                rs2_tag_o     = (reserv_arr[i].rs2_exist == 1'b1) ? reserv_arr[i].rs2_addr : 5'd0;
                rs2_addr_o    = (reserv_arr[i].rs2_exist == 1'b1) ? reserv_arr[i].rs2_tag : 5'd0;
                read_idx      = i;
                read_valid    = 1'b1;
                break;
            end
        end
    end

endmodule: CPU_reservation_station
