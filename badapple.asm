; BADAPPLE.COM: Bad Apple!! on the V9990 + MoonSound (OPL4).
; MSX-DOS2 / Nextor.  Plays BADAPPLE.V99 (format in README.md, version 3) in B1
; (256x212), BP2, at 30 fps: one frame every 2 JIFFY ticks (60 Hz).
;
; The stream goes through a ring of 16 KB mapper segments (one chunk of the
; file each, no frame record crosses a chunk), mapped in page 2 to read and to
; decode.  While waiting for the next frame the player reads the file in
; pieces of 4 KB into the free segments.  R800 on a turbo R.
;
; Audio: BADAPPLE.OPL goes to the sample RAM of the OPL4 first; every frame
; record carries the OPL4 register writes of 2 music ticks (a few frames
; ahead), which the main loop puts in a FIFO in page 3; an H.TIMI routine,
; also in page 3, writes one tick of them at every interrupt.  Without a
; MoonSound the video plays alone.
;
;   pasmo badapple.asm BADAPPLE.COM

BDOS    equ     0005h
RDSLT   equ     000Ch
CALSLT  equ     001Ch
EXPTBL  equ     0FCC1h
JIFFY   equ     0FC9Eh
HOKVLD  equ     0FB20h
EXTBIO  equ     0FFCAh
CHGCPU  equ     0180h

_CONOUT equ     02h
_STROUT equ     09h
_OPEN   equ     43h
_CLOSE  equ     45h
_READ   equ     48h
_TERM   equ     62h

P_VRAM  equ     60h
P_PAL   equ     61h
P_RDATA equ     63h
P_RSEL  equ     64h
P_SYS   equ     67h

PAGE2   equ     8000h
CHUNK   equ     4000h
PIECE   equ     1000h           ; bytes per read while playing
MAXSEG  equ     32
FRAME_TICKS equ 2               ; 60 Hz / 2 = 30 fps

H_TIMI  equ     0FD9Fh
OPL_ST  equ     0C4h            ; status (BUSY bit 0, with NEW2)
OPL_A1  equ     0C6h            ; FM register array 1
OPL_D1  equ     0C7h
OPL_WA  equ     7Eh             ; wave part register
OPL_WD  equ     7Fh

; page 3: music FIFO, ISR variables and code (the TPA must reach TPA_MIN)
FIFO    equ     0C000h          ; 2 KB ring, C000h-C7FFh (wrap: res 3,h)
M_PLAY  equ     0C800h          ; 1: the ISR plays
M_AVAIL equ     0C801h          ; ticks in the FIFO
M_RD    equ     0C802h          ; FIFO read pointer (ISR)
M_WR    equ     0C804h          ; FIFO write pointer (main loop)
M_UNDER equ     0C806h          ; ticks with the FIFO empty
M_OLD   equ     0C808h          ; the H.TIMI hook before ours (5 bytes)
ISR_ADR equ     0C810h
TPA_MIN equ     0CC00h

        org     0100h

start:
        ld      sp, (0006h)             ; top of the TPA
        ld      de, s_title
        call    print

        ; R800 on a turbo R (MSX version 3 at 002Dh of the main ROM)
        ld      a, (EXPTBL)
        ld      hl, 002Dh
        call    RDSLT
        ei
        cp      3
        jr      c, no_r800
        ld      a, 82h                  ; R800 DRAM mode
        call    set_cpu
        ld      a, 1
        ld      (r800), a
no_r800:

        call    init_mapper
        call    open_file
        call    audio_init
        call    v_init
        ld      a, 1
        ld      (v_on), a

        ; fill the ring before starting
prefill:
        call    can_fill
        jr      z, pf_done
        call    read_piece
        jr      prefill
pf_done:

        ld      hl, PAGE2
        ld      (rdptr), hl
        ld      hl, (hdr + 12)
        ld      (frames), hl
        call    isr_install
        ld      hl, (JIFFY)
        inc     hl
        ld      (next), hl

play:
        ; wait for the time of the frame, reading the file meanwhile
wait:
        ld      hl, (JIFFY)
        ld      de, (next)
        or      a
        sbc     hl, de                  ; JIFFY - next
        bit     7, h
        jr      z, go                   ; >= 0
        call    can_fill
        jr      z, wait
        call    read_piece
        jr      wait
go:
        ld      a, h
        or      l
        jr      z, on_time
        ld      hl, (late)
        inc     hl
        ld      (late), hl
on_time:
        call    ensure_ready
        ld      a, (cur)
        call    seg_of
        call    put_p2
        ld      hl, (rdptr)
chk:
        ld      a, (hl)
        inc     hl
        or      (hl)
        dec     hl
        jr      nz, have_frame
        ; 0000h: end of the records of this chunk, next segment
        ld      hl, ready
        dec     (hl)
        ld      a, (cur)
        call    seg_next
        ld      (cur), a
        call    ensure_ready
        ld      a, (cur)
        call    seg_of
        call    put_p2
        ld      hl, PAGE2
        jr      chk
have_frame:
        call    decode_frame
        call    music_in
        ld      (rdptr), hl
        ld      a, (audio)              ; the ISR starts after frame 0
        ld      (M_PLAY), a
        ld      hl, (next)
        ld      de, FRAME_TICKS
        add     hl, de
        ld      (next), hl
        ld      hl, (frames)
        dec     hl
        ld      (frames), hl
        ld      a, h
        or      l
        jr      nz, play

        ; the end: let the music finish
end_wait:
        ld      a, (audio)
        or      a
        jr      z, end_stats
        ld      a, (M_AVAIL)
        or      a
        jr      nz, end_wait
        xor     a
        ld      (M_PLAY), a
        call    keys_off
end_stats:
        ld      de, s_late
        call    print
        ld      hl, (late)
        call    prnum
        ld      de, s_under
        call    print
        ld      hl, (under)
        call    prnum
        ld      a, (audio)
        or      a
        jr      z, es_crlf
        ld      de, s_munder
        call    print
        ld      hl, (M_UNDER)
        call    prnum
es_crlf:
        ld      de, s_crlf
        call    print
quit:
        call    isr_remove
        call    v_off
        ld      a, (fh)
        ld      b, a
        ld      c, _CLOSE
        call    BDOS
        ld      a, (orig_p2)
        call    put_p2
        ld      a, (r800)
        or      a
        ld      a, 80h                  ; back to the Z80
        call    nz, set_cpu
        ld      b, 0
        ld      c, _TERM
        jp      BDOS

; ---------------------------------------------------------------- ring
; Z: no piece to read (file done, or every segment full)
can_fill:
        ld      hl, (chunks)
        ld      a, h
        or      l
        ret     z
        ld      a, (ready)
        ld      hl, nseg
        cp      (hl)
        jr      c, cf_yes
        xor     a
        ret
cf_yes: or      1
        ret

; at least one chunk ready to decode (an empty ring is an underrun)
ensure_ready:
        ld      a, (ready)
        or      a
        ret     nz
        ld      hl, (under)
        inc     hl
        ld      (under), hl
er_loop:
        call    can_fill
        jr      z, er_eof
        call    read_piece
        ld      a, (ready)
        or      a
        jr      z, er_loop
        ret
er_eof:
        ld      de, s_short
        call    print
        jp      quit

; next PIECE of the file into the segment being filled
read_piece:
        ld      a, (fill)
        call    seg_of
        call    put_p2
        ld      hl, (fillofs)
        ld      de, PAGE2
        add     hl, de
        ex      de, hl
        ld      hl, PIECE
        ld      a, (fh)
        ld      b, a
        ld      c, _READ
        call    BDOS
        or      a
        jp      nz, err_read
        ld      hl, (fillofs)
        ld      de, PIECE
        add     hl, de
        ld      a, h
        cp      CHUNK / 256
        jr      c, rp_part
        ld      a, (fill)
        call    seg_next
        ld      (fill), a
        ld      hl, ready
        inc     (hl)
        ld      hl, (chunks)
        dec     hl
        ld      (chunks), hl
        ld      hl, 0
rp_part:
        ld      (fillofs), hl
        ; leave the segment being decoded in page 2
        ld      a, (cur)
        call    seg_of
        jp      put_p2

; A = ring index -> A = segment
seg_of:
        ld      hl, segs
        add     a, l
        ld      l, a
        jr      nc, so1
        inc     h
so1:    ld      a, (hl)
        ret

; A = ring index -> the next one
seg_next:
        inc     a
        ld      hl, nseg
        cp      (hl)
        ret     c
        xor     a
        ret

; ---------------------------------------------------------------- decoder
; HL = frame record (length word first); returns HL after it
decode_frame:
        inc     hl
        inc     hl
        ld      c, P_VRAM
df_run:
        ld      e, (hl)
        inc     hl
        ld      a, (hl)
        inc     hl
        cp      0FFh                    ; FFFFh: end (addresses < 3600h)
        ret     z
        ld      d, a
        xor     a
        out     (P_RSEL), a             ; R#0, write increment
        ld      a, e
        out     (P_RDATA), a
        ld      a, d
        and     3Fh
        out     (P_RDATA), a
        xor     a
        out     (P_RDATA), a            ; R#2
        ld      a, d
        rlca
        rlca
        and     3
        jr      nz, df_short
        ld      b, (hl)                 ; length byte, 0 = 256
        inc     hl
        otir
        jr      df_run
df_short:
        ld      b, a
        otir
        jr      df_run

; ---------------------------------------------------------------- V9990
v_init:
        ld      a, 2                    ; system reset: every register 0
        out     (P_SYS), a
        xor     a                       ; MCS = 0
        out     (P_SYS), a
        ld      a, 6                    ; R#6-R#15
        out     (P_RSEL), a
        ld      hl, v_regs
        ld      b, v_regs_end - v_regs
        ld      c, P_RDATA
        otir
        ; palette 0-3 from the header (5 bit R, G, B)
        ld      a, 14
        out     (P_RSEL), a
        xor     a
        out     (P_RDATA), a
        ld      hl, hdr + 32
        ld      b, 12
        ld      c, P_PAL
        otir
        ; clear the page (13568 bytes = 53 x 256) to color 0
        xor     a
        out     (P_RSEL), a
        out     (P_RDATA), a
        out     (P_RDATA), a
        out     (P_RDATA), a
        ld      d, 53
        ld      c, P_VRAM
vi_clr: ld      hl, zero256
        ld      b, 0
        otir
        dec     d
        jr      nz, vi_clr
        ; display on, cursors off
        ld      a, 8
        out     (P_RSEL), a
        ld      a, 0C2h
        out     (P_RDATA), a
        ret

; display off again (R#8 DISP = 0), so that a video mixer that shows the
; V9990 while it displays (ZEMMIX OSD Auto) goes back to the V9958
v_off:
        ld      a, (v_on)
        or      a
        ret     z
        xor     a
        ld      (v_on), a
        ld      a, 8
        out     (P_RSEL), a
        ld      a, 42h                  ; display off, no cursors
        out     (P_RDATA), a
        ret

v_regs:
        db      80h                     ; R#6: bitmap, XTAL1/4, 256 wide, 2 bpp (B1, BP2)
        db      00h                     ; R#7: NTSC, non interlaced
        db      42h                     ; R#8: display off (on after the clear), no cursors
        db      00h                     ; R#9: no interrupts
        db      0, 0, 0                 ; R#10-R#12
        db      00h                     ; R#13: palette mode, offset 0
        db      00h                     ; R#14: palette pointer
        db      00h                     ; R#15: backdrop color 0
v_regs_end:

; ---------------------------------------------------------------- audio
; music block after the runs of a frame: byte ticks, then per tick a byte n
; and n (register, value) pairs.  HL = block -> HL after it.
music_in:
        ld      a, (hl)
        inc     hl
        ld      (mc_nt), a
        or      a
        ret     z
        ld      c, a
        ld      a, (audio)
        or      a
        jr      z, mi_skip
        ld      de, (M_WR)
mi_tick:
        ld      a, (hl)                 ; writes of this tick
        ld      (de), a
        inc     hl
        inc     de
        res     3, d
        or      a
        jr      z, mi_next
        ld      b, a
mi_pair:
        ld      a, (hl)
        ld      (de), a
        inc     hl
        inc     de
        res     3, d
        ld      a, (hl)
        ld      (de), a
        inc     hl
        inc     de
        res     3, d
        djnz    mi_pair
mi_next:
        dec     c
        jr      nz, mi_tick
        ld      (M_WR), de
        di
        ld      a, (mc_nt)
        ld      b, a
        ld      a, (M_AVAIL)
        add     a, b
        ld      (M_AVAIL), a
        ei
        ret
mi_skip:                                ; no audio: step over the block
        ld      a, (hl)
        inc     hl
        add     a, a
        ld      e, a
        ld      d, 0
        rl      d
        add     hl, de
        dec     c
        jr      nz, mi_skip
        ret

; OPL4 wave register A = value E (waits for BUSY)
opl_w:
        out     (OPL_WA), a
        call    opl_busy
        ld      a, e
        out     (OPL_WD), a
opl_busy:
        in      a, (OPL_ST)
        rra
        jr      c, opl_busy
        ret

; MoonSound found and the stream has audio: BADAPPLE.OPL to the sample RAM
audio_init:
        ld      a, (hdr + 7)            ; flags: bit 0 audio
        rra
        jr      c, ai_has
        ld      de, s_noaud
        jp      print
ai_has:
        ; NEW2 = 1 (FM array 1, register 05h = 03h): the wave part and BUSY
        ld      a, 5
        out     (OPL_A1), a
        call    ai_delay
        ld      a, 3
        out     (OPL_D1), a
        call    ai_delay
        ld      a, 2                    ; R#2: device ID 001 in bits 7-5
        out     (OPL_WA), a
        call    ai_delay
        in      a, (OPL_WD)
        and     0E0h
        cp      20h
        jr      z, ai_moon
        ld      de, s_nomoon
        jp      print
ai_moon:
        ld      hl, (0006h)             ; FIFO and ISR in page 3
        ld      de, TPA_MIN
        or      a
        sbc     hl, de
        jp      c, err_tpa
        ld      a, 0F8h                 ; FM mix -inf (not used), PCM mix 0 dB
        ld      e, 3Fh
        call    opl_w
        ld      a, 0F9h
        ld      e, 0
        call    opl_w
        call    keys_off
        ; the file: "OPL4", version, -, -, size (4), base (4), -
        ld      de, f_opl
        ld      a, 1
        ld      c, _OPEN
        call    BDOS
        or      a
        jp      nz, err_opl
        ld      a, b
        ld      (ofh), a
        ld      de, opl_hdr
        ld      hl, 16
        ld      c, _READ
        call    BDOS
        or      a
        jp      nz, err_opl
        ld      a, (opl_hdr)
        cp      'O'
        jp      nz, err_opl
        ld      de, s_upload
        call    print
        ; memory access mode, headers of the tones 384-511 at 200000h
        ld      a, 2
        ld      e, 11h
        call    opl_w
        ld      a, 3
        ld      hl, opl_hdr + 14
        ld      e, (hl)
        call    opl_w
        ld      a, 4
        ld      e, 0
        ld      hl, opl_hdr + 13
        ld      e, (hl)
        call    opl_w
        ld      a, 5
        ld      hl, opl_hdr + 12
        ld      e, (hl)
        call    opl_w
        ld      a, 6                    ; the data register stays selected
        out     (OPL_WA), a
        call    opl_busy
        ld      a, (segs)               ; the buffer: the first ring segment
        call    put_p2
ai_block:
        ld      a, (ofh)
        ld      b, a
        ld      de, PAGE2
        ld      hl, CHUNK
        ld      c, _READ
        call    BDOS                    ; HL = bytes read
        ld      a, h
        or      l
        jr      z, ai_done
        push    hl
        ld      e, '.'
        ld      c, _CONOUT
        call    BDOS
        ld      a, 6                    ; select the data register again
        out     (OPL_WA), a
        call    opl_busy
        pop     bc
        ld      hl, PAGE2
ai_byte:
        ld      a, (hl)                 ; 28 master clocks (0.83 us) a byte
        out     (OPL_WD), a
        inc     hl
        dec     bc
        ld      a, b
        or      c
        jr      nz, ai_byte
        jr      ai_block
ai_done:
        ld      a, (ofh)
        ld      b, a
        ld      c, _CLOSE
        call    BDOS
        ld      a, 2                    ; back to playing, headers at 200000h
        ld      e, 10h
        call    opl_w
        ld      de, s_crlf
        call    print
        ld      a, 1
        ld      (audio), a
        ret

ai_delay:
        ld      b, 0
aid:    djnz    aid
        ret

; every wave channel off and silent
keys_off:
        ld      b, 24
        ld      c, 0
ko_loop:
        push    bc
        ld      a, 68h
        add     a, c
        ld      e, 0
        call    opl_w
        pop     bc
        push    bc
        ld      a, 50h
        add     a, c
        ld      e, 0FFh                 ; TL 127: silent
        call    opl_w
        pop     bc
        inc     c
        djnz    ko_loop
        ret

; the ISR to page 3 and on H.TIMI
isr_install:
        ld      a, (audio)
        or      a
        ret     z
        xor     a
        ld      (M_PLAY), a
        ld      (M_AVAIL), a
        ld      hl, 0
        ld      (M_UNDER), hl
        ld      hl, FIFO
        ld      (M_RD), hl
        ld      (M_WR), hl
        ld      hl, isr_code
        ld      de, ISR_ADR
        ld      bc, isr_end - isr_code
        ldir
        di
        ld      hl, H_TIMI
        ld      de, M_OLD
        ld      bc, 5
        ldir
        ld      a, 0C3h
        ld      (H_TIMI), a
        ld      hl, ISR_ADR
        ld      (H_TIMI + 1), hl
        ei
        ld      a, 1
        ld      (hooked), a
        ret

isr_remove:
        ld      a, (hooked)
        or      a
        ret     z
        xor     a
        ld      (hooked), a
        ld      (M_PLAY), a
        di
        ld      hl, M_OLD
        ld      de, H_TIMI
        ld      bc, 5
        ldir
        ei
        jp      keys_off

; H.TIMI routine, copied to ISR_ADR: position independent (jr only)
isr_code:
        push    af                      ; A = VDP status, for the hooks after us
        ld      a, (M_PLAY)
        or      a
        jr      z, isr_chain
        ld      a, (M_AVAIL)
        or      a
        jr      z, isr_under
        dec     a
        ld      (M_AVAIL), a
        ld      hl, (M_RD)
        ld      b, (hl)
        inc     hl
        res     3, h
        ld      a, b
        or      a
        jr      z, isr_done
isr_wr:
        ld      a, (hl)
        inc     hl
        res     3, h
        out     (OPL_WA), a
isr_b1: in      a, (OPL_ST)
        rra
        jr      c, isr_b1
        ld      a, (hl)
        inc     hl
        res     3, h
        out     (OPL_WD), a
isr_b2: in      a, (OPL_ST)
        rra
        jr      c, isr_b2
        djnz    isr_wr
isr_done:
        ld      (M_RD), hl
isr_chain:
        pop     af
        jp      M_OLD
isr_under:
        ld      hl, (M_UNDER)
        inc     hl
        ld      (M_UNDER), hl
        jr      isr_chain
isr_end:

err_opl:
        ld      de, s_eopl
        jp      err
err_tpa:
        ld      de, s_etpa
        jp      err

; ---------------------------------------------------------------- setup
init_mapper:
        ld      a, (HOKVLD)
        rra
        jp      nc, err_mapper
        xor     a
        ld      de, 0402h               ; mapper support routines
        call    EXTBIO
        ld      a, h
        or      l
        jp      z, err_mapper
        ld      (all_seg + 1), hl
        ld      de, 3
        add     hl, de
        ld      (fre_seg + 1), hl
        ld      de, 24h - 3
        add     hl, de
        ld      (put_p2 + 1), hl
        inc     hl
        inc     hl
        inc     hl
        ld      (get_p2 + 1), hl
        call    get_p2
        ld      (orig_p2), a
        ; as many user segments as there are, up to MAXSEG
        ld      hl, segs
im_loop:
        push    hl
        xor     a                       ; user segment
        ld      b, a                    ; primary mapper
        call    all_seg
        pop     hl
        jr      c, im_done
        ld      (hl), a
        inc     hl
        ld      a, (nseg)
        inc     a
        ld      (nseg), a
        cp      MAXSEG
        jr      c, im_loop
im_done:
        ld      a, (nseg)
        cp      2
        jp      c, err_mapper
        ret

open_file:
        ld      de, f_name
        ld      a, 1                    ; read only
        ld      c, _OPEN
        call    BDOS
        or      a
        jp      nz, err_open
        ld      a, b
        ld      (fh), a
        ld      de, hdr
        ld      hl, 512
        ld      c, _READ
        call    BDOS
        or      a
        jp      nz, err_read
        ld      hl, hdr
        ld      de, magic
        ld      b, 5                    ; "BA99" and version 2
of_cmp: ld      a, (de)
        cp      (hl)
        jp      nz, err_format
        inc     hl
        inc     de
        djnz    of_cmp
        ; chunks = data size / 16 KB (bytes 20-23 of the header)
        ld      a, (hdr + 21)
        rlca
        rlca
        and     3
        ld      l, a
        ld      a, (hdr + 22)
        add     a, a
        add     a, a
        or      l
        ld      l, a
        ld      a, (hdr + 22)
        rlca
        rlca
        and     3
        ld      h, a
        ld      a, (hdr + 23)
        add     a, a
        add     a, a
        or      h
        ld      h, a
        ld      (chunks), hl
        ret

set_cpu:
        ld      iy, (EXPTBL - 1)
        ld      ix, CHGCPU
        call    CALSLT
        ei
        ret

; mapper support routines (patched)
all_seg: jp     0
fre_seg: jp     0
put_p2: jp      0
get_p2: jp      0

; ---------------------------------------------------------------- text
print:
        ld      c, _STROUT
        jp      BDOS

; HL in decimal
prnum:
        ld      b, 0                    ; digits printed
        ld      de, 10000
        call    pn_dig
        ld      de, 1000
        call    pn_dig
        ld      de, 100
        call    pn_dig
        ld      de, 10
        call    pn_dig
        ld      b, 1
        ld      de, 1
pn_dig:
        ld      a, '0' - 1
pn_sub: inc     a
        or      a
        sbc     hl, de
        jr      nc, pn_sub
        add     hl, de
        cp      '0'
        jr      nz, pn_out
        inc     b
        dec     b
        ret     z                       ; no leading zeros
pn_out: ld      b, 1
        push    hl
        push    bc
        ld      e, a
        ld      c, _CONOUT
        call    BDOS
        pop     bc
        pop     hl
        ret

err_mapper:
        ld      de, s_emap
        jr      err
err_open:
        ld      de, s_eopen
        jr      err
err_read:
        ld      de, s_eread
        jr      err
err_format:
        ld      de, s_eform
err:
        call    print
        call    isr_remove
        call    v_off
        ld      a, (r800)
        or      a
        ld      a, 80h
        call    nz, set_cpu
        ld      b, 0
        ld      c, _TERM
        jp      BDOS

f_name: db      "BADAPPLE.V99", 0
magic:  db      "BA99", 3
s_title: db     "Bad Apple!! V9990 player", 13, 10, "$"
s_late: db      "late frames: $"
s_under: db     ", underruns: $"
s_crlf: db      13, 10, "$"
s_short: db     "stream too short", 13, 10, "$"
s_emap: db      "no mapper segments", 13, 10, "$"
s_eopen: db     "BADAPPLE.V99 not found", 13, 10, "$"
s_eread: db     "read error", 13, 10, "$"
s_eform: db     "not a BADAPPLE.V99 version 3", 13, 10, "$"
s_munder: db    ", music underruns: $"
s_nomoon: db    "no MoonSound: video only", 13, 10, "$"
s_noaud: db     "no audio in the stream", 13, 10, "$"
s_upload: db    "BADAPPLE.OPL to the OPL4 $"
s_eopl: db      "BADAPPLE.OPL not found or bad", 13, 10, "$"
s_etpa: db      "TPA too small", 13, 10, "$"
f_opl:  db      "BADAPPLE.OPL", 0
opl_hdr: ds     16

r800:   db      0
audio:  db      0               ; 1: MoonSound found and loaded
hooked: db      0
v_on:   db      0
mc_nt:  db      0
fh:     db      0
ofh:    db      0
orig_p2: db     0
nseg:   db      0
cur:    db      0               ; ring index being decoded
fill:   db      0               ; ring index being filled
ready:  db      0               ; chunks read and not decoded yet
fillofs: dw     0
chunks: dw      0               ; chunks of the file not read yet
rdptr:  dw      0
frames: dw      0
next:   dw      0
late:   dw      0
under:  dw      0
segs:   ds      MAXSEG
zero256: ds     256
hdr:    ds      512

        if      $ > 4000h
        .error  code over page 0
        endif
