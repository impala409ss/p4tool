; p4tool.asm
; Build:
;   nasm -f bin src/p4tool.asm -o p4tool.com
;
; DOS performance tool for Pentium 4 / NetBurst
;
; This program is intended Pentium 4 / NetBurst CPUs.
; Portability to later Intel microarchitectures is NOT a goal in this version.
; Do not reuse this code on Core/Core2 or newer CPUs.
;
; FORCE option:
; When "force" is present, the program skips the Pentium 4 / NetBurst model
; check and runs on any CPU that supports CPUID. This option exists only for
; experimental use and does not imply correctness on non-NetBurst hardware.
; MSR layouts and semantics may differ on later Intel CPUs.

org 100h
bits 16
cpu 686

%define MSR_IA32_DEBUGCTL       0x1D9
%define MSR_IA32_CLOCK_MOD      0x19A
%define MSR_IA32_DS_AREA        0x600
%define MSR_IA32_MTRRCAP        0x0FE
%define MSR_MTRR_BASE0          0x200
%define MSR_MTRR_MASK0          0x201
%define MSR_MTRR_DEFTYPE        0x2FF

%define MTRR_TYPE_UC            0x00
%define MTRR_TYPE_WC            0x01
%define MTRR_TYPE_WT            0x04
%define MTRR_TYPE_WP            0x05
%define MTRR_TYPE_WB            0x06

%define MTRR_DEFTYPE_MASK       0x00000c00
%define MTRR_DEFTYPE_UC         0x00000000
%define MTRR_DEFTYPE_WB         0x00000c00
%define MTRR_DEFTYPE_WT         0x00000400

%define DEBUGCTLA_LBR          (1<<0)
%define DEBUGCTLA_BTF          (1<<1)
%define DEBUGCTLA_TR           (1<<2)
%define DEBUGCTLA_BTS          (1<<3)
%define DEBUGCTLA_BTINT        (1<<4)
%define DEBUGCTLA_BTS_OFF_OS   (1<<5)
%define DEBUGCTLA_BTS_OFF_USR  (1<<6)

%define ERR_NONE                0
%define ERR_UNKNOWN             1
%define ERR_CONFLICT            2

align 64
ds_area:
    times 32 db 0

align 64
bts_buffer:
    times 32 db 0

end_resident:

start:
    push cs
    pop ds
    push cs
    pop es

    call parse_command_line
    cmp byte [parse_error], ERR_NONE
    jne  show_parse_error_and_exit

    cmp byte [arg_seen], 0
    je  show_help_and_exit

    call check_cpuid_present
    jc  not_supported

    cmp byte [act_force], 1
    je  .skip_netburst_check

    call check_netburst_family
    jc  not_supported

.skip_netburst_check:

    ; apply in order:
    ; 1) MTRR
    ; 2) BTS
    ; 3) ODCM
    ; 4) final cache state

    cmp byte [act_mtrr], 0
    je  .no_mtrr
    mov al, [act_mtrr]
    call apply_mtrr_mainram_type
    jc  action_failed
.no_mtrr:

    cmp byte [act_dstr], 0
    je  .no_bts
    mov al, [act_dstr]
    call apply_dstr
    jc  action_failed
.no_bts:

    cmp byte [act_odcm], 0
    je  .no_odcm
    mov al, [act_odcm]
    call apply_odcm
    jc  action_failed
.no_odcm:

    cmp byte [act_cache], 0
    je  .no_cache
    mov al, [act_cache]
    call apply_cache
    jc  action_failed

.no_cache:
    call print_crlf
    call show_status

    cmp byte [act_res], 0
    je .exit

    lea dx, [end_resident]
    add dx, 15
    shr dx, 4
    mov  ax, 3100h
    int  21h

.exit:
    mov ax, 4C00h
    int 21h

.done_no_status:
    mov dx, msg_ok
    call print_dollar
    mov ax, 4C00h
    int 21h

show_help_and_exit:
    call print_p4tool_header
    mov dx, msg_help
    call print_dollar
    mov ax, 4C00h
    int 21h

show_parse_error_and_exit:
    cmp byte [parse_error], ERR_CONFLICT
    je  .conflict
    mov dx, msg_unknown_arg
    call print_dollar
    jmp .tok

.conflict:
    mov dx, msg_conflict_arg
    call print_dollar

.tok:
    mov dx, err_token
    call print_asciiz
    call print_crlf
    mov ax, 4C03h
    int 21h

not_supported:
    mov dx, msg_not_supported
    call print_dollar
    mov ax, 4C01h
    int 21h

action_failed:
    mov dx, msg_failed
    call print_dollar
    mov ax, 4C02h
    int 21h

; ------------------------------------------------------------
; basic output
; ------------------------------------------------------------
print_dollar:
    pushad
    mov ah, 09h
    int 21h
    popad
    ret

print_char:
    pushad
    mov ah, 02h
    int 21h
    popad
    ret

print_crlf:
    mov dl, 13
    call print_char
    mov dl, 10
    call print_char
    ret

print_space:
    mov dl, ' '
    call print_char
    ret

print_asciiz:
    push ax
    push bx
    mov bx, dx
.next:
    mov al, [bx]
    test al, al
    jz   .done
    mov dl, al
    call print_char
    inc bx
    jmp .next
.done:
    pop bx
    pop ax
    ret

print_label_asciiz:
    call print_asciiz
    ret

print_hex_nibble:
    and al, 0Fh
    cmp al, 9
    jbe .num
    add al, 7
.num:
    add al, '0'
    mov dl, al
    call print_char
    ret

print_hex8:
    push ax
    mov ah, al
    shr al, 4
    call print_hex_nibble
    mov al, ah
    call print_hex_nibble
    pop ax
    ret

print_hex16:
    push ax
    mov al, ah
    call print_hex8
    pop ax
    call print_hex8
    ret

print_hex32_eax:
    push ax
    push bx
    push cx
    mov bx, ax
    shr eax, 16
    mov cx, ax
    mov ax, cx
    call print_hex16
    mov ax, bx
    call print_hex16
    pop cx
    pop bx
    pop ax
    ret

print_hex64_edx_eax:
    push ax
    push dx
    push bx
    push cx
    push si

    mov bx, ax
    mov cx, dx
    shr edx, 16
    mov si, dx
    mov ax, si
    call print_hex16
    mov ax, cx
    call print_hex16

    mov ax, bx
    shr eax, 16
    mov cx, ax
    mov ax, cx
    call print_hex16
    mov ax, bx
    call print_hex16

    pop si
    pop cx
    pop bx
    pop dx
    pop ax
    ret

; ------------------------------------------------------------
; parse command line
; ------------------------------------------------------------
parse_command_line:
    mov byte [arg_seen], 0
    mov byte [parse_error], ERR_NONE
    mov byte [err_token], 0

    mov si, 81h
    xor bx, bx
    mov bl, [80h]
    xor bh, bh
    add bx, si              ; BX = end

.next_token:
    call skip_spaces
    cmp si, bx
    jae .done

    call read_token_to_buffer
    cmp cx, 0
    je  .done

    mov byte [arg_seen], 1

    push si
    call handle_token
    pop si
    cmp byte [parse_error], ERR_NONE
    jne .done

    jmp .next_token

.done:
    ret

skip_spaces:
.loop:
    cmp si, bx
    jae .done
    mov al, [si]
    cmp al, ' '
    je  .skip
    cmp al, 9
    jne .done
.skip:
    inc si
    jmp .loop
.done:
    ret

read_token_to_buffer:
    push di
    mov di, token_buf
    xor cx, cx
.loop:
    cmp si, bx
    jae .finish
    mov al, [si]
    cmp al, ' '
    je  .finish
    cmp al, 9
    je  .finish
    call tolower_al
    cmp cx, TOKEN_MAX-1
    jae .advance_only
    mov [di], al
    inc di
    inc cx
.advance_only:
    inc si
    jmp .loop
.finish:
    mov byte [di], 0
    pop di
    ret

handle_token:
    ; status
    mov si, token_buf
    mov di, tok_status
    call strcmp_z
    jc  .chk_force
    mov byte [act_status], 1
    ret

.chk_force:
    mov si, token_buf
    mov di, tok_force
    call strcmp_z
    jc  .chk_cd
    mov byte [act_force], 1
    ret

.chk_cd:
    mov si, token_buf
    mov di, tok_cd
    call strcmp_z
    jc  .chk_ce
    cmp byte [act_cache], 0
    jne .conflict
    mov byte [act_cache], 1
    ret

.chk_ce:
    mov si, token_buf
    mov di, tok_ce
    call strcmp_z
    jc  .chk_o1
    cmp byte [act_cache], 0
    jne .conflict
    mov byte [act_cache], 2
    ret

.chk_o1:
    mov si, token_buf
    mov di, tok_o1
    call strcmp_z
    jc  .chk_o2
    jmp .set_o1
.chk_o2:
    mov si, token_buf
    mov di, tok_o2
    call strcmp_z
    jc  .chk_o3
    jmp .set_o2
.chk_o3:
    mov si, token_buf
    mov di, tok_o3
    call strcmp_z
    jc  .chk_o4
    jmp .set_o3
.chk_o4:
    mov si, token_buf
    mov di, tok_o4
    call strcmp_z
    jc  .chk_o5
    jmp .set_o4
.chk_o5:
    mov si, token_buf
    mov di, tok_o5
    call strcmp_z
    jc  .chk_o6
    jmp .set_o5
.chk_o6:
    mov si, token_buf
    mov di, tok_o6
    call strcmp_z
    jc  .chk_o7
    jmp .set_o6
.chk_o7:
    mov si, token_buf
    mov di, tok_o7
    call strcmp_z
    jc  .chk_o8
    jmp .set_o7
.chk_o8:
    mov si, token_buf
    mov di, tok_o8
    call strcmp_z
    jc  .chk_dsbts
    jmp .set_o8

.set_o1:
    cmp byte [act_odcm], 0
    jne .conflict
    mov byte [act_odcm], 1
    ret
.set_o2:
    cmp byte [act_odcm], 0
    jne .conflict
    mov byte [act_odcm], 2
    ret
.set_o3:
    cmp byte [act_odcm], 0
    jne .conflict
    mov byte [act_odcm], 3
    ret
.set_o4:
    cmp byte [act_odcm], 0
    jne .conflict
    mov byte [act_odcm], 4
    ret
.set_o5:
    cmp byte [act_odcm], 0
    jne .conflict
    mov byte [act_odcm], 5
    ret
.set_o6:
    cmp byte [act_odcm], 0
    jne .conflict
    mov byte [act_odcm], 6
    ret
.set_o7:
    cmp byte [act_odcm], 0
    jne .conflict
    mov byte [act_odcm], 7
    ret
.set_o8:
    cmp byte [act_odcm], 0
    jne .conflict
    mov byte [act_odcm], 8
    ret

.chk_dsbts:
    mov si, token_buf
    mov di, tok_dsbts
    call strcmp_z
    jc  .chk_dstr
    cmp byte [act_dstr], 0
    jne .conflict
    mov byte [act_dstr], 3
    ret

.chk_dstr:
    mov si, token_buf
    mov di, tok_dstr
    call strcmp_z
    jc  .chk_dstrd
    cmp byte [act_dstr], 0
    jne .conflict
    mov byte [act_dstr], 1
    ret

.chk_dstrd:
    mov si, token_buf
    mov di, tok_dstrd
    call strcmp_z
    jc  .chk_mtrr0uc
    cmp byte [act_dstr], 0
    jne .conflict
    mov byte [act_dstr], 2
    ret

.chk_mtrr0uc:
    mov si, token_buf
    mov di, tok_mtrr0uc
    call strcmp_z
    jc  .chk_mtrr0wb
    cmp byte [act_mtrr], 0
    jne .conflict
    mov byte [act_mtrr], 1
    ret

.chk_mtrr0wb:
    mov si, token_buf
    mov di, tok_mtrr0wb
    call strcmp_z
    jc  .chk_mtrr0wt
    cmp byte [act_mtrr], 0
    jne .conflict
    mov byte [act_mtrr], 2
    ret

.chk_mtrr0wt:
    mov si, token_buf
    mov di, tok_mtrr0wt
    call strcmp_z
    jc  .unknown
    cmp byte [act_mtrr], 0
    jne .conflict
    mov byte [act_mtrr], 3
    ret

.unknown:
    mov byte [parse_error], ERR_UNKNOWN
    call copy_token_for_error
    ret

.conflict:
    mov byte [parse_error], ERR_CONFLICT
    call copy_token_for_error
    ret

copy_token_for_error:
    push si
    push di
    mov si, token_buf
    mov di, err_token
.loop:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    test al, al
    jnz .loop
    pop di
    pop si
    ret

strcmp_z:
    ; CF=0 equal, CF=1 not equal
.loop:
    mov al, [si]
    mov ah, [di]
    cmp al, ah
    jne .ne
    test al, al
    jz   .eq
    inc si
    inc di
    jmp .loop
.eq:
    clc
    ret
.ne:
    stc
    ret

tolower_al:
    cmp al, 'A'
    jb  .done
    cmp al, 'Z'
    ja  .done
    or  al, 20h
.done:
    ret

; ------------------------------------------------------------
; CPUID checks
; ------------------------------------------------------------
check_cpuid_present:
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 1 << 21
    push eax
    popfd
    pushfd
    pop eax
    xor eax, ecx
    test eax, 1 << 21
    jz  .fail
    clc
    ret
.fail:
    stc
    ret

check_netburst_family:
    xor eax, eax
    cpuid
    cmp ebx, 756E6547h      ; Genu
    jne .fail
    cmp edx, 49656E69h      ; ineI
    jne .fail
    cmp ecx, 6C65746Eh      ; ntel
    jne .fail

    mov eax, 1
    cpuid

    mov esi, eax
    shr esi, 8
    and esi, 0Fh

    mov edi, eax
    shr edi, 20
    and edi, 0FFh

    cmp esi, 0Fh
    jne .fail
    add esi, edi
    cmp esi, 0Fh
    jne .fail

    clc
    ret
.fail:
    stc
    ret

; ------------------------------------------------------------
; actions
; ------------------------------------------------------------
apply_cache:
    pushad
    mov ebx, MTRR_DEFTYPE_UC
    cmp al, 1
    je  .process_mtrr_deftype
    mov ebx, MTRR_DEFTYPE_WB
    cmp al, 2
    je  .process_mtrr_deftype
    popad
    stc
    ret

.process_mtrr_deftype:
    cli
    mov ecx, MSR_MTRR_DEFTYPE
    rdmsr
    and eax, ~MTRR_DEFTYPE_MASK
    or eax, ebx
    wrmsr
    sti
    popad
    clc
    ret

apply_odcm:
    mov eax, 1
    cpuid
    bt  edx, 22
    jnc .fail

    mov ecx, MSR_IA32_CLOCK_MOD
    rdmsr
    and eax, ~001Fh

    cmp byte [act_odcm], 8
    je  .write

    xor ebx, ebx
    mov bl, [act_odcm]
    shl ebx, 1
    or  eax, ebx
    or  eax, (1 << 4)
.write:
    wrmsr
    clc
    ret
.fail:
    stc
    ret

apply_dstr:
    push eax
    mov ecx, MSR_IA32_DEBUGCTL
    rdmsr
    and eax, ~DEBUGCTLA_BTS
    wrmsr
    pop eax
    cmp al, 1
    je .enable
    cmp al, 2
    je .disable
    cmp al, 3
    je .enable_bts
    stc
    ret

.enable_bts:
    mov ecx, MSR_IA32_DS_AREA
    rdmsr
    test eax, eax
    jne .skip_ds
    mov [act_res], 1

    ; ---------- Compute linear base for ds_area  ----------
    xor  eax, eax
    mov  ax, cs
    shl  eax, 4                  ; EAX = linear base of CS segment

    mov  ebx, eax
    add  ebx, ds_area            ; EBX = linear addr of ds_area

    add  eax, bts_buffer	 ; EAX = linear addr of bts_buffer

    ; ----------  Init DS area ----------
    mov  [ds_area + 0], eax
    mov  dword [ds_area + 4], 0

    mov  [ds_area + 8], 0
    mov  dword [ds_area + 12], 0
    
    add  eax, 32
    mov  [ds_area + 16], eax
    mov  dword [ds_area + 20], 0

    mov  [ds_area + 24], 0
    mov  dword [ds_area + 28], 0

    mov ecx, MSR_IA32_DS_AREA
    mov eax, ebx
    xor edx, edx
    wrmsr

.skip_ds:
    mov ecx, MSR_IA32_DEBUGCTL
    rdmsr
    or  eax, DEBUGCTLA_BTS
    wrmsr

.enable:
    mov ecx, MSR_IA32_DEBUGCTL
    rdmsr
    or  eax, DEBUGCTLA_TR
    wrmsr
    clc
    ret

.disable:
    mov ecx, MSR_IA32_DEBUGCTL
    rdmsr
    and eax, ~(DEBUGCTLA_TR | DEBUGCTLA_BTS | DEBUGCTLA_BTINT)
    wrmsr
    clc
    ret

.fail:
    stc
    ret

apply_mtrr_mainram_type:
    push ax

    cmp al, 1
    je  .type_uc
    cmp al, 2
    je  .type_wb
    cmp al, 3
    je  .type_wt
    pop ax
    stc
    ret

.type_uc:
    mov bl, MTRR_TYPE_UC
    jmp .scan
.type_wb:
    mov bl, MTRR_TYPE_WB
    jmp .scan
.type_wt:
    mov bl, MTRR_TYPE_WT

.scan:
    call find_mtrr_base0
    jc  .fail_pop

    mov ax, di
    mov [mtrr_index], ax

    cli
    xor ecx, ecx
    mov cx, [mtrr_index]
    shl ecx, 1
    add ecx, MSR_MTRR_BASE0
    rdmsr
    and eax, 0FFFFFF00h
    movzx ebp, bl
    or  eax, ebp
    wrmsr
    wbinvd
    sti

    pop ax
    clc
    ret

.fail_pop:
    pop ax
    stc
    ret

find_mtrr_base0:
    ; CF=0 found, DI=index
    mov ecx, MSR_IA32_MTRRCAP
    rdmsr
    movzx si, al
    cmp si, 0
    je  .fail

    xor di, di
.loop:
    cmp di, si
    jae .fail

    movzx ecx, di
    shl ecx, 1
    add ecx, MSR_MTRR_MASK0
    rdmsr
    bt  eax, 11
    jnc .next

    movzx ecx, di
    shl ecx, 1
    add ecx, MSR_MTRR_BASE0
    rdmsr

    cmp edx, 0
    jne .next
    mov ebp, eax
    and ebp, 0FFFFFF00h
    cmp ebp, 0
    je  .ok

.next:
    inc di
    jmp .loop

.ok:
    clc
    ret
.fail:
    stc
    ret

show_status:
    cmp byte [act_status], 1
    jne .dont_print_p4tool_header
    call print_p4tool_header
.dont_print_p4tool_header:
    call print_status_header
    call show_status_cache_sem
    call show_status_mainram_mtrr_sem
    call show_status_debugstorage_sem
    call show_status_odcm_sem
    ret

print_p4tool_header:
    mov edx, txt_p4tool_header
    call print_asciiz
    ret

print_status_header:
    mov dx, txt_status_header
    call print_asciiz
    ret

show_status_cache_sem:
    mov dx, txt_cache_sem
    call print_asciiz

    mov ecx, MSR_MTRR_DEFTYPE
    rdmsr
    and eax, MTRR_DEFTYPE_MASK
    cmp eax, MTRR_DEFTYPE_WB
    je  .enabled

    mov dx, txt_disabled
    call print_asciiz
    call print_crlf
    ret

.enabled:
    mov dx, txt_enabled
    call print_asciiz
    call print_crlf
    ret


show_status_mainram_mtrr_sem:
    mov dx, txt_mainram_mtrr_sem
    call print_asciiz

    call find_mtrr_base0
    jc  .unknown

    xor ecx, ecx
    mov cx, di
    shl ecx, 1
    add ecx, MSR_MTRR_BASE0
    rdmsr

    and eax, 0FFh
    cmp al, MTRR_TYPE_WB
    je  .wb
    cmp al, MTRR_TYPE_WT
    je  .wt
    cmp al, MTRR_TYPE_UC
    je  .uc
    jmp .unknown

.wb:
    mov dx, txt_writeback
    jmp .print
.wt:
    mov dx, txt_writethrough
    jmp .print
.uc:
    mov dx, txt_uncachable
    jmp .print

.unknown:
    mov dx, txt_unknown

.print:
    call print_asciiz
    call print_crlf
    ret


show_status_debugstorage_sem:
    mov dx, txt_debugstorage_sem
    call print_asciiz

    mov ecx, MSR_IA32_DEBUGCTL
    rdmsr

    bt eax, 2
    jnc .disabled

    bt eax, 3
    jc  .enabled_bts

    mov dx, txt_enabled
    jmp .print

.enabled_bts:
    mov dx, txt_enabled_with_bts
    jmp .print

.disabled:
    mov dx, txt_disabled

.print:
    call print_asciiz
    call print_crlf
    ret


show_status_odcm_sem:
    mov dx, txt_odcm_sem
    call print_asciiz

    mov ecx, MSR_IA32_CLOCK_MOD
    rdmsr

    bt eax, 4
    jnc .disabled

    mov ebx, eax
    shr ebx, 1
    and ebx, 7
    cmp bl, 0
    je  .reserved

    mov al, bl
    add al, '0'
    mov dl, al
    call print_char
    mov dl, '/'
    call print_char
    mov dl, '8'
    call print_char
    call print_crlf
    ret

.reserved:
    mov dx, txt_reserved
    call print_asciiz
    call print_crlf
    ret

.disabled:
    mov dx, txt_disabled
    call print_asciiz
    call print_crlf
    ret

; ------------------------------------------------------------
; data
; ------------------------------------------------------------
TOKEN_MAX       equ 16

arg_seen        db 0
parse_error     db 0

act_res         db 0    ; 0 no TSR
act_cache       db 0    ; 0 none, 1 disable, 2 enable
act_odcm        db 0    ; 0 none, 1..8
act_dstr        db 0    ; 0 none, 1 enable, 2 disable
act_mtrr        db 0    ; 0 none, 1 UC, 2 WB, 3 WT
act_force       db 0    ; 0 no, 1 yes
act_status      db 0    ; 0 no, 1 yes

mtrr_index      dw 0
saved_cr0       dd 0
saved_def_lo    dd 0
saved_def_hi    dd 0

token_buf       times TOKEN_MAX db 0
err_token       times TOKEN_MAX db 0
vendor_buf      times 13 db 0

tok_cd          db 'cd',0
tok_ce          db 'ce',0
tok_o1          db 'o1',0
tok_o2          db 'o2',0
tok_o3          db 'o3',0
tok_o4          db 'o4',0
tok_o5          db 'o5',0
tok_o6          db 'o6',0
tok_o7          db 'o7',0
tok_o8          db 'o8',0
tok_dsbts	db 'dsbts',0
tok_dstr        db 'ds',0
tok_dstrd       db 'dsd',0
tok_mtrr0uc     db 'mtrr0uc',0
tok_mtrr0wb     db 'mtrr0wb',0
tok_mtrr0wt     db 'mtrr0wt',0
tok_force       db 'force',0
tok_status      db 'status',0

msg_ok db 13,10
       db 'Done.',13,10,'$'

msg_failed db 13,10
           db 'Error: action failed or target MSR/MTRR not found.',13,10,'$'

msg_unknown_arg db 13,10
                db 'Error: unknown argument: ','$'

msg_conflict_arg db 13,10
                 db 'Error: conflicting argument: ','$'

msg_not_supported db 13,10
                  db 'Error: unsupported CPU.',13,10
                  db 'This program requires Intel Pentium 4 / NetBurst (family 0Fh).',13,10
                  db 'Use FORCE to bypass the NetBurst model check at your own risk.',13,10,'$'

msg_help db 13,10
         db 'Usage:     P4TOOL [args...]',13,10
         db 13,10
         db 'Arguments:',13,10
         db '  cd       Disable cache (DefTypeMTRR)',13,10
         db '  ce       Enable cache  (DefTypeMTRR)',13,10
         db '  o1       ODCM 1/8 duty',13,10
         db '  o2       ODCM 2/8 duty',13,10
         db '  o3       ODCM 3/8 duty',13,10
         db '  o4       ODCM 4/8 duty',13,10
         db '  o5       ODCM 5/8 duty',13,10
         db '  o6       ODCM 6/8 duty',13,10
         db '  o7       ODCM 7/8 duty',13,10
         db '  o8       ODCM 8/8 duty (ODCM Disabled)',13,10
         db '  ds       Enable DebugStore transactions without BTS',13,10
         db '  dsbts    Enable DebugStore transactions with BTS (one time TSR)',13,10
         db '  dsd      Disable DebugStore transactions',13,10
         db '  mtrr0uc  Set main RAM MTRR (base 0) to UnCached',13,10
         db '  mtrr0wb  Set main RAM MTRR (base 0) to WriteBack',13,10
         db '  mtrr0wt  Set main RAM MTRR (base 0) to WriteThrough',13,10
         db '  force    Force execution even if CPUID does not identify NetBurst',13,10
         db '  status   Show current status',13,10
         db 'You may combine arguments, except conflicting ones in the same group.'
         db '$'

txt_p4tool_header       db 'P4TOOL - Pentium 4 / NetBurst performance tool | OttoPS ;)',13,10,0
txt_status_header       db 13,10, 'Current status:',13,10,0
txt_cache_sem           db 'Cache (DefTypeMTRR):       ',0
txt_mainram_mtrr_sem    db 'Main RAM MTRR (base 0):    ',0
txt_debugstorage_sem    db 'DebugStorage:              ',0
txt_odcm_sem            db 'ODCM:                      ',0

txt_enabled             db 'Enabled',0
txt_disabled            db 'Disabled',0
txt_enabled_with_bts    db 'Enabled with BTS',0

txt_writeback           db 'WriteBack',0
txt_writethrough        db 'WriteThrough',0
txt_uncachable          db 'UnCachable',0
txt_unknown             db 'Unknown',0
txt_reserved            db 'Reserved',0
