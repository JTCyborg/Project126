; =========================================================================
; PROJECT126 — stage-0 bootstrap assembly unit, executable at 4000h.
; =========================================================================
        ORG #4000
        INCLUDE "neogs_sub/p126_bootstrap.asm"
        ASSERT p126_bootstrap_start = #4000
        ASSERT p126_bootstrap_end > p126_bootstrap_start
        ASSERT p126_bootstrap_end <= #4100
        ASSERT p126_bootstrap_end-p126_bootstrap_start <= #0100
        DISPLAY "P126_BOOTSTRAP_START=",/H,p126_bootstrap_start
        DISPLAY "P126_BOOTSTRAP_END=",/H,p126_bootstrap_end
        DISPLAY "P126_BOOTSTRAP_SIZE=",/D,p126_bootstrap_end-p126_bootstrap_start
        SAVEBIN "build/P126_BOOTSTRAP.bin",p126_bootstrap_start,p126_bootstrap_end-p126_bootstrap_start
