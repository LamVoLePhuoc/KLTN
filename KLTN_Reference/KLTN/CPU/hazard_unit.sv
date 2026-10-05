module hazard_unit(
    input       br_selE, wb_selE, wb_selM, rd_wrenD, rd_wrenE, rd_wrenM, rd_wrenW, rd_wrenC,
    input [4:0] rs1_addrD, rs2_addrD, rs1_addrE, rs2_addrE, rd_addrD, rd_addrE, rd_addrM, rd_addrW, rd_addrC,
    input [4:0] bridge_rd_addr_E, bridge_rd_addr_D,
    input       bridge_rden_E, bridge_rden_D,
    input       fpu_busy, dispatch_stall,
    input       bridge_wrenM,
    input [4:0] bridge_wr_addrM,
    input       bridge_wrenW,
    input [4:0] bridge_wr_addrW,
    input       bridge_wrenC,
    input [4:0] bridge_wr_addrC,
    output stallF, stallD, flushD, flushE,
    output logic [1:0] rs1d_sel, rs2d_sel, bridge_rddata_sel,
    output logic [2:0] forward1sel, forward2sel,
    output logic busy, br_flush
);
    timeunit 1ns; timeprecision 1ps;
    
    logic load_hazard;

    always_comb begin: cpu_hazard
        if (rs1_addrE != 5'b0) begin
            if ((rs1_addrE == rd_addrM) && rd_wrenM) begin 
                forward1sel = 3'b001;
            end
            else if ((rs1_addrE == bridge_wr_addrM) && bridge_wrenM) begin
                forward1sel = 3'b100;
            end
            else if ((rs1_addrE == rd_addrW) && rd_wrenW) begin 
                forward1sel = 3'b010;
            end
            else if ((rs1_addrE == bridge_wr_addrW) && bridge_wrenW) begin
                forward1sel = 3'b101;
            end
            else if ((rs1_addrE == rd_addrC) && rd_wrenC) begin 
                forward1sel = 3'b011;
            end
            else if ((rs1_addrE == bridge_wr_addrC) && bridge_wrenC) begin
                forward1sel = 3'b110;
            end
            else begin 
                forward1sel = 3'b000;
            end
        end
		else begin 
            forward1sel = 3'b000;
        end

        if (rs2_addrE != 5'b0) begin
            if ((rs2_addrE == rd_addrM) && rd_wrenM) begin 
                forward2sel = 3'b001;
            end
            else if ((rs2_addrE == bridge_wr_addrM) && bridge_wrenM) begin
                forward2sel = 3'b100;
            end
            else if ((rs2_addrE == rd_addrW) && rd_wrenW) begin 
                forward2sel = 3'b010;
            end
            else if ((rs2_addrE == bridge_wr_addrW) && bridge_wrenW) begin
                forward2sel = 3'b101;
            end
            else if ((rs2_addrE == rd_addrC) && rd_wrenC) begin 
                forward2sel = 3'b011;
            end
            else if ((rs2_addrE == bridge_wr_addrC) && bridge_wrenC) begin
                forward2sel = 3'b110;
            end
            else begin
                forward2sel = 3'b000;
            end
        end
		else begin 
            forward2sel = 3'b000;
        end
        
        if (rs1_addrD != 5'b0)
            if      ((rs1_addrD == rd_addrE) && rd_wrenE) rs1d_sel = 2'b01;
            else if ((rs1_addrD == rd_addrM) && rd_wrenM)
                if   (wb_selM)                            rs1d_sel = 2'b11;
                else                                      rs1d_sel = 2'b10;
            else                                          rs1d_sel = 2'b00;
		else                                              rs1d_sel = 2'b00;
        
        if (rs2_addrD != 5'b0)
            if      ((rs2_addrD == rd_addrE) && rd_wrenE) rs2d_sel = 2'b01;
            else if ((rs2_addrD == rd_addrM) && rd_wrenM)
                if   (wb_selM)                            rs2d_sel = 2'b11;
                else                                      rs2d_sel = 2'b10;
            else                                          rs2d_sel = 2'b00;
		else                                              rs2d_sel = 2'b00;
    end

    always_comb begin: bridge_hazard
        if (bridge_rd_addr_E != 5'b0) begin
            if ((bridge_rd_addr_E == rd_addrM) && rd_wrenM && bridge_rden_E) begin
                bridge_rddata_sel = 2'b01;
            end 
            else if ((bridge_rd_addr_E == rd_addrW) && rd_wrenW && bridge_rden_E) begin
                bridge_rddata_sel = 2'b10;
            end
            else if ((bridge_rd_addr_E == rd_addrC) && rd_wrenC && bridge_rden_E) begin
                bridge_rddata_sel = 2'b11;
            end
            else begin
                bridge_rddata_sel = 2'b00;
            end 
        end
        else begin
            bridge_rddata_sel = 2'b00; 
        end

        if (bridge_rd_addr_D != 5'b0) begin
            if ((bridge_rd_addr_D == rd_addrD) && rd_wrenD && bridge_rden_D) begin
                busy = 1'b1;
            end
            else if (wb_selE & (bridge_rd_addr_D == rd_addrE) & bridge_rden_D) begin
                busy = 1'b1;
            end
            else begin
                busy = 1'b0;
            end 
        end
        else begin
            busy = 1'b0;
        end
    end

    assign load_hazard = wb_selE & ((rs1_addrD == rd_addrE) | (rs2_addrD == rd_addrE));
    assign stallF      = load_hazard | fpu_busy | dispatch_stall;
    assign stallD      = load_hazard | fpu_busy;
    assign flushD      = br_selE;
    assign flushE      = load_hazard | br_selE;
    assign br_flush    = br_selE;

endmodule