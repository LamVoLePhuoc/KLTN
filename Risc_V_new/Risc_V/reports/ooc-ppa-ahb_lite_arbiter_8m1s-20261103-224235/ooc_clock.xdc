create_clock -name ooc_clk -period 3.000 [get_ports {HCLK}]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports {HCLK}]
