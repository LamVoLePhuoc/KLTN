# PS loader integration

`boot_ctrl.h` is the software contract for the AXI4-Lite block instantiated by
the bootable SoC wrappers. Set `BOOT_CTRL_BASE` to the address assigned to
`cpu0/S_AXI_BOOT` in the PS address space.

```c
#include "boot_ctrl.h"

#define BOOT_CTRL_BASE  /* value from Vivado Address Editor */

kltn_boot_ctrl_t *const boot =
    (kltn_boot_ctrl_t *)(uintptr_t)BOOT_CTRL_BASE;

/* Initial SD-to-memory load happens while GO is zero and caches are reset. */
load_and_verify_riscv_image();
kltn_boot_release(boot);

/* Any later DMA transfer requires exclusive software ownership of its buffer. */
lock_dma_buffer_on_all_riscv_cores();
if (kltn_cache_maintain(boot, PLATFORM_POLL_LIMIT) != KLTN_CACHE_OK)
    recover_or_reset();
start_dma();
wait_and_check_dma();
if (kltn_cache_maintain(boot, PLATFORM_POLL_LIMIT) != KLTN_CACHE_OK)
    recover_or_reset();
unlock_dma_buffer_on_all_riscv_cores();
```

The functions named around the header API are platform-specific placeholders,
not implementations. In particular, the buffer ownership protocol and DMA error
handling depend on the PS software environment. See
[`../../docs/BOOT_DMA_PROTOCOL.md`](../../docs/BOOT_DMA_PROTOCOL.md) for failure
semantics and the complete ordering requirements.
