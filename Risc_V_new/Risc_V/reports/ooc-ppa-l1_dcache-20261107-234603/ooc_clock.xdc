create_clock -name ooc_clk -period 5.000 [get_ports {clk}]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports {clk}]
