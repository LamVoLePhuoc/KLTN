# Reproducible post-route proof at 9.800 ns (102.041 MHz).
# The implementation script fails if either post-route setup or hold slack is
# negative; it does not add false paths, multicycle paths, or DRC waivers.
source [file join [file dirname [file normalize [info script]]] run_mdu_pipeline_impl.tcl]
