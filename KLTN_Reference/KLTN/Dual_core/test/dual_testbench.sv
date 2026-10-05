`include "../../FPU/lzc/lzc_wire.sv"
`include "../../FPU/lzc/lzc_4.sv"
`include "../../FPU/lzc/lzc_8.sv"
`include "../../FPU/lzc/lzc_16.sv"
`include "../../FPU/lzc/lzc_32.sv"
`include "../../FPU/lzc/lzc_64.sv"
`include "../../FPU/lzc/lzc_128.sv"
`include "../../FPU/lzc/lzc_256.sv"
`include "../../FPU/float/fp_wire.sv"
`include "../../FPU/float/fp_rnd.sv"
`include "../../FPU/float/fp_cmp.sv"
`include "../../FPU/float/fp_cvt.sv"
`include "../../FPU/float/fp_mac.sv"
`include "../../FPU/float/fp_fdiv.sv"
`include "../../FPU/float/fp_fma.sv"
`include "../../FPU/float/fp_max.sv"
`include "../../FPU/float/fp_sgnj.sv"
`include "../../FPU/float/fp_ext.sv"
`include "../../FPU/float/fp_exe.sv"
`include "../../FPU/float/fp_unit.sv"
`include "../../FPU/control_unit/fp_control_unit.sv"
`include "../../FPU/hazard_unit/fp_hazard_unit.sv"
`include "../../FPU/hazard_unit/fp_shift_register.sv"
`include "../../FPU/reg_file/fp_regfile.sv"
`include "../../FPU/registers/fp_reg_decode_execute.sv"
`include "../../FPU/registers/fp_reg_execute_mem.sv"
`include "../../FPU/registers/fp_reg_issue_decode.sv"
`include "../../FPU/registers/fp_reg_mem_wb.sv"
`include "../../FPU/registers/fp_reg_wb_commit.sv"
`include "../../FPU/top_module/mux2_1.sv"
`include "../../FPU/top_module/mux4_1.sv" 
`include "../../FPU/top_module/mux5_1.sv" 
`include "../../FPU/top_module/fp_adder.sv"
`include "../../FPU/top_module/fp_sign_extend.sv"
`include "../../FPU/top_module/fp_tag_comparator.sv"
`include "../../FPU/top_module/fp_bridge.sv"
`include "../../FPU/top_module/fp_top.sv"

`include "../../CPU/mul_div/twos_comp_128bit.sv"
`include "../../CPU/mul_div/twos_comp_64bit.sv"
// `include "../../CPU/mul_div/divider_64bit.sv"
`include "../../CPU/mul_div/multiplier.sv"
`include "../../CPU/mul_div/md_res_mux.sv"
`include "../../CPU/mul_div/mul_div_ctrl_unit.sv"
`include "../../CPU/mul_div/mul_div_top.sv"
`include "../../CPU/dispatch/arbiter.sv"
`include "../../CPU/dispatch/pre_decoder.sv"
`include "../../CPU/dispatch/ROB_counter.sv"
`include "../../CPU/dispatch/CPU_rs_tag_comparator.sv"
`include "../../CPU/dispatch/FPU_rs_tag_comparator.sv"
`include "../../CPU/dispatch/CPU_reg_manager.sv"
`include "../../CPU/dispatch/FPU_reg_manager.sv"
`include "../../CPU/dispatch/CPU_reservation_station.sv"
`include "../../CPU/dispatch/FPU_reservation_station.sv"
`include "../../CPU/dispatch/dispatch.sv"
`include "../../CPU/add4.sv"
`include "../../CPU/alu.sv"
`include "../../CPU/br_mux.sv"
`include "../../CPU/ex_res_mux.sv"
`include "../../CPU/brcomp.sv"
`include "../../CPU/ctrl_unit.sv"
`include "../../CPU/forward1mux.sv"
`include "../../CPU/forward2mux.sv"
`include "../../CPU/bridgemux.sv"
`include "../../CPU/hazard_unit.sv"
`include "../../CPU/immGen.sv"
`include "../../CPU/op_a_mux.sv"
`include "../../CPU/op_b_mux.sv"
`include "../../CPU/pc_reg.sv"
`include "../../CPU/reg_dec.sv"
`include "../../CPU/reg_decode_execute.sv"
`include "../../CPU/reg_execute_memory.sv"
`include "../../CPU/reg_fetch_decode.sv"
`include "../../CPU/reg_memory_writeback.sv"
`include "../../CPU/reg_writeback_commit.sv"
`include "../../CPU/regfile.sv"
`include "../../CPU/rs1d_mux.sv"
`include "../../CPU/rs2d_mux.sv"
`include "../../CPU/wb_mux.sv"
`include "../../CPU/tag_comparator.sv"
`include "../../CPU/rv64im.sv"

`include "../../MMU/TagArray.sv"
`include "../../MMU/Comparator.sv"
`include "../../MMU/DataArray.sv"
`include "../../MMU/D_Cache.sv"
`include "../../MMU/D_CacheController.sv"
`include "../../MMU/I_Cache.sv"
`include "../../MMU/I_CacheController.sv"
`include "../../MMU/MMU.sv"

`include "../../AXI_4/if_master.sv"
`include "../../AXI_4/if_slave.sv"

`include "../mem/sdram_wrapper.sv"

`include "../top_module/clk_divider.sv"
`include "../top_module/dual_core.sv"
`include "../top_module/dual_wrapper.sv"
`include "../top_module/dual_top.sv"

module dual_testbench;
    timeunit 1ns; timeprecision 1ps;
    
    localparam CLK_PERIOD = 4ns;

    logic sys_clk, reset;
    longint unsigned clock_counter;

    dual_top #(.NO_RESERV(16)) DUT (
        .clk(sys_clk),
        .rst_n(reset)
    );

    always #(CLK_PERIOD/2) sys_clk = ~sys_clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, dual_testbench);
        sys_clk = 1'b0;
        #(CLK_PERIOD) reset = 1'b1;
        #(CLK_PERIOD) reset = 1'b0;
        #(3*CLK_PERIOD) reset = 1'b1; 
       
        repeat (1000) begin
            @(posedge sys_clk);
        end
        $finish;
    end

    initial begin
        forever begin
            fork
                begin
                    @(posedge reset);
                    forever @(posedge sys_clk) begin
                        clock_counter++;
                    end
                end
                begin
                    @(negedge reset);
                    clock_counter = 0;
                end
            join_any
            disable fork;
        end
    end
endmodule
