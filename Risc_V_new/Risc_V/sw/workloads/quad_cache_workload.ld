OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = 0x00001000;
    .text : ALIGN(4) {
        KEEP(*(.text.init))
        *(.text .text.*)
    }
    .rodata : ALIGN(4) { *(.rodata .rodata.*) }
    .data : ALIGN(4) { *(.data .data.*) }
    .bss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.bss .bss.* COMMON)
        __bss_end = .;
    }
    /DISCARD/ : { *(.comment) *(.eh_frame*) *(.riscv.attributes) }
}

ASSERT(. < 0x00008000, "workload image overlaps shared test data")
