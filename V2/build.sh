#!/bin/bash
set -e

cd "$(dirname "$0")"
mkdir -p build

if command -v iverilog >/dev/null 2>&1; then
    iverilog -g2012 -f rtl/files.f -o build/v2_quadcore
    echo "Build OK: V2 quad-core RTL compiled with iverilog"
elif command -v verilator >/dev/null 2>&1; then
    verilator --cc --top quad_core_soc -f rtl/files.f
    echo "Build OK: V2 quad-core RTL compiled with Verilator"
else
    echo "No simulator found (iverilog/verilator). Install one to build the V2 RTL."
    exit 1
fi
