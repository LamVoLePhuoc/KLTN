#ifndef KLTN_SOC_DMA_H
#define KLTN_SOC_DMA_H

#include <stdint.h>

/* Portable register contract for rtl/dma/soc_dma_controller.v. */
typedef struct {
    volatile uint32_t control;   /* 0x00: START/CLEAR */
    volatile uint32_t status;    /* 0x04: BUSY/DONE/ERROR/CODE */
    volatile uint32_t src_addr;  /* 0x08 */
    volatile uint32_t dst_addr;  /* 0x0c */
    volatile uint32_t length;    /* 0x10: bytes */
} kltn_soc_dma_t;

enum {
    KLTN_DMA_START        = 1u << 0,
    KLTN_DMA_CLEAR_STATUS = 1u << 1,
    KLTN_DMA_BUSY         = 1u << 0,
    KLTN_DMA_DONE         = 1u << 1,
    KLTN_DMA_ERROR        = 1u << 2,
    KLTN_DMA_ERROR_SHIFT  = 8,
    KLTN_DMA_ERROR_MASK   = 7u << KLTN_DMA_ERROR_SHIFT
};

enum {
    KLTN_DMA_OK               = 0,
    KLTN_DMA_ERR_ARGUMENT     = -1,
    KLTN_DMA_ERR_PRE_FLUSH    = -2,
    KLTN_DMA_ERR_TRANSFER     = -3,
    KLTN_DMA_ERR_POST_FLUSH   = -4,
    KLTN_DMA_ERR_HW_TIMEOUT   = -5,
    KLTN_DMA_ERR_REJECTED     = -6,
    KLTN_DMA_ERR_SW_TIMEOUT   = -7,
    KLTN_DMA_ERR_UNKNOWN      = -8
};

static inline void kltn_dma_io_barrier(void)
{
#if defined(__GNUC__) || defined(__clang__)
    __asm__ volatile ("" ::: "memory");
#endif
}

static inline int kltn_dma_decode_error(uint32_t status)
{
    switch ((status & KLTN_DMA_ERROR_MASK) >> KLTN_DMA_ERROR_SHIFT) {
    case 1u: return KLTN_DMA_ERR_PRE_FLUSH;
    case 2u: return KLTN_DMA_ERR_TRANSFER;
    case 3u: return KLTN_DMA_ERR_POST_FLUSH;
    case 4u: return KLTN_DMA_ERR_HW_TIMEOUT;
    case 5u: return KLTN_DMA_ERR_REJECTED;
    default: return KLTN_DMA_ERR_UNKNOWN;
    }
}

/*
 * Submit one aligned copy and poll its sticky completion status. The caller
 * must establish the ownership condition represented by buffer_quiesced before
 * calling and must keep the buffers quiescent until this function returns.
 */
static inline int kltn_dma_memcpy(kltn_soc_dma_t *regs,
                                  uint32_t src_addr,
                                  uint32_t dst_addr,
                                  uint32_t length_bytes,
                                  uint32_t spin_limit)
{
    uint32_t i;

    if ((length_bytes == 0u) ||
        (((src_addr | dst_addr | length_bytes) & 3u) != 0u))
        return KLTN_DMA_ERR_ARGUMENT;

    regs->control = KLTN_DMA_CLEAR_STATUS;
    regs->src_addr = src_addr;
    regs->dst_addr = dst_addr;
    regs->length = length_bytes;
    kltn_dma_io_barrier();
    regs->control = KLTN_DMA_START;
    kltn_dma_io_barrier();

    for (i = 0; i < spin_limit; ++i) {
        const uint32_t state = regs->status;
        if (((state & KLTN_DMA_DONE) != 0u) &&
            ((state & KLTN_DMA_BUSY) == 0u)) {
            kltn_dma_io_barrier();
            return ((state & KLTN_DMA_ERROR) != 0u) ?
                   kltn_dma_decode_error(state) : KLTN_DMA_OK;
        }
    }

    return KLTN_DMA_ERR_SW_TIMEOUT;
}

#endif /* KLTN_SOC_DMA_H */
