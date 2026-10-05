# Vivado XSIM MMU regression

Result: **9/9 PASS**

| Test | Result | Log |
|---|---:|---|
| tb_mmu_core | PASS | run-tb_mmu_core.log |
| tb_mmu_upgrade | PASS | run-tb_mmu_upgrade.log |
| tb_mmu_policy | PASS | run-tb_mmu_policy.log |
| tb_mmu_advanced | PASS | run-tb_mmu_advanced.log |
| tb_mmu_sfence | PASS | run-tb_mmu_sfence.log |
| tb_mmu_context | PASS | run-tb_mmu_context.log |
| tb_mmu_bus_error | PASS | run-tb_mmu_bus_error.log |
| tb_csr_mmu_bits | PASS | run-tb_csr_mmu_bits.log |
| tb_csr_access_fault | PASS | run-tb_csr_access_fault.log |

> Scope: MMU and directly related CSR tests. tb_csr_priv is not included in these 9 tests.
