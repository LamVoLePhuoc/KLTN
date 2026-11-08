# Shared-L2 physical cluster for xc7z030fbv676-1.
#
# The 512-KiB L2 uses 136 RAMB36E1 + 5 RAMB18E1 after explicit 8x32-bit
# banking (139 conservative BRAM tiles).  The lower 2x2 clock-region rectangle
# contains 145 RAMB36 sites; this is the smallest contiguous rectangle that can
# hold the complete L2 while leaving 120 RAMB36 sites for four private L1 pairs
# and the platform memory in the upper half of the device.
#
# Include the MSI/cache controller in the same pblock so its command, refill
# and maintenance registers stay close to the L2 ports.  EXCLUDE_PLACEMENT is
# intentionally false: unrelated slice logic may use otherwise-empty slice
# sites inside the rectangle, while only pblock members are required to stay
# inside it.

create_pblock pblock_l2_cluster
resize_pblock [get_pblocks pblock_l2_cluster] -add \
    {CLOCKREGION_X0Y0:CLOCKREGION_X1Y1}
add_cells_to_pblock [get_pblocks pblock_l2_cluster] \
    [get_cells -hier -filter {
        NAME =~ *u_shared_l2* || NAME =~ *g_internal_l2*u_l2* ||
        NAME =~ *u_cache_controller_mmu*
    }]
set_property EXCLUDE_PLACEMENT false [get_pblocks pblock_l2_cluster]
set_property CONTAIN_ROUTING false [get_pblocks pblock_l2_cluster]
