module fp_hazard_unit(
    // ---------- Decode stage ----------
    input logic         wren_d,
    input logic [19:0]  opcode_d,
    input logic [4:0]   rdAddr1_d,
    input logic [4:0]   rdAddr2_d,
    input logic [4:0]   rdAddr3_d,
    input logic         bridge_rden_d,
    // --------- Execute stage ----------
    input logic         wb_sel_e,
    input logic [19:0]  opcode_e,
    input logic [4:0]   rdAddr1_e,
    input logic [4:0]   rdAddr2_e,
    input logic [4:0]   rdAddr3_e,
    input logic [4:0]   writeAddr_e,
    input logic         wren_e,
    input logic         bridge_rden_e,
    // -------- Mem access stage --------
    input logic         reg_write_m,
    input logic [4:0]   writeAddr_m,
    input logic         bridge_wren_m,
    // -------- Write back stage --------
    input logic         reg_write_w,
    input logic [4:0]   writeAddr_w,
    input logic         bridge_wren_w,
    // ---------- Commit stage ----------  
    input logic         reg_write_c,
    input logic [4:0]   writeAddr_c,
    input logic         bridge_wren_c,
    // ------- Shift reg outputs --------
    input logic         occupied,
    input logic         is_raw,
    
    output logic        stall_i,
    output logic        stall_d,
    output logic        flush_e,
    output logic [1:0]  fwd1sel,
    output logic [1:0]  fwd2sel,
    output logic [1:0]  fwd3sel,
    output logic        shift_reg_en,
    output logic [1:0]  cpu_fwd
);
    timeunit 1ns; timeprecision 1ps;

    logic hazard, load_hazard;

    always_comb begin: stalling
        // ============ Stall between fdiv & fsqrt | 2 commands to mem at same time | Read after Write Hazard | Load-use stalling & bypassing ===========
        if (occupied | is_raw | load_hazard) begin
            hazard = 1'b1;
            shift_reg_en = 1'b0;
        end
        // =================== No stalling ===================
        else begin
            hazard = 1'b0;
            shift_reg_en = 1'b1;
        end
    end: stalling

    always_comb begin: forwarding
        if ((rdAddr1_e == writeAddr_m) & reg_write_m) begin
            fwd1sel = 2'b01;    // EX to EX
        end
        else if ((rdAddr1_e == writeAddr_w) & reg_write_w) begin
            fwd1sel = 2'b10;    // MEM to EX
        end
        else if ((rdAddr1_e == writeAddr_c) & reg_write_c) begin
            fwd1sel = 2'b11;    // WB to EX
        end
        else begin
            fwd1sel = 2'b00;    // No forwarding
        end

        if ((rdAddr2_e == writeAddr_m) & reg_write_m & (~|{opcode_e[11], opcode_e[7:2]} | wren_e)) begin
            fwd2sel = 2'b01;    // EX to EX
        end
        else if ((rdAddr2_e == writeAddr_w) & reg_write_w & (~|{opcode_e[11], opcode_e[7:2]} | wren_e)) begin
            fwd2sel = 2'b10;    // MEM to EX
        end
        else if ((rdAddr2_e == writeAddr_c) & reg_write_c & (~|{opcode_e[11], opcode_e[7:2]} | wren_e)) begin
            fwd2sel = 2'b11;    // WB to EX
        end
        else begin
            fwd2sel = 2'b00;    // No forwarding
        end

        if ((rdAddr3_e == writeAddr_m) & reg_write_m & |opcode_e[19:16]) begin
            fwd3sel = 2'b01;    // EX to EX
        end
        else if ((rdAddr3_e == writeAddr_w) & reg_write_w & |opcode_e[19:16]) begin
            fwd3sel = 2'b10;    // MEM to EX
        end
        else if ((rdAddr3_e == writeAddr_c) & reg_write_c & |opcode_e[19:16]) begin
            fwd3sel = 2'b11;    // WB to EX
        end
        else begin
            fwd3sel = 2'b00;    // No forwarding
        end

        if ((rdAddr1_e == writeAddr_m) & bridge_rden_e & bridge_wren_m) begin
            cpu_fwd = 2'b01;
        end
        else if ((rdAddr1_e == writeAddr_w) & bridge_rden_e & bridge_wren_w) begin
            cpu_fwd = 2'b10;
        end
        else if ((rdAddr1_e == writeAddr_c) & bridge_rden_e & bridge_wren_c) begin
            cpu_fwd = 2'b11;
        end
        else begin
            cpu_fwd = 2'b00;
        end
    end: forwarding

    assign load_hazard = wb_sel_e & ((rdAddr1_d == writeAddr_e) | ((rdAddr2_d == writeAddr_e) & (~|{opcode_d[11], opcode_d[7:2]} | wren_d)) | ((rdAddr3_d == writeAddr_e) & (|opcode_d[19:16]))) & ~bridge_rden_d;
    assign stall_i     = hazard;
    assign stall_d     = hazard;
    assign flush_e     = hazard;

endmodule: fp_hazard_unit