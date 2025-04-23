

%include "boot.inc"

SECTION LOADER vstart=LOADER_BASE_ADDR

mov ax,cs
mov ds,ax
mov es,ax
mov ss,ax
mov fs,ax
mov ax,0xb800
mov gs,ax
mov ax,0600h
mov bx,0700h
mov cx,0
mov dx,184fh

int 10h

mov byte [gs:0x00],'2'
mov byte [gs:0x01],0xA4

mov byte [gs:0x02],' '
mov byte [gs:0x03],0xA4

mov byte [gs:0x04],'L'
mov byte [gs:0x05],0xA4

mov byte [gs:0x06],'O'
mov byte [gs:0x07],0xA4

mov byte [gs:0x08],'D'
mov byte [gs:0x09],0xA4

jmp $