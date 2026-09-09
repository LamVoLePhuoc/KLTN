//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
//Date        : Tue May  5 00:24:49 2026
//Host        : Admin-PC running 64-bit major release  (build 9200)
//Command     : generate_target RV32IMFA_DualCore_wrapper.bd
//Design      : RV32IMFA_DualCore_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module RV32IMFA_DualCore_wrapper
   (led_out_0,
    reset_rtl_0,
    sys_clock_0);
  output led_out_0;
  input reset_rtl_0;
  input sys_clock_0;

  wire led_out_0;
  wire reset_rtl_0;
  wire sys_clock_0;

  RV32IMFA_DualCore RV32IMFA_DualCore_i
       (.led_out_0(led_out_0),
        .reset_rtl_0(reset_rtl_0),
        .sys_clock_0(sys_clock_0));
endmodule
