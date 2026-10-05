module fp_shift_register #(
    parameter N = 18
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        has_cmd,
    // From hazard unit
    input  logic        enable,
    // From decode stage
    input  logic [4:0]  shift_reg_addr,  
    input  logic        reg_write_d,
    input  logic [4:0]  writeAddr_d,
    input  logic        ld_sel_d,
    input  logic        wb_sel_d,
    input  logic        wren_d,
    input  logic [19:0] opcode_d,
    input  logic [4:0]  rdAddr1_d,
    input  logic [4:0]  rdAddr2_d,
    input  logic [4:0]  rdAddr3_d,
    input  logic        bridge_wren_d,
    input  logic        bridge_rden_d,
    input  logic [4:0]  wr_addr_tag_D,

    // To memory access stage
    output logic        reg_write_e,
    output logic [4:0]  writeAddr_e,
    output logic        ld_sel_e,
    output logic        wb_sel_e,
    output logic        wren_e,
    output logic        bridge_wren_e,
    output logic [4:0]  wr_addr_tag_E,
    // To hazard unit
    output logic        occupied, 
    output logic        is_raw
);
    
    timeunit 1ns; timeprecision 1ps;

    logic have_raw, has_long_cmd;  
    
    typedef struct packed {
        logic [4:0]  wr_addr_tag;
        logic        reg_write;
        logic [4:0]  writeAddr;
        logic        ld_sel;
        logic        wb_sel;
        logic        wren;
        logic        bridge_wren;
        logic        long_cmd;
        logic        has_data;
    } reg_entry_t;

    reg_entry_t reg_array[N];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++) begin
                reg_array[i] <= '0;
            end
        end 
        else begin
            for (int i = 0; i < N-1; i++) begin
                reg_array[i] <= reg_array[i+1];
            end
            reg_array[N-1] <= '0; 
            
            if ((enable == 1'b1) & ~have_raw) begin
                if (reg_array[shift_reg_addr + 5'b00001].has_data == 1'b0) begin
                    reg_array[shift_reg_addr].wr_addr_tag <= wr_addr_tag_D;                                                               // 16 - 12
                    reg_array[shift_reg_addr].reg_write   <= reg_write_d;                                                                 // 11
                    reg_array[shift_reg_addr].writeAddr   <= writeAddr_d;                                                                 // 10 - 6
                    reg_array[shift_reg_addr].ld_sel      <= ld_sel_d;                                                                    // 5
                    reg_array[shift_reg_addr].wb_sel      <= wb_sel_d;                                                                    // 4
                    reg_array[shift_reg_addr].wren        <= wren_d;                                                                      // 3
                    reg_array[shift_reg_addr].bridge_wren <= bridge_wren_d;                                                               // 2
                    reg_array[shift_reg_addr].long_cmd    <= has_long_cmd;                                                                // 1
                    reg_array[shift_reg_addr].has_data    <= ({reg_write_d, writeAddr_d, ld_sel_d, wb_sel_d, wren_d} != 0) ? 1'b1 : 1'b0; // 0
                    for (int i = N-1; i > 0; i--) begin
                        if (i <= shift_reg_addr && ~reg_array[i].has_data) begin
                            reg_array[i - 1].long_cmd  <= has_long_cmd;
                            reg_array[i - 1].writeAddr <= writeAddr_d;
                        end
                    end
                end
            end
        end
    end
    
    assign reg_write_e   = (reg_array[0].has_data == 1'b1) ? reg_array[0].reg_write : '0;
    assign writeAddr_e   = (reg_array[0].has_data == 1'b1) ? reg_array[0].writeAddr : '0;
    assign ld_sel_e      = (reg_array[0].has_data == 1'b1) ? reg_array[0].ld_sel : '0;
    assign wb_sel_e      = (reg_array[0].has_data == 1'b1) ? reg_array[0].wb_sel : '0;
    assign wren_e        = (reg_array[0].has_data == 1'b1) ? reg_array[0].wren : '0;
    assign bridge_wren_e = (reg_array[0].has_data == 1'b1) ? reg_array[0].bridge_wren : '0;
    assign wr_addr_tag_E = (reg_array[0].has_data == 1'b1) ? reg_array[0].wr_addr_tag : '0;
    assign is_raw        = have_raw;
    assign has_long_cmd  = |opcode_d[19:11];
    
    always_comb begin
        if (~bridge_rden_d & (reg_array[shift_reg_addr + 5'd1].long_cmd == 1'b1) & ((reg_array[shift_reg_addr + 5'd1].writeAddr == rdAddr1_d) | ((reg_array[shift_reg_addr + 5'd1].writeAddr == rdAddr2_d) & (~|{opcode_d[11], opcode_d[7:2]} | wren_d)) | ((reg_array[shift_reg_addr + 5'd1].writeAddr == rdAddr3_d) & (|opcode_d[19:16])))) begin
            have_raw = 1'b1;
        end
        else if (~bridge_rden_d & (reg_array[3].writeAddr != '0) & ((reg_array[3].writeAddr == rdAddr1_d) | ((reg_array[3].writeAddr == rdAddr2_d) & (~|{opcode_d[11], opcode_d[7:2]} | wren_d)) | ((reg_array[3].writeAddr == rdAddr3_d) & (|opcode_d[19:16])))) begin
            have_raw = 1'b1;
        end
        else if (~bridge_rden_d & (reg_array[2].writeAddr != '0) & ((reg_array[2].writeAddr == rdAddr1_d) | ((reg_array[2].writeAddr == rdAddr2_d) & (~|{opcode_d[11], opcode_d[7:2]} | wren_d)) | ((reg_array[2].writeAddr == rdAddr3_d) & (|opcode_d[19:16])))) begin
            have_raw = 1'b1;
        end
        else if (~bridge_rden_d & (reg_array[1].writeAddr != '0) & ((reg_array[1].writeAddr == rdAddr1_d) | ((reg_array[1].writeAddr == rdAddr2_d) & (~|{opcode_d[11], opcode_d[7:2]} | wren_d)) | ((reg_array[1].writeAddr == rdAddr3_d) & (|opcode_d[19:16])))) begin
            have_raw = 1'b1;
        end
        else begin
            have_raw = 1'b0;
        end
    end

    always_comb begin
        if ((reg_array[shift_reg_addr + 5'b00001].has_data != 1'b0) && has_cmd) begin
            occupied = 1'b1;
        end
        else begin
            occupied = 1'b0;
        end
    end
    
endmodule
