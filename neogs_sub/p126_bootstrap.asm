; =========================================================================
; PROJECT126 — GS105a stage-0 bootstrap
; Loaded at 4000h by ROM command #14, entered by ROM command #13.
; Receives one bounded resident image over the legacy DBIT byte channel.
; DBIT/GSDAT are used here only for ROM/bootstrap compatibility; ABI 1.0
; application payloads use DMA after the resident image has started.
; =========================================================================
P126_B_ZXSTAT EQU #04
P126_B_ZXDATRD EQU #02
P126_B_ZXDATWR EQU #03
P126_B_DMA_MOD EQU #1B
P126_B_DMA_CST EQU #1F
P126_B_GSCFG0 EQU #0F
P126_B_MPAGE EQU #00
P126_B_MPAGEEX EQU #10
P126_B_READY EQU #A1
P126_B_LENGTH_ACK EQU #A3
P126_B_ERROR EQU #E1

p126_bootstrap_start:
        di
        ; The ROM's stack pointer is not part of the Project126 ABI.
        ; Establish our private stack before CALL/PUSH in the first logger.
        ld      sp,#FFFE
        ld      hl,p126_boot_msg_enter
        call    p126_boot_log
        ld      a,1
        out     (P126_B_DMA_MOD),a
        xor     a
        out     (P126_B_DMA_CST),a
        in      a,(P126_B_GSCFG0)
        and     #FD
        or      #09
        out     (P126_B_GSCFG0),a
        ld      hl,p126_boot_msg_norom
        call    p126_boot_log
        xor     a
        out     (#20),a                ; WIN0 -> physical page 00
        ld      a,#80
        out     (P126_B_MPAGE),a
        ld      a,#01
        out     (P126_B_MPAGEEX),a
        ld      bc,#FF02
        in      a,(c)
        ld      a,P126_B_READY
        call    p126_boot_send_byte
        call    p126_boot_receive_byte
        ld      e,a
        call    p126_boot_receive_byte
        ld      d,a
        ld      a,d
        or      e
        jp      z,p126_bootstrap_error
        ld      a,d
        cp      #40
        jr      c,p126_bootstrap_length_ok
        jp      nz,p126_bootstrap_error
        ld      a,e
        or      a
        jp      nz,p126_bootstrap_error
p126_bootstrap_length_ok:
        push    bc
        ld      bc,#0400
p126_bootstrap_turnaround:
        dec     bc
        ld      a,b
        or      c
        jr      nz,p126_bootstrap_turnaround
        pop     bc
        ld      a,P126_B_LENGTH_ACK
        call    p126_boot_send_byte
        ld      hl,0
p126_bootstrap_copy:
        ld      a,d
        or      e
        jr      z,p126_bootstrap_enter
        call    p126_boot_receive_byte
        ld      (hl),a
        inc     hl
        dec     de
        jr      p126_bootstrap_copy
p126_bootstrap_enter:
        jp      0
p126_bootstrap_error:
        ld      a,P126_B_ERROR
        call    p126_boot_send_byte
p126_bootstrap_halt:
        di
        halt
        jr      p126_bootstrap_halt

p126_boot_send_byte:
        ld      (p126_boot_tx),a
        ld      bc,#FFFF
p126_boot_send_wait_free:
        in      a,(P126_B_ZXSTAT)
        bit     7,a
        jr      z,p126_boot_send_free
        dec     bc
        ld      a,b
        or      c
        jr      nz,p126_boot_send_wait_free
        jp      p126_bootstrap_halt
p126_boot_send_free:
        ld      a,(p126_boot_tx)
        out     (P126_B_ZXDATWR),a
        ld      bc,#FFFF
p126_boot_send_wait_read:
        in      a,(P126_B_ZXSTAT)
        bit     7,a
        jr      z,p126_boot_send_done
        dec     bc
        ld      a,b
        or      c
        jr      nz,p126_boot_send_wait_read
        jp      p126_bootstrap_halt
p126_boot_send_done:
        or      a
        ret

p126_boot_receive_byte:
        ld      bc,#FFFF
p126_boot_receive_wait:
        in      a,(P126_B_ZXSTAT)
        bit     7,a
        jr      nz,p126_boot_receive_ready
        dec     bc
        ld      a,b
        or      c
        jr      nz,p126_boot_receive_wait
        jp      p126_bootstrap_halt
p126_boot_receive_ready:
        in      a,(P126_B_ZXDATRD)
        or      a
        ret

; Independent NeoGS diagnostic output. This routine writes directly to the
; NeoGS CPU's own physical #EF debug port; ATM does not proxy these bytes.
p126_boot_log:
        push    af
        push    bc
        ld      bc,#00EF
.p126_boot_log_loop:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,.p126_boot_log_done
        out     (c),a
        jr      .p126_boot_log_loop
.p126_boot_log_done:
        pop     bc
        pop     af
        ret

p126_boot_msg_enter: db "[NGS] BOOTSTRAP ENTER",13,10,0
p126_boot_msg_norom: db "[NGS] NOROM ENABLED",13,10,0
p126_boot_tx: db 0
p126_bootstrap_end:
