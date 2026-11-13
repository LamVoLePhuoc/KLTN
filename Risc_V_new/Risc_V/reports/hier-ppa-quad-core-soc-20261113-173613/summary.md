# Hierarchical full four-core SoC PPA

- Part: `xcvu29p-fsga2577-2L-e`
- MESI_ENABLE: `1`
- Target: `4.000 ns` (`250.000 MHz`)
- Setup WNS: `0.158 ns`
- Hold slack: `0.040 ns`
- Timing-derived Fmax estimate: `260.281 MHz`
- Failed/unrouted nets: `0`
- MARK_DEBUG nets: `0`
- Critical startpoint: `soc/core0/physical_core/core/ex_mem/RD_M_reg[4]/C`
- Critical endpoint: `soc/core0/physical_core/core/ex_mem/ALU_ResultM_reg[3]/D`

> All four HART_ID-specific core/L1 checkpoints were linked before implementation.
> Scope: internal RTL route with `-no_iobuf`. Final VCU129 board sign-off must drive ACLK through the board clocking/BUFG path and constrain external AXI input/output delays.
