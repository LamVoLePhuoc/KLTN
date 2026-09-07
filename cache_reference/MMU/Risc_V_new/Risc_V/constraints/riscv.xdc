# Xung Clock
set_property PACKAGE_PIN Y9 [get_ports sys_clock]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clock]

# Nút nhấn Reset (BTNC trên Zedboard)
set_property PACKAGE_PIN P16 [get_ports reset_rtl]
set_property IOSTANDARD LVCMOS18 [get_ports reset_rtl]

# Đèn LED báo hiệu (LD0 trên Zedboard)
set_property PACKAGE_PIN T22 [get_ports led_out]
set_property IOSTANDARD LVCMOS33 [get_ports led_out]