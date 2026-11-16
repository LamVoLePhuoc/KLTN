    .section .text.init
    .globl rvtest_entry_point
rvtest_entry_point:
    li      t0, 0xC0000200
    li      t1, 1
    sw      t1, 0(t0)
1:  j       1b
