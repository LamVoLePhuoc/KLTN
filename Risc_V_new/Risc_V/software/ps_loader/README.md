# PS loader integration

`boot_ctrl.h` is the software contract for the AXI4-Lite block instantiated by
the bootable SoC wrappers. `soc_dma.h` is the contract for the source-level
`rtl/dma/soc_dma_controller.v`. Set each base address to the value assigned by
the system address map.

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

When the source-level DMA controller is present, it performs both maintenance
passes itself:

```c
#include "soc_dma.h"

#define SOC_DMA_BASE  /* value from the system address map */

kltn_soc_dma_t *const dma =
    (kltn_soc_dma_t *)(uintptr_t)SOC_DMA_BASE;

lock_dma_buffer_on_all_riscv_cores();
if (kltn_dma_memcpy(dma, source, destination, byte_count,
                    PLATFORM_POLL_LIMIT) != KLTN_DMA_OK)
    recover_or_reset_while_buffers_remain_quiescent();
unlock_dma_buffer_on_all_riscv_cores();
```

Do not combine this helper with manual pre/post `boot_ctrl.CACHE` commands for
the same transfer; choose one ownership/maintenance path and keep it consistent.
