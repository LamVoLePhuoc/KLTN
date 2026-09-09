//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
//Date        : Tue May  5 00:24:49 2026
//Host        : Admin-PC running 64-bit major release  (build 9200)
//Command     : generate_target RV32IMFA_DualCore.bd
//Design      : RV32IMFA_DualCore
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "RV32IMFA_DualCore,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=RV32IMFA_DualCore,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=1,numReposBlks=1,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=1,numPkgbdBlks=0,bdsource=USER,da_clkrst_cnt=2,synth_mode=None}" *) (* HW_HANDOFF = "RV32IMFA_DualCore.hwdef" *) 
module RV32IMFA_DualCore
   (led_out_0,
    reset_rtl_0,
    sys_clock_0);
  output led_out_0;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.RESET_RTL_0 RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.RESET_RTL_0, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input reset_rtl_0;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.SYS_CLOCK_0 CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.SYS_CLOCK_0, CLK_DOMAIN RV32IMFA_DualCore_sys_clock_0, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input sys_clock_0;

  wire led_out_0;
  wire reset_rtl_0;
  wire sys_clock_0;

  RV32IMFA_DualCore_RV32IMFA_DualCore_Bo_0_0 RV32IMFA_DualCore_Bo_0
       (.led_out(led_out_0),
        .reset_rtl(reset_rtl_0),
        .sys_clock(sys_clock_0));
endmodule
