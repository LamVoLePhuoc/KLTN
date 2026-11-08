create_clock -name ooc_clk -period 9.800 [get_ports {HCLK}]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports {HCLK}]
