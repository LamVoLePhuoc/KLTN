# V2 RTL (MMU-free simplified build)

This directory is a lightweight quad-core RTL variant that keeps the
core/cache/coherence structure but removes the MMU/TLB/PTW layer.

Used for:
- simpler multi-core bring-up
- cache/coherence validation without virtual memory
- reduced RTL complexity for a thesis/demo build

Important:
- VA = PA in this variant
- MMU and page-fault logic are intentionally disabled
- the original full MMU-based design remains in the main rtl folder
