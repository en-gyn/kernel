
%include "boot.inc"

SECTION MBR vstart=0x7c00

mov ax,cs
mov ds,ax
mov es,ax
mov ss,ax
mov fs,ax
mov sp,0x7c00
mov ax,0xb800
mov gs,ax
mov ax,0600h
mov bx,0700h
mov cx,0
mov dx,184fh

int 10h

mov byte [gs:0x00],'1'
mov byte [gs:0x01],0xA4

mov byte [gs:0x02],' '
mov byte [gs:0x03],0xA4

mov byte [gs:0x04],'M'
mov byte [gs:0x05],0xA4

mov byte [gs:0x06],'B'
mov byte [gs:0x07],0xA4

mov byte [gs:0x08],'R'
mov byte [gs:0x09],0xA4

mov eax,LOADER_BASE_SECTOR
mov bx,LOADER_BASE_ADDR
mov cx,0x01
call rd_risk

jmp LOADER_BASE_ADDR


rd_risk:
   ;sector_count
    mov esi,eax
    mov al,cl
    mov dx,sector_count
    out dx,al
    ;low
    mov eax,esi
    mov di,cx
    mov cx,0x8
    mov dx,lba_low
    out dx,al
    ;mid
    shr eax,cl
    mov dx,lba_mid
    out dx,al
    ;high
    shr eax,cl
    mov dx,lba_high
    out dx,al
    ;device
    shr eax,cl
    or al,0xf0
    mov dx,device
    out dx,al
    ;commond
    mov eax,0x20
    mov dx,commond
    out dx,al

.not_on_ready:
    mov dx,status
    in al,dx
    and al,0x88
    cmp al,0x08
    jnz .not_on_ready

    mov ax,di
    mov dx,$256
    mul dx

    mov cx,ax
.go_on_ready:
    in ax,dx
    mov bx,LOADER_BASE_ADDR
    mov [bx],ax
    add bx,2
    loop .go_on_ready

    ret


times 510-($-$$) db 0
db 0x55,0xAA
