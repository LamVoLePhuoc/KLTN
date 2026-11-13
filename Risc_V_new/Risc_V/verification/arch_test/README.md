# RISC-V ACT4 integration

This directory connects the RTL to the official `riscv/riscv-arch-test`
ACT4 framework pinned at commit
`792e55702c6ffff5c8432670086f126f40b88c9e`.

The first enabled scope is the unprivileged RV32 `I`, `M`, `Zaamo`, `Zalrsc`,
`Zicsr` and `Zifencei` suites. Privileged certification is deliberately not
claimed: the current RTL has project-specific M/S/U CSR and trap behavior, no
complete interrupt platform, and its UDB parameters still require a rule-by-rule
audit. `prepare_act4_tests.ps1` therefore sets `include_priv_tests: False`.

Run generation and then XSIM execution from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare_act4_tests.ps1
vivado -mode batch -source scripts/run_riscv_arch_tests_xsim.tcl -tclargs build/act4/work/kltn-rv32ima/elfs
```

ACT4 generation requires the official current prerequisites: `make`, Ruby and
Bundler/UDB, GCC 15/Binutils 2.44, and Sail RISC-V 0.16. The script fails closed
when any dependency is absent or the source checkout is not at the pinned
commit. On Windows, WSL/Linux is the recommended ACT4 generation environment;
the produced ELF directory can then be passed to the Windows Vivado runner.

The stock Sail `RVI20U32` configuration is only used as a starting point. The
generation scripts explicitly disable `F`, `D`, `Zca`, `Zcf` and `Zcd`, make
`misa.M/A/C` immutable, and force `mstatus.FS` to read-only zero. This matters
because leaving `Zca` enabled gives the reference model `IALIGN=16`, whereas
the implemented RV32IMA core has `IALIGN=32` and must mask both low xEPC bits.
The scripts also specialize the Sail PMA to the testbench's executable 1 MiB
memory map and select Privileged ISA 1.11.

The DUT macros report pass (`1`) or fail (`3`) through uncached MMIO address
`0xC0000200`; console bytes use `0xC0000204`. Hart 0 executes the test from
`0x1000`, while harts 1–3 execute a parking loop at address zero. Every ELF is
converted with `objcopy --verilog-data-width=4` and run in a fresh XSIM process.

ACTs are certification tests, not complete processor verification. Keep the
directed ISA/CSR tests, random coherence stress, compiled four-core workload,
and protocol assertions as independent gates.

## Reproduced result

The pinned configuration generated 65 self-checking ELF files and passed all
65 in XSIM on 2026-11-13. The exact tool/source versions are recorded in
`build/act4/act4-manifest.txt`; the per-test result is in
`reports/xsim-riscv-arch-test-20261113-170438/summary.md`. This is a passing
official ACT4 **unprivileged subset** run, not a RISC-V certification claim.
