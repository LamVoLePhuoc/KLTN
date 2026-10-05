#ifndef KLTN_BOOT_CTRL_H
#define KLTN_BOOT_CTRL_H

#include <stdint.h>

/*
 * Portable register definitions for the PS-side loader.  Cast the base
 * address assigned to S_AXI_BOOT by Vivado's Address Editor to
 * kltn_boot_ctrl_t *.  No Xilinx BSP dependency is required here.
 */
typedef struct {
    volatile uint32_t ctrl;    /* 0x0: bit 0 GO, write-one/sticky */
    volatile uint32_t status;  /* 0x4: bit 0 mirrors GO */
    volatile uint32_t result;  /* 0x8: workload result */
    volatile uint32_t cache;   /* 0xC: command/status */
} kltn_boot_ctrl_t;

enum {
    KLTN_BOOT_GO              = 1u << 0,
    KLTN_CACHE_COMMAND        = 1u << 0,
    KLTN_CACHE_BUSY           = 1u << 0,
    KLTN_CACHE_DONE           = 1u << 1,
    KLTN_CACHE_ERROR          = 1u << 2,
    KLTN_CACHE_REJECTED       = 1u << 3
};

enum {
    KLTN_CACHE_OK             = 0,
    KLTN_CACHE_ERR_REJECTED   = -1,
    KLTN_CACHE_ERR_HARDWARE   = -2,
    KLTN_CACHE_ERR_SW_TIMEOUT = -3
};

static inline void kltn_io_barrier(void)
{
#if defined(__GNUC__) || defined(__clang__)
    __asm__ volatile ("" ::: "memory");
#endif
}

static inline void kltn_boot_release(kltn_boot_ctrl_t *regs)
{
    kltn_io_barrier();
    regs->ctrl = KLTN_BOOT_GO;
    kltn_io_barrier();
}

/*
 * Submit one global clean/invalidate and poll it to a safe conclusion.
 * spin_limit is deliberately supplied by the platform so the caller can
 * choose a timeout appropriate to its clock and recovery policy.
 *
 * The caller must quiesce every CPU user of the DMA buffer before entering.
 * Call once before DMA and once after DMA.  A hardware error is sticky and
 * requires subsystem recovery/reset; do not continue the transfer.
 */
static inline int kltn_cache_maintain(kltn_boot_ctrl_t *regs,
                                      uint32_t spin_limit)
{
    uint32_t i;

    regs->cache = KLTN_CACHE_COMMAND;
    kltn_io_barrier();

    for (i = 0; i < spin_limit; ++i) {
        const uint32_t state = regs->cache;

        if ((state & KLTN_CACHE_REJECTED) != 0u)
            return KLTN_CACHE_ERR_REJECTED;
        if ((state & KLTN_CACHE_ERROR) != 0u)
            return KLTN_CACHE_ERR_HARDWARE;
        if (((state & KLTN_CACHE_DONE) != 0u) &&
            ((state & KLTN_CACHE_BUSY) == 0u)) {
            kltn_io_barrier();
            return KLTN_CACHE_OK;
        }
    }

    return KLTN_CACHE_ERR_SW_TIMEOUT;
}

#endif /* KLTN_BOOT_CTRL_H */
