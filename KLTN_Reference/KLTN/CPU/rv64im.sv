module rv64im #(parameter NO_RESERV = 16) (
    input  logic        clk_i, rst_ni,

    // ===== I-Memory access =====
    output logic [31:0] pc2cache_o,
    input  logic [31:0] cache_instr_i,
    input  logic        cache_i_ready_i,
    // ===========================

    // ===== D-Memory access =====
    output logic        mem_st_en,
    output logic        mem_ld_en,
    output logic [11:0] mem_addr,
    output logic [3:0]  mem_byte_en,
    output logic [2:0]  mem_ld_sel,
    output logic [63:0] mem_st_data,
    input  logic [63:0] mem_ld_data,
    // ===========================

    // ===== Bridge from CPU =====
    // ---- Address/Data bus ----
    input  logic        bridge_wren_i,
    input  logic [4:0]  bridge_wr_addr_i,
    input  logic [4:0]  bridge_wr_addr_tag_i,
    input  logic [63:0] bridge_wr_data_i,
    
    input  logic        bridge_rden_i,
    input  logic        bridge_rd_sel_i,
    input  logic [4:0]  bridge_rd_addr_i,
    output logic [63:0] bridge_rd_data_o,

    input  logic        bridge_CPU_dest_clr_i,
    input  logic        bridge_FPU_dest_clr_i,
    input  logic [4:0]  bridge_dest_addr_clr_i,
    input  logic [4:0]  bridge_dest_ROB_clr_i,
    
    // ---- Control state bus ----
    output logic [4:0]  bridge_fpu_current_wr_addr_tag_o,
    output logic        bridge_rs1_rf_sel_o,
    output logic        bridge_rs2_rf_sel_o,
    output logic        bridge_rs3_rf_sel_o,
    input  logic        bridge_fpu_busy_i,
    output logic        bridge_cpu_busy_o,
    output logic        bridge_cpu_br_flush_o,
    output logic [31:0] bridge_fpu_instr_o,
    output logic [4:0]  bridge_fpu_wr_addr_tag_o
    // ===========================
);
    timeunit 1ns; timeprecision 1ps;
    
    logic        br_equal, br_less, br_unsigned, mem_wrenD, mem_wrenE, mem_wrenM, op_a_selD, op_a_selE, op_b_selD, op_b_selE,
                 rd_wrenD, rd_wrenE, rd_wrenM, rd_wrenW, rd_wrenC, br_selD, br_selE, stallF, stallD, flushD, flushE, W_suffixD, W_suffixE, bridge_rdenE, ex_res_selD, ex_res_selE, dispatch_stall_req, wr_commit, fpu_wr_commit, wr_commitC, fpu_wr_commitC, bridge_wrenC, rs1_rf_sel, rs2_rf_sel, rs1_rf_selD, rs2_rf_selD, bridge_wrenW;
    logic        mem_ldenM, mem_ldenE, mem_ldenD;
    logic  [1:0] wb_selD, wb_selE, wb_selM, wb_selW, rs1d_sel, rs2d_sel, bridge_rddata_sel, muldiv_opD, muldiv_modeD, muldiv_opE, muldiv_modeE;
    logic  [2:0] ld_selD, ld_selE, ld_selM, forward1sel, forward2sel;
    logic  [3:0] byte_enD, byte_enE, byte_enM, alu_opD, alu_opE;
    logic  [4:0] rs1_addrD, rs1_addrE, rs2_addrD, rs2_addrE, rd_addrD, rd_addrE, rd_addrM, rd_addrW, rd_addrC, bridge_rd_addrE;
    logic  [4:0] wr_addr_tagF, wr_addr_tagD, wr_addr_tagE, wr_addr_tagM, wr_addr_tagW, current_wr_addr_tag, bridge_wr_addrW, bridge_wr_addrC;
    logic [12:0] next_pc, pcF, pc4F, pcD, pc4D, pcE, pc4E, pc4M, pc4W;
    logic [31:0] instrF, instrD, issue_to_CPU;
    logic [63:0] operand_a, operand_b, forward1out, forward2out, immE, rs1_dataE, rs2_dataE, alu_dataE, muldiv_dataE, ex_resE, alu_dataM, ld_dataM, forward2outM, rs1_dataD, rs2_dataD, wb_data, wb_dataC, immD, rs1d_out, rs2d_out, alu_dataW, ld_dataW, bridge_rd_rf_dataD, bridge_rd_rf_dataE, bridge_wr_dataW, bridge_wr_dataC;

    `ifdef DEBUG_EN
        logic [63:0] CPU_command;
        logic [63:0] FPU_command;
        logic [63:0] command;
        always_comb begin
            unique case (issue_to_CPU[6:0])
                7'b0110111: begin
                    CPU_command = "LUI";
                end 
                7'b0010111: begin
                    CPU_command = "AUIPC";
                end
                7'b1101111: begin
                    CPU_command = "JAL";
                end
                7'b1100111: begin
                    CPU_command = "JALR";
                end
                7'b1100011: begin
                    unique case (issue_to_CPU[14:12])
                        'd0: begin
                            CPU_command = "BEQ";
                        end 
                        'd1: begin
                            CPU_command = "BNE";
                        end
                        'd4: begin
                            CPU_command = "BLT";
                        end
                        'd5: begin
                            CPU_command = "BGE";
                        end
                        'd6: begin
                            CPU_command = "BLTU";
                        end
                        'd7: begin
                            CPU_command = "BGEU";
                        end
                        default: begin
                            CPU_command = "-";
                        end
                    endcase
                end
                7'b0000011: begin
                    unique case (issue_to_CPU[14:12])
                        'd0: begin
                            CPU_command = "LB";
                        end 
                        'd1: begin
                            CPU_command = "LH";
                        end
                        'd2: begin
                            CPU_command = "LW";
                        end
                        'd3: begin
                            CPU_command = "LD";
                        end
                        'd4: begin
                            CPU_command = "LBU";
                        end
                        'd5: begin
                            CPU_command = "LHU";
                        end
                        'd6: begin
                            CPU_command = "LWU";
                        end
                        default: begin
                            CPU_command = "-";
                        end
                    endcase
                end
                7'b0100011: begin
                    unique case (issue_to_CPU[14:12])
                        'd0: begin
                            CPU_command = "SB";
                        end 
                        'd1: begin
                            CPU_command = "SH";
                        end
                        'd2: begin
                            CPU_command = "SW";
                        end
                        'd3: begin
                            CPU_command = "SD";
                        end
                        default: begin
                            CPU_command = "-";
                        end
                    endcase
                end
                7'b0010011: begin
                    unique case (issue_to_CPU[14:12])
                        'd0: begin
                            CPU_command = "ADDI";
                        end
                        'd1: begin
                            CPU_command = "SLLI";
                        end
                        'd2: begin
                            CPU_command = "SLTI";
                        end
                        'd3: begin
                            CPU_command = "SLTIU";
                        end
                        'd4: begin
                            CPU_command = "XORI";
                        end
                        'd5: begin
                            if (issue_to_CPU[30]) begin
                                CPU_command = "SRAI";
                            end
                            else begin
                                CPU_command = "SRLI";
                            end
                        end
                        'd6: begin
                            CPU_command = "ORI";
                        end
                        'd7: begin
                            CPU_command = "ANDI";
                        end
                        default: begin
                            CPU_command = "-";
                        end 
                    endcase
                end
                7'b0110011: begin
                    if (issue_to_CPU[25]) begin
                        unique case (issue_to_CPU[14:12])
                            'd0: begin
                                CPU_command = "MUL";
                            end
                            'd1: begin
                                CPU_command = "MULH";
                            end
                            'd2: begin
                                CPU_command = "MULHSU";
                            end
                            'd3: begin
                                CPU_command = "MULHU";
                            end
                            'd4: begin
                                CPU_command = "DIV";
                            end
                            'd5: begin
                                CPU_command = "DIVU";
                            end
                            'd6: begin
                                CPU_command = "REM";
                            end
                            'd7: begin
                                CPU_command = "REMU";
                            end
                            default: begin
                                CPU_command = "-";
                            end
                        endcase
                    end
                    else begin
                        unique case (issue_to_CPU[14:12])
                            'd0: begin
                                if (issue_to_CPU[30]) begin
                                    CPU_command = "SUB";
                                end
                                else begin
                                    CPU_command = "ADD";
                                end
                            end
                            'd1: begin
                                CPU_command = "SLL";
                            end
                            'd2: begin
                                CPU_command = "SLT";
                            end
                            'd3: begin
                                CPU_command = "SLTU";
                            end
                            'd4: begin
                                CPU_command = "XOR";
                            end
                            'd5: begin
                                if (issue_to_CPU[30]) begin
                                    CPU_command = "SRA";
                                end
                                else begin
                                    CPU_command = "SRL";
                                end
                            end
                            'd6: begin
                                CPU_command = "OR";
                            end
                            'd7: begin
                                CPU_command = "AND";
                            end
                            default: begin
                                CPU_command = "-";
                            end
                        endcase
                    end
                end
                7'b0011011: begin
                    unique case (issue_to_CPU[14:12])
                        'd0: begin
                            CPU_command = "ADDIW";
                        end 
                        'd1: begin
                            CPU_command = "SLLIW";
                        end
                        'd5: begin
                            if (issue_to_CPU[30]) begin
                                CPU_command = "SRAIW";
                            end
                            else begin
                                CPU_command = "SRLIW";
                            end
                        end
                        default: begin
                            CPU_command = "-";
                        end
                    endcase
                end
                7'b0111011: begin
                    unique case (issue_to_CPU[14:12])
                        'd0: begin
                            if (issue_to_CPU[25]) begin
                                CPU_command = "MULW";
                            end
                            else begin
                                if (issue_to_CPU[30]) begin
                                    CPU_command = "SUBW";
                                end
                                else begin
                                    CPU_command = "ADDW";
                                end
                            end
                        end
                        'd1: begin
                            CPU_command = "SLLW";
                        end
                        'd4: begin
                            CPU_command = "DIVW";
                        end
                        'd5: begin
                            if (issue_to_CPU[25]) begin
                                CPU_command = "DIVUW";
                            end
                            else begin
                                if (issue_to_CPU[30]) begin
                                    CPU_command = "SRAW";
                                end
                                else begin
                                    CPU_command = "SRLW";
                                end
                            end
                        end
                        'd6: begin
                            CPU_command = "REMW";
                        end
                        'd7: begin
                            CPU_command = "REMUW";
                        end
                        default: begin
                            CPU_command = "-";
                        end
                    endcase
                end
                7'b1111111: begin
                    CPU_command = "NOP";
                end
                default: begin
                    CPU_command = "-";
                end
            endcase
        end

        always_comb begin
            unique case (bridge_fpu_instr_o[6:0])
                7'b0000111: begin
                    FPU_command = "FLD";
                end 
                7'b0100111: begin
                    FPU_command = "FSD";
                end
                7'b1000011: begin
                    FPU_command = "FMADD";
                end
                7'b1000111: begin
                    FPU_command = "FMSUB";
                end
                7'b1001011: begin
                    FPU_command = "FNMSUB";
                end
                7'b1001111: begin
                    FPU_command = "FNMADD";
                end
                7'b1010011: begin
                    unique case (bridge_fpu_instr_o[31:25])
                        7'b0000001: begin
                            FPU_command = "FADD";
                        end 
                        7'b0000101: begin
                            FPU_command = "FSUB";
                        end
                        7'b0001001: begin
                            FPU_command = "FMUL";
                        end
                        7'b0001101: begin
                            FPU_command = "FDIV";
                        end
                        7'b0101101: begin
                            FPU_command = "FSQRT";
                        end
                        7'b0010001: begin
                            if (bridge_fpu_instr_o[14:12] == 'd0) begin
                                FPU_command = "FSGNJ";
                            end
                            else if (bridge_fpu_instr_o[14:12] == 'd1) begin
                                FPU_command = "FSGNJN";
                            end
                            else if (bridge_fpu_instr_o[14:12] == 'd2) begin
                                FPU_command = "FSGNJX";
                            end
                            else begin
                                FPU_command = "-";
                            end
                        end
                        7'b0010101: begin
                            if (bridge_fpu_instr_o[14:12] == 'd0) begin
                                FPU_command = "FMIN";
                            end
                            else if (bridge_fpu_instr_o[14:12] == 'd1) begin
                                FPU_command = "FMAX";
                            end
                            else begin
                                FPU_command = "-";
                            end
                        end
                        7'b0100000: begin
                            FPU_command = "FCVT.S.D";
                        end
                        7'b0100001: begin
                            FPU_command = "FCVT.D.S";
                        end
                        7'b1010001: begin
                            if (bridge_fpu_instr_o[14:12] == 'd0) begin
                                FPU_command = "FLE";
                            end
                            else if (bridge_fpu_instr_o[14:12] == 'd1) begin
                                FPU_command = "FLT";
                            end
                            else if (bridge_fpu_instr_o[14:12] == 'd2) begin
                                FPU_command = "FEQ";
                            end
                            else begin
                                FPU_command = "-";
                            end
                        end
                        7'b1110001: begin
                            if (bridge_fpu_instr_o[12]) begin
                                FPU_command = "FCLASS";
                            end
                            else begin
                                FPU_command = "FMV.X.D";
                            end
                        end
                        7'b1100001: begin
                            if (bridge_fpu_instr_o[21:20] == 2'b01) begin
                                FPU_command = "FCVT.WU.D";
                            end
                            else if (bridge_fpu_instr_o[21:20] == 2'b00) begin
                                FPU_command = "FCVT.W.D";
                            end
                            else if (bridge_fpu_instr_o[21:20] == 2'b10) begin
                                FPU_command = "FCVT.L.D";
                            end
                            else begin
                                FPU_command = "FCVT.LU.D";
                            end
                        end
                        7'b1101001: begin
                            if (bridge_fpu_instr_o[21:20] == 2'b01) begin
                                FPU_command = "FCVT.D.WU";
                            end
                            else if (bridge_fpu_instr_o[21:20] == 2'b00) begin
                                FPU_command = "FCVT.D.W";
                            end
                            else if (bridge_fpu_instr_o[21:20] == 2'b10) begin
                                FPU_command = "FCVT.D.L";
                            end
                            else begin
                                FPU_command = "FCVT.D.LU";
                            end
                        end
                        7'b1111001: begin
                            FPU_command = "FMV.D.X";
                        end
                        default: begin
                            FPU_command = "-";
                        end
                    endcase
                end
                7'b1111111: begin
                    FPU_command = "NOP";
                end
                default: begin
                    FPU_command = "-";
                end
            endcase
        end

        always_comb begin
            if ((FPU_command == "-") & (CPU_command == "-")) begin
                command = "-";
            end
            else if ((FPU_command != "-") & (CPU_command == "-")) begin
                command = FPU_command;
            end
            else if ((FPU_command == "-") & (CPU_command != "-")) begin
                command = CPU_command;
            end
            else begin
                command = "INVALID";
            end
        end
    `endif

    br_mux brsel (.br_sel(br_selE),
                  .alu_data(ex_resE[12:0]),
                  .pc_four(pc4F),
                  .next_pc(next_pc));

    pc_reg fetch_address (.clk(clk_i),
                          .rstn(rst_ni),
                          .en(!stallF),
                          .cache_ready_i(cache_i_ready_i),
                          .next_pc(next_pc),
                          .pc(pcF));

    add4 plus4 (.pc_in(pcF),
                .pc_out(pc4F));

    assign pc2cache_o = {9'd0, pcF};
    assign instrF   = (cache_i_ready_i) ? cache_instr_i : 32'h0000007F;

    dispatch #(.NO_RESERV(NO_RESERV)) dispatcher (.clk(clk_i),
                                                  .rst_n(rst_ni),
                                                  .instr_f(instrF),
                                                  .stall_f(stallF),
                                                  .reg_write_CPU(rd_wrenE),
                                                  .reg_addr_CPU(rd_addrE),
                                                  .reg_ROB_CPU(wr_addr_tagE),
                                                  .bridge_CPU_reg_write(bridge_CPU_dest_clr_i),
                                                  .bridge_FPU_reg_write(bridge_FPU_dest_clr_i),
                                                  .bridge_reg_addr(bridge_dest_addr_clr_i),
                                                  .bridge_reg_ROB(bridge_dest_ROB_clr_i),
                                                  .instr_CPU(issue_to_CPU),
                                                  .instr_FPU(bridge_fpu_instr_o),
                                                  .wr_addr_tag_CPU(wr_addr_tagF),
                                                  .wr_addr_tag_FPU(bridge_fpu_wr_addr_tag_o),
                                                  .rs1_rf_sel_CPU(rs1_rf_sel),
                                                  .rs2_rf_sel_CPU(rs2_rf_sel),
                                                  .rs1_rf_sel_FPU(bridge_rs1_rf_sel_o),
                                                  .rs2_rf_sel_FPU(bridge_rs2_rf_sel_o),
                                                  .rs3_rf_sel_FPU(bridge_rs3_rf_sel_o),
                                                  .stall(dispatch_stall_req),
                                                  .rd_addrW_CPU((bridge_wrenW) ? bridge_wr_addrW : rd_addrW),
                                                  .current_wr_addr_tag_CPU(current_wr_addr_tag),
                                                  .rd_addrW_FPU(bridge_wr_addrW),
                                                  .current_wr_addr_tag_FPU(bridge_fpu_current_wr_addr_tag_o));

    reg_fetch_decode decode (.clk(clk_i),
                             .sclr(flushD),
                             .aclr(rst_ni),
                             .en(!stallD),
                             .instrF(issue_to_CPU),
                             .wr_addr_tagF(wr_addr_tagF),
                             .rs1_rf_selF(rs1_rf_sel),
                             .rs2_rf_selF(rs2_rf_sel),
                             .pcF(pcF),
                             .pc4F(pc4F),
                             .instrD(instrD),
                             .wr_addr_tagD(wr_addr_tagD),
                             .rs1_rf_selD(rs1_rf_selD),
                             .rs2_rf_selD(rs2_rf_selD),
                             .pcD(pcD),
                             .pc4D(pc4D));

    reg_dec regdec (.instr(instrD),
                    .rs1_addr(rs1_addrD),
                    .rs2_addr(rs2_addrD),
                    .rd_addr(rd_addrD));

    immGen iG (.instr(instrD),
               .imm(immD));

    brcomp brc (.rs1_data(rs1d_out),
                .rs2_data(rs2d_out),
                .br_unsigned(br_unsigned),
                .br_less(br_less),
                .br_equal(br_equal));

    ctrl_unit cu (.instr(instrD),
                  .br_less(br_less),
                  .br_equal(br_equal),
                  .br_sel(br_selD),
                  .rd_wren(rd_wrenD),
                  .br_unsigned(br_unsigned),
                  .op_a_sel(op_a_selD),
                  .op_b_sel(op_b_selD),
                  .mem_wren(mem_wrenD),
                  .mem_lden(mem_ldenD),
                  .alu_op(alu_opD),
                  .W_suffix(W_suffixD),
                  .byte_en(byte_enD),
                  .wb_sel(wb_selD),
                  .ld_sel(ld_selD),
                  .muldiv_op(muldiv_opD),
                  .muldiv_mode(muldiv_modeD),
                  .ex_res_sel(ex_res_selD));

    regfile rf (.clk_i(clk_i),
                .rst_ni(rst_ni),
                .rs1_addr(rs1_addrD),
                .rs1_rf_sel(rs1_rf_selD),
                .rs2_addr(rs2_addrD),
                .rs2_rf_sel(rs2_rf_selD),
                .rd_addr(rd_addrC),
                .rd_data(wb_dataC),
                .rd_wren(rd_wrenC),
                .rd_commit(wr_commitC),
                .rs1_data(rs1_dataD),
                .rs2_data(rs2_dataD),
                .bridge_wren_i(bridge_wrenC),
                .bridge_wr_commit_i(fpu_wr_commitC),
                .bridge_wr_addr_i(bridge_wr_addrC),
                .bridge_wr_data_i(bridge_wr_dataC),
                .bridge_rden_i(bridge_rden_i),
                .bridge_rd_sel_i(bridge_rd_sel_i),
                .bridge_rd_addr_i(bridge_rd_addr_i),
                .bridge_rd_data_o(bridge_rd_rf_dataD)
                );

    rs1d_mux rd1m (.rs1_dataD(rs1_dataD),
                   .alu_dataE(ex_resE),
                   .alu_dataM(alu_dataM),
                   .ld_dataM(ld_dataM),
                   .rs1d_sel(rs1d_sel),
                   .rs1d_out(rs1d_out));

    rs2d_mux rd2m (.rs2_dataD(rs2_dataD),
                   .alu_dataE(ex_resE),
                   .alu_dataM(alu_dataM),
                   .ld_dataM(ld_dataM),
                   .rs2d_sel(rs2d_sel),
                   .rs2d_out(rs2d_out));

    reg_decode_execute execute (.clk(clk_i),
                                .sclr(flushE),
                                .aclr(rst_ni),
                                .mem_wrenD(mem_wrenD),
                                .mem_ldenD(mem_ldenD),
                                .op_a_selD(op_a_selD),
                                .op_b_selD(op_b_selD),
                                .rd_wrenD(rd_wrenD),
                                .br_selD(br_selD),
                                .wb_selD(wb_selD),
                                .ld_selD(ld_selD),
                                .byte_enD(byte_enD),
                                .alu_opD(alu_opD),
                                .rs1_addrD(rs1_addrD),
                                .rs2_addrD(rs2_addrD),
                                .rd_addrD(rd_addrD),
                                .pcD(pcD),
                                .pc4D(pc4D),
                                .immD(immD),
                                .wr_addr_tagD(wr_addr_tagD),
                                .rs1_dataD(rs1_dataD),
                                .rs2_dataD(rs2_dataD),
                                .bridge_rdenD(bridge_rden_i),
                                .bridge_rd_addrD(bridge_rd_addr_i),
                                .bridge_rd_rf_dataD(bridge_rd_rf_dataD),
                                .W_suffixD(W_suffixD),
                                .muldiv_opD(muldiv_opD),
                                .muldiv_modeD(muldiv_modeD),
                                .ex_res_selD(ex_res_selD),
                                .mem_wrenE(mem_wrenE),
                                .mem_ldenE(mem_ldenE),
                                .op_a_selE(op_a_selE),
                                .op_b_selE(op_b_selE),
                                .rd_wrenE(rd_wrenE),
                                .br_selE(br_selE),
                                .wb_selE(wb_selE),
                                .ld_selE(ld_selE),
                                .byte_enE(byte_enE),
                                .alu_opE(alu_opE),
                                .rs1_addrE(rs1_addrE),
                                .rs2_addrE(rs2_addrE),
                                .rd_addrE(rd_addrE),
                                .pcE(pcE),
                                .pc4E(pc4E),
                                .immE(immE),
                                .wr_addr_tagE(wr_addr_tagE),
                                .rs1_dataE(rs1_dataE),
                                .rs2_dataE(rs2_dataE),
                                .bridge_rdenE(bridge_rdenE),
                                .bridge_rd_addrE(bridge_rd_addrE),
                                .bridge_rd_rf_dataE(bridge_rd_rf_dataE),
                                .W_suffixE(W_suffixE),
                                .muldiv_opE(muldiv_opE),
                                .muldiv_modeE(muldiv_modeE),
                                .ex_res_selE(ex_res_selE));

    forward1mux f1m (.rs1_dataE(rs1_dataE),
                     .alu_dataM(alu_dataM),
                     .wb_data(wb_data),
                     .wb_dataC(wb_dataC),
                     .bridge_wr_dataM(bridge_wr_data_i),
                     .bridge_wr_dataW(bridge_wr_dataW),
                     .bridge_wr_dataC(bridge_wr_dataC),
                     .forward1sel(forward1sel),
                     .forward1out(forward1out));

    forward2mux f2m (.rs2_dataE(rs2_dataE),
                     .alu_dataM(alu_dataM),
                     .wb_data(wb_data),
                     .wb_dataC(wb_dataC),
                     .bridge_wr_dataM(bridge_wr_data_i),
                     .bridge_wr_dataW(bridge_wr_dataW),
                     .bridge_wr_dataC(bridge_wr_dataC),
                     .forward2sel(forward2sel),
                     .forward2out(forward2out));

    op_a_mux oam (.pc(pcE),
                  .rs1_data(forward1out),
                  .op_a_sel(op_a_selE),
                  .operand_a(operand_a));

    op_b_mux obm (.imm(immE),
                  .rs2_data(forward2out),
                  .op_b_sel(op_b_selE),
                  .operand_b(operand_b));

    alu al (.operand_a(operand_a),
            .operand_b(operand_b),
            .alu_op(alu_opE),
            .W_suffix(W_suffixE),
            .alu_data(alu_dataE));

    mul_div_top mul_div (
        .opcode(muldiv_opE),
        .mode(muldiv_modeE),
        .W_suffix(W_suffixE),
        .inp_a(operand_a),
        .inp_b(operand_b),
        .res(muldiv_dataE)
    );

    ex_res_mux ex_res_mux (
        .ex_res_sel(ex_res_selE),
        .alu_res(alu_dataE),
        .muldiv_res(muldiv_dataE),
        .ex_res(ex_resE));

    reg_execute_memory memory (.clk(clk_i),
                               .aclr(rst_ni),
                               .mem_wrenE(mem_wrenE),
                               .mem_ldenE(mem_ldenE),
                               .rd_wrenE(rd_wrenE),
                               .wb_selE(wb_selE),
                               .ld_selE(ld_selE),
                               .byte_enE(byte_enE),
                               .rd_addrE(rd_addrE),
                               .pc4E(pc4E),
                               .alu_dataE(ex_resE),
                               .forward2outE(forward2out),
                               .wr_addr_tagE(wr_addr_tagE),
                               .mem_wrenM(mem_wrenM),
                               .mem_ldenM(mem_ldenM),
                               .rd_wrenM(rd_wrenM),
                               .wb_selM(wb_selM),
                               .ld_selM(ld_selM),
                               .byte_enM(byte_enM),
                               .rd_addrM(rd_addrM),
                               .pc4M(pc4M),
                               .alu_dataM(alu_dataM),
                               .forward2outM(forward2outM),
                               .wr_addr_tagM(wr_addr_tagM));

    assign mem_st_en   = mem_wrenM;
    assign mem_ld_en   = mem_ldenM;
    assign mem_addr    = alu_dataM[11:0];
    assign mem_byte_en = byte_enM; 
    assign mem_ld_sel  = ld_selM;
    assign mem_st_data = forward2outM;
    assign ld_dataM    = mem_ld_data;

    reg_memory_writeback writeback (.clk(clk_i),
                                    .aclr(rst_ni),
                                    .rd_wrenM(rd_wrenM),
                                    .wb_selM(wb_selM),
                                    .rd_addrM(rd_addrM),
                                    .pc4M(pc4M),
                                    .alu_dataM(alu_dataM),
                                    .ld_dataM(ld_dataM),
                                    .wr_addr_tagM(wr_addr_tagM),
                                    .bridge_wrenM(bridge_wren_i),
                                    .bridge_wr_addrM(bridge_wr_addr_i),
                                    .bridge_wr_dataM(bridge_wr_data_i),
                                    .rd_wrenW(rd_wrenW),
                                    .wb_selW(wb_selW),
                                    .rd_addrW(rd_addrW),
                                    .pc4W(pc4W),
                                    .alu_dataW(alu_dataW),
                                    .ld_dataW(ld_dataW),
                                    .wr_addr_tagW(wr_addr_tagW),
                                    .bridge_wrenW(bridge_wrenW),
                                    .bridge_wr_addrW(bridge_wr_addrW),
                                    .bridge_wr_dataW(bridge_wr_dataW));

    wb_mux wbm (.pc_four(pc4W),
                .alu_data(alu_dataW),
                .ld_data(ld_dataW),
                .wb_sel(wb_selW),
                .wb_data(wb_data));

    tag_comparator tag_cmp (
        .wr_addr_tag(wr_addr_tagW),
        .fpu_wr_addr_tag(bridge_wr_addr_tag_i),
        .current_wr_addr_tag(current_wr_addr_tag),
        .wr_commit(wr_commit),
        .fpu_wr_commit(fpu_wr_commit)
    );

    reg_writeback_commit commit (.clk(clk_i),
                                 .aclr(rst_ni),
                                 .rd_wrenW(rd_wrenW),
                                 .rd_addrW(rd_addrW),
                                 .wb_dataW(wb_data),
                                 .wr_commitW(wr_commit),
                                 .fpu_wr_commitW(fpu_wr_commit),
                                 .bridge_wrenW(bridge_wrenW),
                                 .bridge_wr_addrW(bridge_wr_addrW),
                                 .bridge_wr_dataW(bridge_wr_dataW),
                                 .rd_wrenC(rd_wrenC),
                                 .rd_addrC(rd_addrC),
                                 .wb_dataC(wb_dataC),
                                 .wr_commitC(wr_commitC),
                                 .fpu_wr_commitC(fpu_wr_commitC),
                                 .bridge_wrenC(bridge_wrenC),
                                 .bridge_wr_addrC(bridge_wr_addrC),
                                 .bridge_wr_dataC(bridge_wr_dataC));

    hazard_unit hu (.br_selE(br_selE),
                    .wb_selE(wb_selE[0]),
                    .wb_selM(wb_selM[0]),
                    .rs1_addrD(rs1_addrD),
                    .rs2_addrD(rs2_addrD),
                    .rs1_addrE(rs1_addrE),
                    .rs2_addrE(rs2_addrE),
                    .rd_wrenD(rd_wrenD),
                    .rd_wrenE(rd_wrenE),
                    .rd_addrD(rd_addrD),
                    .rd_addrE(rd_addrE),
                    .rd_wrenM(rd_wrenM),
                    .rd_addrM(rd_addrM),
                    .rd_wrenW(rd_wrenW),
                    .rd_addrW(rd_addrW),
                    .rd_wrenC(rd_wrenC),
                    .rd_addrC(rd_addrC),
                    .bridge_wrenM(bridge_wren_i),
                    .bridge_wr_addrM(bridge_wr_addr_i),
                    .bridge_wrenW(bridge_wrenW),
                    .bridge_wr_addrW(bridge_wr_addrW),
                    .bridge_wrenC(bridge_wrenC),
                    .bridge_wr_addrC(bridge_wr_addrC),
                    .bridge_rd_addr_E(bridge_rd_addrE),
                    .bridge_rden_E(bridge_rdenE),
                    .bridge_rd_addr_D(bridge_rd_addr_i),
                    .bridge_rden_D(bridge_rden_i),
                    .fpu_busy(bridge_fpu_busy_i),
                    .dispatch_stall(dispatch_stall_req),
                    .stallF(stallF),
                    .stallD(stallD),
                    .flushD(flushD),
                    .flushE(flushE),
                    .forward1sel(forward1sel),
                    .forward2sel(forward2sel),
                    .rs1d_sel(rs1d_sel),
                    .rs2d_sel(rs2d_sel),
                    .bridge_rddata_sel(bridge_rddata_sel),
                    .busy(bridge_cpu_busy_o),
                    .br_flush(bridge_cpu_br_flush_o));

    bridgemux bridge_mux (.rf_data(bridge_rd_rf_dataE),
                          .alu_dataM(alu_dataM),
                          .wb_data(wb_data),
                          .wb_dataC(wb_dataC),
                          .bridge_rddata_sel(bridge_rddata_sel),
                          .bridge_rddata_out(bridge_rd_data_o));
endmodule