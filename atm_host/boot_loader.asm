; =========================================================================
; PROJECT126 — TR-DOS BASIC boot loader
; Version: P126_TRDOS_BOOT v0.1.0
;
; Adapted from the proven Project125 boot.B loader without changing its
; TR-DOS startup trampoline or CLEAR barrier.
; Loads PROJ126.C at 24576 and transfers control to 24585.
; =========================================================================

CLEAR       EQU     $FD
LOAD        EQU     $EF
CODE        EQU     $AF
RANDOMIZE   EQU     $F9
USR         EQU     $C0
REM         EQU     $EA
VAL         EQU     $B0
OUT_CMD     EQU     $DF

BASIC_START:
p126_basic_loader:
        ; 10 OUT 239,1:CLEAR 24000
        DB      0, 10
        DW      P126_LINE10_END-P126_LINE10
P126_LINE10:
        DB      OUT_CMD
        DB      "239", $0E, $00, $00, $EF, $00, $00
        DB      ","
        DB      "1", $0E, $00, $00, $01, $00, $00
        DB      ":"
        DB      CLEAR
        DB      "24000", $0E, $00, $00, $5D, $C0, $00
        DB      $0D
P126_LINE10_END:

        ; 11 OUT 239, VAL "50": ... "P126 START" on debug port #EF.
        DB      0, 11
        DW      P126_LINE11_END-P126_LINE11
P126_LINE11:
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "50", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "31", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "32", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "34", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "32", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "80", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "49", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "50", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "54", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "32", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "83", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "84", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "65", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "82", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "84", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "13", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "10", 34
        DB      $0D
P126_LINE11_END:

        ; 20 RANDOMIZE USR 15619:REM:LOAD "@@HOST_NAME@@" CODE 24576
        ; Keep the Project125 TR-DOS entry trampoline unchanged.
        DB      0, 20
        DW      P126_LINE20_END-P126_LINE20
P126_LINE20:
        DB      RANDOMIZE
        DB      USR, "15619", $0E, 0, 0
        DW      15619
        DB      0
        DB      $3A, REM, $3A
        DB      "LOAD ", 34, "@@HOST_NAME@@", 34, " CODE 24576", $0D
P126_LINE20_END:

        ; 21 LOADED marker, emitted only after TR-DOS loads PROJ126.C.
        DB      0, 21
        DW      P126_LINE21_END-P126_LINE21
P126_LINE21:
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "76", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "79", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "65", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "68", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "69", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "68", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "13", 34, ":"
        DB      OUT_CMD, VAL, 34, "239", 34, ",", VAL, 34, "10", 34
        DB      $0D
P126_LINE21_END:

        ; 30 OUT 239,2:RANDOMIZE USR VAL "24585"
        DB      0, 30
        DW      P126_LINE30_END-P126_LINE30
P126_LINE30:
        DB      OUT_CMD
        DB      "239", $0E, $00, $00, $EF, $00, $00
        DB      ","
        DB      "2", $0E, $00, $00, $02, $00, $00
        DB      ":"
        DB      RANDOMIZE
        DB      USR
        DB      VAL
        DB      34
        DEFM    "24585"
        DB      34
        DB      $0D
P126_LINE30_END:

        DB      $80

BASIC_END:
