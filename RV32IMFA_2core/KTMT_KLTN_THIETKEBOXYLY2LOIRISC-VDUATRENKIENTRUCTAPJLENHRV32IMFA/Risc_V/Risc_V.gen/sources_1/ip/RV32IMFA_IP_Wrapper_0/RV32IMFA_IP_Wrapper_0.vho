-- (c) Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- (c) Copyright 2022-2026 Advanced Micro Devices, Inc. All rights reserved.
-- 
-- This file contains confidential and proprietary information
-- of AMD and is protected under U.S. and international copyright
-- and other intellectual property laws.
-- 
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- AMD, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) AMD shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or AMD had been advised of the
-- possibility of the same.
-- 
-- CRITICAL APPLICATIONS
-- AMD products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of AMD products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
-- 
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-- 
-- DO NOT MODIFY THIS FILE.
-- IP VLNV: xilinx.com:user:RV32IMFA_IP_Wrapper:1.0
-- IP Revision: 3

-- The following code must appear in the VHDL architecture header.

------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
COMPONENT RV32IMFA_IP_Wrapper_0
  PORT (
    ACLK : IN STD_LOGIC;
    ARESETN : IN STD_LOGIC;
    Snoop_Addr : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    Snoop_WE : IN STD_LOGIC;
    ResultW : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    ALU_ResultE_Debug : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_IMEM_ARADDR : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_IMEM_ARLEN : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    M_AXI_IMEM_ARSIZE : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M_AXI_IMEM_ARBURST : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_IMEM_ARVALID : OUT STD_LOGIC;
    M_AXI_IMEM_ARREADY : IN STD_LOGIC;
    M_AXI_IMEM_RDATA : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_IMEM_RRESP : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_IMEM_RLAST : IN STD_LOGIC;
    M_AXI_IMEM_RVALID : IN STD_LOGIC;
    M_AXI_IMEM_RREADY : OUT STD_LOGIC;
    M_AXI_DMEM_AWADDR : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_DMEM_AWLEN : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    M_AXI_DMEM_AWSIZE : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M_AXI_DMEM_AWBURST : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_DMEM_AWVALID : OUT STD_LOGIC;
    M_AXI_DMEM_AWREADY : IN STD_LOGIC;
    M_AXI_DMEM_WDATA : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_DMEM_WSTRB : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M_AXI_DMEM_WLAST : OUT STD_LOGIC;
    M_AXI_DMEM_WVALID : OUT STD_LOGIC;
    M_AXI_DMEM_WREADY : IN STD_LOGIC;
    M_AXI_DMEM_BRESP : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_DMEM_BVALID : IN STD_LOGIC;
    M_AXI_DMEM_BREADY : OUT STD_LOGIC;
    M_AXI_DMEM_ARADDR : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_DMEM_ARLEN : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    M_AXI_DMEM_ARSIZE : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M_AXI_DMEM_ARBURST : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_DMEM_ARVALID : OUT STD_LOGIC;
    M_AXI_DMEM_ARREADY : IN STD_LOGIC;
    M_AXI_DMEM_RDATA : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_DMEM_RRESP : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_DMEM_RLAST : IN STD_LOGIC;
    M_AXI_DMEM_RVALID : IN STD_LOGIC;
    M_AXI_DMEM_RREADY : OUT STD_LOGIC 
  );
END COMPONENT;
-- COMP_TAG_END ------ End COMPONENT Declaration ------------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
your_instance_name : RV32IMFA_IP_Wrapper_0
  PORT MAP (
    ACLK => ACLK,
    ARESETN => ARESETN,
    Snoop_Addr => Snoop_Addr,
    Snoop_WE => Snoop_WE,
    ResultW => ResultW,
    ALU_ResultE_Debug => ALU_ResultE_Debug,
    M_AXI_IMEM_ARADDR => M_AXI_IMEM_ARADDR,
    M_AXI_IMEM_ARLEN => M_AXI_IMEM_ARLEN,
    M_AXI_IMEM_ARSIZE => M_AXI_IMEM_ARSIZE,
    M_AXI_IMEM_ARBURST => M_AXI_IMEM_ARBURST,
    M_AXI_IMEM_ARVALID => M_AXI_IMEM_ARVALID,
    M_AXI_IMEM_ARREADY => M_AXI_IMEM_ARREADY,
    M_AXI_IMEM_RDATA => M_AXI_IMEM_RDATA,
    M_AXI_IMEM_RRESP => M_AXI_IMEM_RRESP,
    M_AXI_IMEM_RLAST => M_AXI_IMEM_RLAST,
    M_AXI_IMEM_RVALID => M_AXI_IMEM_RVALID,
    M_AXI_IMEM_RREADY => M_AXI_IMEM_RREADY,
    M_AXI_DMEM_AWADDR => M_AXI_DMEM_AWADDR,
    M_AXI_DMEM_AWLEN => M_AXI_DMEM_AWLEN,
    M_AXI_DMEM_AWSIZE => M_AXI_DMEM_AWSIZE,
    M_AXI_DMEM_AWBURST => M_AXI_DMEM_AWBURST,
    M_AXI_DMEM_AWVALID => M_AXI_DMEM_AWVALID,
    M_AXI_DMEM_AWREADY => M_AXI_DMEM_AWREADY,
    M_AXI_DMEM_WDATA => M_AXI_DMEM_WDATA,
    M_AXI_DMEM_WSTRB => M_AXI_DMEM_WSTRB,
    M_AXI_DMEM_WLAST => M_AXI_DMEM_WLAST,
    M_AXI_DMEM_WVALID => M_AXI_DMEM_WVALID,
    M_AXI_DMEM_WREADY => M_AXI_DMEM_WREADY,
    M_AXI_DMEM_BRESP => M_AXI_DMEM_BRESP,
    M_AXI_DMEM_BVALID => M_AXI_DMEM_BVALID,
    M_AXI_DMEM_BREADY => M_AXI_DMEM_BREADY,
    M_AXI_DMEM_ARADDR => M_AXI_DMEM_ARADDR,
    M_AXI_DMEM_ARLEN => M_AXI_DMEM_ARLEN,
    M_AXI_DMEM_ARSIZE => M_AXI_DMEM_ARSIZE,
    M_AXI_DMEM_ARBURST => M_AXI_DMEM_ARBURST,
    M_AXI_DMEM_ARVALID => M_AXI_DMEM_ARVALID,
    M_AXI_DMEM_ARREADY => M_AXI_DMEM_ARREADY,
    M_AXI_DMEM_RDATA => M_AXI_DMEM_RDATA,
    M_AXI_DMEM_RRESP => M_AXI_DMEM_RRESP,
    M_AXI_DMEM_RLAST => M_AXI_DMEM_RLAST,
    M_AXI_DMEM_RVALID => M_AXI_DMEM_RVALID,
    M_AXI_DMEM_RREADY => M_AXI_DMEM_RREADY
  );
-- INST_TAG_END ------ End INSTANTIATION Template ---------

-- You must compile the wrapper file RV32IMFA_IP_Wrapper_0.vhd when simulating
-- the core, RV32IMFA_IP_Wrapper_0. When compiling the wrapper file, be sure to
-- reference the VHDL simulation library.



