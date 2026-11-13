#include <stdint.h>

#define HARTS              4u
#define PRIVATE_WORDS      256u
#define PING_PONG_ROUNDS   32u

#define BOOT_FLAG          (*(volatile uint32_t *)0x00008000u)
#define BARRIER0_BASE      ((volatile uint32_t *)0x00008200u)
#define BARRIER1_BASE      ((volatile uint32_t *)0x00008300u)
#define BARRIER2_BASE      ((volatile uint32_t *)0x00008400u)
#define TURN_WORD          (*(volatile uint32_t *)0x00008600u)
#define HOT_WORDS          ((volatile uint32_t *)0x00008620u)
#define PRIVATE_BASE(h)    ((volatile uint32_t *)(0x00009000u + ((h) << 12)))
#define MMIO_SIGNATURE(h)  (*(volatile uint32_t *)(0xC0000100u + ((h) << 2)))

static void barrier(volatile uint32_t *base, uint32_t hart)
{
    uint32_t peer;
    base[hart << 3] = 1u; /* one flag per 32-byte line */
    for (peer = 0; peer < HARTS; ++peer) {
        while (base[peer << 3] == 0u) {
            __asm__ volatile ("nop");
        }
    }
}

void workload_main(uint32_t hart)
{
    volatile uint32_t *private_words = PRIVATE_BASE(hart);
    uint32_t i;
    uint32_t checksum = 0u;
    uint32_t failed = 0u;

    if (hart == 0u) {
        TURN_WORD = 0u;
        for (i = 0; i < HARTS; ++i)
            HOT_WORDS[i] = 0u;
        BOOT_FLAG = 1u;
    } else {
        while (BOOT_FLAG == 0u)
            __asm__ volatile ("nop");
    }

    /* Private streaming phase: 32 cold lines followed by 224 line hits. */
    for (i = 0; i < PRIVATE_WORDS; ++i)
        private_words[i] = 0x13579BDFu ^ (hart << 24) ^ i;

    for (i = 0; i < PRIVATE_WORDS; ++i) {
        uint32_t expected = 0x13579BDFu ^ (hart << 24) ^ i;
        uint32_t observed = private_words[i];
        if (observed != expected)
            failed = 1u;
        checksum ^= (observed << (i & 7u)) | (observed >> ((32u - i) & 31u));
    }
    barrier(BARRIER0_BASE, hart);

    /* All four harts read data last written by hart 0, creating sharers. */
    for (i = 0; i < HARTS; ++i)
        checksum ^= HOT_WORDS[i];
    barrier(BARRIER1_BASE, hart);

    /* Deterministic M-owner migration and false sharing on one cache line. */
    for (i = 0; i < PING_PONG_ROUNDS; ++i) {
        while (TURN_WORD != hart)
            __asm__ volatile ("nop");
        HOT_WORDS[hart] = (hart << 16) | i;
        TURN_WORD = (hart + 1u) & 3u;
    }
    barrier(BARRIER2_BASE, hart);

    for (i = 0; i < HARTS; ++i) {
        if (HOT_WORDS[i] != ((i << 16) | (PING_PONG_ROUNDS - 1u)))
            failed = 1u;
    }
    if (TURN_WORD != 0u)
        failed = 1u;

    /* Signature is uncached MMIO, so the testbench observes completion
       without forcing a cache flush or peeking into a dirty private line. */
    MMIO_SIGNATURE(hart) = failed ? (0xBAD00000u | hart) :
                                    (0xC0DE0000u | hart | (checksum & 0u));

    for (;;)
        __asm__ volatile ("nop");
}
