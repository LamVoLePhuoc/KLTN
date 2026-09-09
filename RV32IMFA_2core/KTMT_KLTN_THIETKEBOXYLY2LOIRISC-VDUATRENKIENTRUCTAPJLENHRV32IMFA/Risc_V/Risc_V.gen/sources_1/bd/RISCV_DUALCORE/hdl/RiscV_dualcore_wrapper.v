//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
//Date        : Sun Mar 15 01:02:35 2026
//Host        : Admin-PC running 64-bit major release  (build 9200)
//Command     : generate_target RiscV_dualcore_wrapper.bd
//Design      : RiscV_dualcore_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module RiscV_dualcore_wrapper
   (reset_rtl,
    sys_clock);
  input reset_rtl;
  input sys_clock;

  wire reset_rtl;
  wire sys_clock;

  RiscV_dualcore RiscV_dualcore_i
       (.reset_rtl(reset_rtl),
        .sys_clock(sys_clock));
endmodule
