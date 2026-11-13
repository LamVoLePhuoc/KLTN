# Hierarchical full four-core SoC PPA

- Part: `xcvu29p-fsga2577-2L-e`
- MESI_ENABLE: `0`
- Target: `4.000 ns` (`250.000 MHz`)
- Setup WNS: `0.066 ns`
- Hold slack: `0.039 ns`
- Timing-derived Fmax estimate: `254.194 MHz`
- Failed/unrouted nets: `0`
- MARK_DEBUG nets: `0`
- Critical startpoint: `soc/core0/physical_core/core/mem_wb/RD_W_reg[1]/C`
- Critical endpoint: `soc/core0/physical_core/core/ex_mem/ALU_ResultM_reg[25]/D`

> All four HART_ID-specific core/L1 checkpoints were linked before implementation.
> Scope: internal RTL route with `-no_iobuf`. Final VCU129 board sign-off must drive ACLK through the board clocking/BUFG path and constrain external AXI input/output delays.
