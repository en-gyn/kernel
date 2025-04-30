
%include "boot.inc"

SECTION LOADER vstart=LOADER_BASE_ADDR

LOADER_STACK_TOP equ LOADER_BASE_ADDR

;构建gdt及其内部的描述符
    GDT_BASE: dd 0x00000000
              dd 0x00000000

;GDT第0个是空的
    CODE_DESC:dd 0x0000FFFF
               dd DESC_CODE_HIGH4
    DATA_STACK_DESC:dd 0x0000FFFF
                    dd DESC_DATA_HIGH4

    VIDEO_DESC:dd 0x80000007;limit=(0xbffff-0xb8000)
                dd DESC_VIDEO_HIGH4 ;此时dpl为0

    GDT_SIZE equ $-GDT_BASE
    GDT_LIMIT equ GDT_SIZE-1

 times 60 dq 0   ;预留60个描述符位

  ;total_mem_bytes用于保存内存容量，以字节为单位，此位置比较好及
  ;当前便宜loader.bin文件头0x200字节
  ;loader.bin的加载地址是0x900
  ;故total_mem_bytes内存中的地址是0xb00
  ;将来在内核中在咱们会引用此地址
  total_mem_bytes dd 0;

 ;以下是gdt指针，前两字节是gdt界限，后4字节是gdt起始地址
    gdt_ptr dw GDT_LIMIT
            dd GDT_BASE
  ;人工对齐：total_mem_bytes4+get_ptr6+ards_buf244+ards_nr2,共256字节
     ards_buf times 244 db 0
     ards_nr dw 0


 loader_start:

 ;_________________________________________________
 ;int 15h eax=0000E820h,edx=534D4150h ('SMAP')获取内存布局v
      xor ebx,ebx;第一次调用时，ebx值要为0
      mov edx,0x534d4150;edx只赋值一次，循环体中不会改变
      mov di,ards_buf;ards结构体缓冲区
.e820_mem_get_loop:
      mov eax,0x0000e820;执行int 0x15后，eax的值变为0x534d4150,所以每次执行int前都要更新为子功能号
      mov ecx,20
      int 0x15
      jc .e820_failed_so_try_e801
;若cf位为1则有错误发生，尝试0xe801子功能
      add di,cx;使di增加20字节指向缓冲区中新的ARDS结构位置
      inc word [ards_nr];记录 ARDS 数量
      cmp ebx,0 ;若ebx为0，且cf不为1,这说明ards全部返回
      jnz .e820_mem_get_loop
    ;在所有ards结构中
    ;找出（base_add_low + length_low)的最大值，即内存的容量
      mov cx,[ards_nr]
      ;遍历每一个ARDS机构体，循环次数是ARDS的数量
      mov ebx,ards_buf
      xor edx,edx
.find_max_mem_area:
      mov eax,[ebx];无需判断type是否为1,最大的内存块一定是可被使用的
      add eax,[ebx+8]
      add ebx,20
      cmp edx,eax
      jge .next_ards
    ;冒泡排序，找出最大，edx寄存器始终是最大的内存容量
      mov edx,eax

.next_ards:
      loop .find_max_mem_area
      jmp .mem_get_ok


    ;_____int 15h ax =E801h 获取内存大小，最大支持4G——————
    ;返回后，ax cx值一样，以KB为单位，bx dx值一样，以64KB为单位
    ;在ax和cx寄存器中为低16MB，在bx和dx寄存器中为16MB到4GB
.e820_failed_so_try_e801:
    mov eax,0x0000e801
    int 0x15
    jc .e801_failed_so_try88
    ;1先算出低15MB的内存
    ;ax和cx中是以KB为单位的内存数量，将其转换为以byte为单位
    mov cx,0x400
    mul cx
    shl edx,16
    and eax,0x0000FFFF
    or edx,eax
    add edx,0x100000
    mov esi,edx

    ;2再将16MB以上的内存转换为byte为单位
    ;寄存器bx和dx中是以64KB为单位的内存数量
    xor eax,eax
    mov ax,bx
    mov ecx,0x10000
    mul ecx

    add esi,eax
    ;由于此方法只能测出4GB以内的内存，故32位eax足够了
    ;edx肯定为0,只加eax便可
    mov edx,esi
    jmp .mem_get_ok

    ;____ int 15h ah =0x88获取内存大小，只能获取64MB之内————————
.e801_failed_so_try88:
    ;int 15后，ax存入的是以KB为单位的内存容量
    mov ah,0x88
    int 0x15
    jc error_hlt
    and eax,0x0000FFFF
    ;16位乘法，被乘数是ax，积为32位。积的高16位在dx中
    ;积的低 16 位在 ax
    mov cx,0x400
    ;Ox400 等于 1024 ，将 ax 中的内存容量换为以 byte 为单位
    mul cx
    shl edx,16 ;把 dx 移到高 16
    or edx, eax ;把积的低 16 位组合到 edx ，为 32 位的积
    add edx,0x100000 ; Ox88 子功能只会返回 lMB 以上的内存
    ;故实际内存大小要加上 lMB

 .mem_get_ok :
    mov [total_mem_bytes], edx

    jmp $

;将内存换为 byte单位后存入total_mem_bytes处

error_hlt:
  loadermsg db '2 loader in real'

  SELECTOR_CODE equ (0x0001 << 3)+TI_GDT+RPL0;相当与(CODE_DESC - GDT_BASE)/8 + TI_GDT + RPL0
  SELECTOR_DATA equ (0x0002 << 3)+TI_GDT + RPL0;同上
  SELECTOR_VIDEO equ (0x0003 << 3)+TI_GDT+RPL0;同上
  ;__________________________
  ;INT 0x10 功能号：0x13 功能描述：打印字符串
  ;__________________________
  ;输入：
  ;AH子功能号=13H
  ;BH= 页码
  ;BL = 属性（若AL=00H 或 01H）
  ;CX=字符串长度
  ;(DH,DL)=坐标（行，列）
  ;ES:BP=字符串地址
  ;AL=显示输出方式
  ;0——字符串中只含显示字符，其显示属性在BL中
  ;         显示后，光标位置不变
  ;1——字符串中只含显示字符，其显示属性在BL中
  ;         显示后，光标位置改变
  ;2——字符串中含有显示字符和显示属性。显示后，光标位置不变
  ;3——字符串中含有显示字符和显示属性。显示后，光标位置改变
  ;无返回值

  mov sp,LOADER_BASE_ADDR
  mov bp,loadermsg
  mov cx,17
  mov ax,0x1301
  mov bx,0x001f
  mov dx,0x1800
  int 0x10

  ;—-----------------------准备进入保护模式
  ;1打开A20
  ;2加载gdt
  ;3将cr0的pe位置1

  ;-----------------打开A20---------------
  in al,0x92
  or al,00000010b
  out 0x92,al

  ;-----------------加载GDT---------
  lgdt [gdt_ptr]

  ;---------------cr0第0位置1-------
  mov eax,cr0
  or eax,0x00000001
  mov cr0,eax

  jmp dword SELECTOR_CODE:p_mode_start ;刷新流水线

  [bits 32]
p_mode_start:
    mov ax,SELECTOR_DATA
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov esp,LOADER_STACK_TOP
    mov ax,SELECTOR_VIDEO
    mov gs,ax

    mov byte [gs:160],'p'

    jmp $

