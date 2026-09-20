# ===============================================================
# genesys_zu5ev_boot_template.xdc
#
# NEW file (constraints/ is a new directory this session -- nothing
# here overwrites/replaces any existing constraint file in the repo,
# there were none before this).
#
# READ THIS BEFORE FILLING IN A SINGLE PIN NUMBER: this template does
# NOT contain verified Genesys ZU-5EV pin locations. Every attempt this
# session to extract exact pin names from Digilent's published
# reference manual / schematic PDFs failed (the PDFs use a compressed
# text-encoding this environment's tooling cannot parse, and no Vivado
# installation is available here to cross-check against the board
# file's own packaged constraints either). Writing down a guessed
# PACKAGE_PIN/IOSTANDARD here instead of leaving it blank would be
# exactly the kind of fabricated hardware fact this whole project has
# deliberately avoided everywhere else (see Risc_V_new/README.md) --
# and for I/O standard / voltage-bank properties specifically, a wrong
# guess is not just "won't work", it can genuinely damage the board.
# Get real pin data from one of these BEFORE editing this file:
#   - Digilent's official Genesys ZU-5EV master XDC / board files
#     (installed via the Digilent board-file repo referenced from
#     https://digilent.com/reference/programmable-logic/genesys-zu/reference-manual --
#     once installed, Vivado's own board-preset flow for the PS
#     already covers DDR/FIXED_IO/MIO for you, see below).
#   - Digilent's published schematic:
#     https://digilent.com/reference/_media/reference/programmable-logic/genesys-zu/genesys_zu-5ev_sch_public.pdf
#
# WHY THIS FILE IS SHORT: build_soc_zu5ev_boot.tcl's design is a Zynq
# UltraScale+ PS-centric design (see that script's header for why --
# short version: the SD card is PS-attached, so a PS is mandatory
# here). For a PS-based design using apply_bd_automation's board-
# preset step, Vivado does NOT need hand-written XDC constraints for
# DDR, FIXED_IO, or MIO-routed peripherals (SD, the PS console UART,
# etc.) at all -- those come from the installed board file + the PS
# IP's own packaged constraints, applied automatically once the
# correct board part is selected in Project Settings. This template
# therefore only needs to cover whatever RAW PL pins YOUR OWN design
# adds on top of that -- which, as shipped by this session, is
# NOTHING (every PL signal in build_soc_zu5ev_boot.tcl's block design
# stays internal, reaching the outside world only through the PS).
#
# WHEN YOU WOULD ACTUALLLY NEED TO FILL IN A PIN BELOW: only if you
# add something that exposes a raw PL pin as a top-level port -- for
# example, an LED wired to boot_ctrl's core_go signal (a nice, simple
# "did the RISC-V side actually start" visual indicator), or uart0's
# TXD/RXD IF you separately confirm this board has a PL-reachable
# UART-capable connector (see rtl/boot_ctrl.v's header -- NOT assumed
# by default). Uncomment and fill in ONLY the lines you actually need,
# using real pin names from the sources above -- never guess.
# ===============================================================

## Example (commented out -- fill in real values from Digilent's
## master XDC before uncommening, then rename the port to match
## whatever you actually add to soc_zu5ev_boot_wrapper.v):
# set_property PACKAGE_PIN <FILL_ME_FROM_DIGILENT_XDC> [get_ports core_go_led]
# set_property IOSTANDARD  <FILL_ME_FROM_DIGILENT_XDC> [get_ports core_go_led]

## Example for a bonus/debug PL UART (ONLY if confirmed PL-reachable --
## see rtl/boot_ctrl.v's header):
# set_property PACKAGE_PIN <FILL_ME_FROM_DIGILENT_XDC> [get_ports uart0_txd]
# set_property IOSTANDARD  <FILL_ME_FROM_DIGILENT_XDC> [get_ports uart0_txd]
# set_property PACKAGE_PIN <FILL_ME_FROM_DIGILENT_XDC> [get_ports uart0_rxd]
# set_property IOSTANDARD  <FILL_ME_FROM_DIGILENT_XDC> [get_ports uart0_rxd]
