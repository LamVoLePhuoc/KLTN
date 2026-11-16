    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
    .type _start, @function
_start:
    csrr    a0, mhartid

    /* Four non-overlapping 2 KiB stacks ending below 0x0001_0000. */
    li      t0, 0x0000d800
    slli    t1, a0, 11
    add     sp, t0, t1

    call    workload_main
1:
    j       1b
    .size _start, .-_start
