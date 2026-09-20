# ===============================================================
# vcu129_template.xdc
#
# NEW file, same caveat as genesys_zu5ev_boot_template.xdc: NO
# verified VCU129 pin locations are in this file. Every
# PACKAGE_PIN/IOSTANDARD below is a placeholder you MUST replace with
# real values from AMD's official VCU129 Evaluation Board User Guide
# (UG1318 -- see Risc_V_new/README.md mục -0.5.5 for the link) before
# this can mean anything on real hardware. Guessing pin numbers here
# would be exactly the kind of fabricated hardware fact this project
# has deliberately avoided everywhere else -- and for I/O standard /
# voltage-bank properties specifically, a wrong guess can genuinely
# damage the board, not just fail to work.
#
# BIGGER OPEN QUESTION THAN PIN NUMBERS (read before investing effort
# here): unlike Genesys ZU-5EV, VCU129 is a pure-PL Virtex UltraScale+
# board -- there is no PS to lean on for SD-card access (see README's
# board survey, mục -0.5.5). This project's SD-card boot flow
# (build_soc_zu5ev_boot.tcl, rtl/boot_ctrl.v) is built entirely around
# having a PS available -- it does NOT apply to VCU129 as-is. Whether
# VCU129 can satisfy the advisor's mandatory-SD-boot requirement at
# all depends on TWO things neither this session nor its available
# tooling could confirm:
#   1. Does VCU129 physically have an SD/microSD slot at all? Official
#      feature lists found this session did not mention one (unlike
#      the related VCU118, which explicitly does) -- see README's
#      board survey for the exact sources checked.
#   2. IF it does, are the card's pins wired to PL-reachable I/O bank
#      pins (the only way a PL-only design could reach them at all)?
#
# If both are confirmed true, the RIGHT architecture here is
# DIFFERENT in kind from Genesys ZU-5EV's PS-mediated flow: it would
# need a genuine PL-side SD-in-SPI-mode bit-banged bootloader (real
# CMD0/CMD8/ACMD41/CMD17 protocol handling), talking to an
# ahb_lite_l1_adapter.v-style or axi_quad_spi-based SPI master IP
# instantiated directly in this board's own block design (NOT
# build_soc_zu5ev_boot.tcl, which is Zynq-PS-specific and would not
# even elaborate on a PS-less device). This session did not build that
# PL-only bootloader's RTL/hand-assembled boot ROM program -- doing so
# without first confirming #1/#2 above risks investing real effort
# (and real hand-assembly bug-risk, see Risc_V_new/README.md mục -0.1
# for how easy hand-assembled RISC-V programs are to get subtly wrong
# without a simulator) into a path that may not be physically usable
# on this specific board at all. Confirm #1/#2 first (physically
# inspect the board or read UG1318 closely), then ask for this piece
# specifically once confirmed -- the SD-in-SPI-mode protocol sequence
# itself (CMD0 -> CMD8 -> ACMD41 retry loop -> CMD16 -> CMD17 per
# block) is well-understood, stable, and safe to implement once the
# physical feasibility question is answered.
#
# What IS safe to fill in below regardless (every PL-only design needs
# these, independent of the SD-boot question above):
# ===============================================================

## System clock input -- FILL IN from UG1318. VCU129 almost certainly
## has a fixed-frequency differential oscillator wired to PL clock-
## capable pins (every UltraScale+ eval board does); the exact pin
## pair, frequency, and I/O standard (typically a LVDS-family standard
## for a differential clock input) all need to come from UG1318, not
## guessed here.
# set_property PACKAGE_PIN <FILL_ME_P> [get_ports sys_clk_p]
# set_property PACKAGE_PIN <FILL_ME_N> [get_ports sys_clk_n]
# set_property IOSTANDARD  <FILL_ME>   [get_ports sys_clk_p]
# set_property IOSTANDARD  <FILL_ME>   [get_ports sys_clk_n]
# create_clock -period <FILL_ME_PERIOD_NS> -name sys_clk [get_ports sys_clk_p]

## Reset input (push-button or DIP switch -- FILL IN from UG1318):
# set_property PACKAGE_PIN <FILL_ME> [get_ports ext_reset_in]
# set_property IOSTANDARD  <FILL_ME> [get_ports ext_reset_in]

## UART (only relevant once/if a PL-reachable UART-capable connector
## is confirmed -- see the open question above; VCU129's own on-board
## USB-UART bridge, if any, may or may not be PL-reachable, same class
## of question as Genesys ZU-5EV's UART -- do not assume):
# set_property PACKAGE_PIN <FILL_ME> [get_ports uart_txd]
# set_property IOSTANDARD  <FILL_ME> [get_ports uart_txd]
# set_property PACKAGE_PIN <FILL_ME> [get_ports uart_rxd]
# set_property IOSTANDARD  <FILL_ME> [get_ports uart_rxd]
