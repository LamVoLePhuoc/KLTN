// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------
// This file contains confidential and proprietary information
// of AMD and is protected under U.S. and international copyright
// and other intellectual property laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// AMD, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) AMD shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or AMD had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// AMD products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of AMD products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
// DO NOT MODIFY THIS FILE.

// MODULE VLNV: xilinx.com:user:RV32IMFA_IP_Wrapper:1.0

`timescale 1ps / 1ps

`include "vivado_interfaces.svh"

module RV32IMFA_IP_Wrapper_0_sv (
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM" *)
  (* X_INTERFACE_MODE = "master M_AXI_DMEM" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI_DMEM, DATA_WIDTH 32, PROTOCOL AXI4, FREQ_HZ 100000000, ID_WIDTH 0, ADDR_WIDTH 32, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 0, HAS_PROT 0, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 2, NUM_WRITE_OUTSTANDING 2, MAX_BURST_LENGTH 256, PHASE 0.0, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0" *)
  vivado_aximm_v1_0.master M_AXI_DMEM,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_IMEM" *)
  (* X_INTERFACE_MODE = "master M_AXI_IMEM" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI_IMEM, DATA_WIDTH 32, PROTOCOL AXI4, FREQ_HZ 100000000, ID_WIDTH 0, ADDR_WIDTH 32, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_ONLY, HAS_BURST 1, HAS_LOCK 0, HAS_PROT 0, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 0, HAS_BRESP 0, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 2, NUM_WRITE_OUTSTANDING 2, MAX_BURST_LENGTH 256, PHASE 0.0, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0" *)
  vivado_aximm_v1_0.master M_AXI_IMEM,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire ACLK,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire ARESETN,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire [31:0] Snoop_Addr,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire Snoop_WE,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [31:0] ResultW,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [31:0] ALU_ResultE_Debug
);

  // interface wire assignments
  assign M_AXI_DMEM.ARCACHE = 0;
  assign M_AXI_DMEM.ARID = 0;
  assign M_AXI_DMEM.ARLOCK = 0;
  assign M_AXI_DMEM.ARPROT = 0;
  assign M_AXI_DMEM.ARQOS = 0;
  assign M_AXI_DMEM.ARREGION = 0;
  assign M_AXI_DMEM.ARUSER = 0;
  assign M_AXI_DMEM.AWCACHE = 0;
  assign M_AXI_DMEM.AWID = 0;
  assign M_AXI_DMEM.AWLOCK = 0;
  assign M_AXI_DMEM.AWPROT = 0;
  assign M_AXI_DMEM.AWQOS = 0;
  assign M_AXI_DMEM.AWREGION = 0;
  assign M_AXI_DMEM.AWUSER = 0;
  assign M_AXI_DMEM.WID = 0;
  assign M_AXI_DMEM.WUSER = 0;
  assign M_AXI_IMEM.ARCACHE = 0;
  assign M_AXI_IMEM.ARID = 0;
  assign M_AXI_IMEM.ARLOCK = 0;
  assign M_AXI_IMEM.ARPROT = 0;
  assign M_AXI_IMEM.ARQOS = 0;
  assign M_AXI_IMEM.ARREGION = 0;
  assign M_AXI_IMEM.ARUSER = 0;
  assign M_AXI_IMEM.AWADDR = 0;
  assign M_AXI_IMEM.AWBURST = 0;
  assign M_AXI_IMEM.AWCACHE = 0;
  assign M_AXI_IMEM.AWID = 0;
  assign M_AXI_IMEM.AWLEN = 0;
  assign M_AXI_IMEM.AWLOCK = 0;
  assign M_AXI_IMEM.AWPROT = 0;
  assign M_AXI_IMEM.AWQOS = 0;
  assign M_AXI_IMEM.AWREGION = 0;
  assign M_AXI_IMEM.AWSIZE = 0;
  assign M_AXI_IMEM.AWUSER = 0;
  assign M_AXI_IMEM.AWVALID = 0;
  assign M_AXI_IMEM.BREADY = 0;
  assign M_AXI_IMEM.WDATA = 0;
  assign M_AXI_IMEM.WID = 0;
  assign M_AXI_IMEM.WLAST = 0;
  assign M_AXI_IMEM.WSTRB = 0;
  assign M_AXI_IMEM.WUSER = 0;
  assign M_AXI_IMEM.WVALID = 0;

  RV32IMFA_IP_Wrapper_0 inst (
    .ACLK(ACLK),
    .ARESETN(ARESETN),
    .Snoop_Addr(Snoop_Addr),
    .Snoop_WE(Snoop_WE),
    .ResultW(ResultW),
    .ALU_ResultE_Debug(ALU_ResultE_Debug),
    .M_AXI_IMEM_ARADDR(M_AXI_IMEM.ARADDR),
    .M_AXI_IMEM_ARLEN(M_AXI_IMEM.ARLEN),
    .M_AXI_IMEM_ARSIZE(M_AXI_IMEM.ARSIZE),
    .M_AXI_IMEM_ARBURST(M_AXI_IMEM.ARBURST),
    .M_AXI_IMEM_ARVALID(M_AXI_IMEM.ARVALID),
    .M_AXI_IMEM_ARREADY(M_AXI_IMEM.ARREADY),
    .M_AXI_IMEM_RDATA(M_AXI_IMEM.RDATA),
    .M_AXI_IMEM_RRESP(M_AXI_IMEM.RRESP),
    .M_AXI_IMEM_RLAST(M_AXI_IMEM.RLAST),
    .M_AXI_IMEM_RVALID(M_AXI_IMEM.RVALID),
    .M_AXI_IMEM_RREADY(M_AXI_IMEM.RREADY),
    .M_AXI_DMEM_AWADDR(M_AXI_DMEM.AWADDR),
    .M_AXI_DMEM_AWLEN(M_AXI_DMEM.AWLEN),
    .M_AXI_DMEM_AWSIZE(M_AXI_DMEM.AWSIZE),
    .M_AXI_DMEM_AWBURST(M_AXI_DMEM.AWBURST),
    .M_AXI_DMEM_AWVALID(M_AXI_DMEM.AWVALID),
    .M_AXI_DMEM_AWREADY(M_AXI_DMEM.AWREADY),
    .M_AXI_DMEM_WDATA(M_AXI_DMEM.WDATA),
    .M_AXI_DMEM_WSTRB(M_AXI_DMEM.WSTRB),
    .M_AXI_DMEM_WLAST(M_AXI_DMEM.WLAST),
    .M_AXI_DMEM_WVALID(M_AXI_DMEM.WVALID),
    .M_AXI_DMEM_WREADY(M_AXI_DMEM.WREADY),
    .M_AXI_DMEM_BRESP(M_AXI_DMEM.BRESP),
    .M_AXI_DMEM_BVALID(M_AXI_DMEM.BVALID),
    .M_AXI_DMEM_BREADY(M_AXI_DMEM.BREADY),
    .M_AXI_DMEM_ARADDR(M_AXI_DMEM.ARADDR),
    .M_AXI_DMEM_ARLEN(M_AXI_DMEM.ARLEN),
    .M_AXI_DMEM_ARSIZE(M_AXI_DMEM.ARSIZE),
    .M_AXI_DMEM_ARBURST(M_AXI_DMEM.ARBURST),
    .M_AXI_DMEM_ARVALID(M_AXI_DMEM.ARVALID),
    .M_AXI_DMEM_ARREADY(M_AXI_DMEM.ARREADY),
    .M_AXI_DMEM_RDATA(M_AXI_DMEM.RDATA),
    .M_AXI_DMEM_RRESP(M_AXI_DMEM.RRESP),
    .M_AXI_DMEM_RLAST(M_AXI_DMEM.RLAST),
    .M_AXI_DMEM_RVALID(M_AXI_DMEM.RVALID),
    .M_AXI_DMEM_RREADY(M_AXI_DMEM.RREADY)
  );

endmodule
