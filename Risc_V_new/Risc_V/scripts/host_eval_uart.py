#!/usr/bin/env python3
# ===============================================================
# host_eval_uart.py
#
# Host-side half of the "automated FPGA evaluation" piece of Direction
# 3 (Risc_V_new/README.md). This script is generic: it just watches
# WHATEVER serial port you point it at for a line containing "PASS" or
# "FAIL", giving an automated test run (a CI job, a batch of board
# tests, or just you not wanting to babysit a serial terminal window) a
# real exit code instead of eyeballing a waveform or a terminal by
# hand -- directly answering the "kịch bản đánh giá tự động, không cần
# xem waveform thủ công" ask.
#
# WHICH SERIAL PORT TO POINT THIS AT (see rtl/boot_ctrl.v's header for
# the full reasoning): on Genesys ZU-5EV, the RECOMMENDED/confirmed-
# feasible target is the PS's own console UART -- the same COM port
# you already use to watch FSBL/u-boot/Linux boot messages. The PS-
# side loader program (see README), after writing boot_ctrl's GO bit
# and later polling its REG_RESULT register, simply prints "PASS" or
# "FAIL" to its own stdout, which goes out over that already-confirmed-
# working UART. build_soc_zu5ev_boot.tcl's uart0 (axi_uartlite, a PL
# peripheral) is a SEPARATE, bonus/debug-only serial output -- point
# this script at it INSTEAD only if you have separately confirmed this
# board exposes a PL-reachable UART-capable connector; do not assume
# it by default (see boot_ctrl.v's header for why that's uncertain).
#
# WHAT THIS DOES NOT DO: it does not program the board, load the SD
# card, or drive JTAG -- it only WATCHES a UART already exposed as a
# host COM port / /dev/ttyUSB* device (the same port a serial terminal
# like PuTTY/screen/minicom would open), after you have already booted
# the board through whatever flow README documents (SD boot -> PS
# loader -> boot_ctrl GO -> RISC-V program runs -> RISC-V writes
# boot_ctrl's REG_RESULT -> PS loader reads it back and prints it).
#
# CONTRACT this script expects: at least one line containing the
# literal substring "PASS" (success) or "FAIL" (failure), terminated
# by '\n', printed to whatever UART this script is pointed at (see
# above -- the PS loader's own stdout by default). This mirrors the
# exact convention every sim testbench in this repo already uses
# ($display("..._TB: PASS/FAIL")) -- same idea, now read back from
# real hardware over a wire instead of a simulator log.
#
# Usage:
#   python host_eval_uart.py --port COM5 --baud 115200
#   python host_eval_uart.py --port /dev/ttyUSB1 --baud 115200 --timeout 30
#
# Exit codes (for scripting/CI -- check $? / %ERRORLEVEL% after running):
#   0  = saw a line containing "PASS" before any "FAIL" and before timeout
#   1  = saw a line containing "FAIL"
#   2  = timed out with neither PASS nor FAIL seen (dead board, wrong
#        baud rate, wrong port, program never reached its result line,
#        or boot_ctrl's GO was never written -- see README's boot flow)
#   3  = could not open the serial port at all (wrong port name, port
#        in use by another program, permissions)
#
# Requires: pyserial (`pip install pyserial`) -- NOT in Python's
# standard library, install it first. This is the one real external
# dependency this script has; everything else is standard library.
# ===============================================================

import argparse
import sys
import time

try:
    import serial
except ImportError:
    print("ERROR: pyserial is not installed. Run: pip install pyserial", file=sys.stderr)
    sys.exit(3)


def main():
    parser = argparse.ArgumentParser(
        description="Watch a board's UART for a PASS/FAIL result line -- automated FPGA evaluation, no waveform needed."
    )
    parser.add_argument("--port", required=True, help="Serial port, e.g. COM5 or /dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default 115200 -- must match uart0's C_BAUDRATE in build_soc_zu5ev_boot.tcl)")
    parser.add_argument("--timeout", type=float, default=60.0, help="Seconds to wait for a PASS/FAIL line before giving up (default 60)")
    parser.add_argument("--echo", action="store_true", help="Also print every line received to stdout as it arrives (useful while debugging a new test program)")
    args = parser.parse_args()

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1.0)
    except serial.SerialException as e:
        print(f"ERROR: could not open {args.port} at {args.baud} baud: {e}", file=sys.stderr)
        sys.exit(3)

    print(f"Listening on {args.port} @ {args.baud} baud, timeout={args.timeout}s ...")
    deadline = time.monotonic() + args.timeout
    buf = b""

    try:
        while time.monotonic() < deadline:
            chunk = ser.read(256)  # blocks up to the Serial() timeout=1.0s above, never past --timeout overall
            if not chunk:
                continue
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                text = line.decode("ascii", errors="replace").rstrip("\r")
                if args.echo:
                    print(f"  UART> {text}")
                if "FAIL" in text:
                    print(f"RESULT: FAIL -- board reported: {text}")
                    ser.close()
                    sys.exit(1)
                if "PASS" in text:
                    print(f"RESULT: PASS -- board reported: {text}")
                    ser.close()
                    sys.exit(0)
    finally:
        ser.close()

    print(f"RESULT: TIMEOUT -- no PASS/FAIL line seen within {args.timeout}s.")
    print("Check: correct COM port/baud rate, board actually booted (SD card present and")
    print("formatted correctly, boot_ctrl's GO bit actually written by the PS loader -- see")
    print("Risc_V_new/README.md's boot-flow section), and that the RISC-V test program actually")
    print("writes its result line to uart0 before it self-loops.")
    sys.exit(2)


if __name__ == "__main__":
    main()
