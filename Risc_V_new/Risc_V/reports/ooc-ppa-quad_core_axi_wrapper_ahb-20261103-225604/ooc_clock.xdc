create_clock -name ooc_clk -period 9.700 [get_ports {ACLK}]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports {ACLK}]
