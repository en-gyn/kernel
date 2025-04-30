

%include "boot.inc"

SECTION LOADER vstart=LOADER_BASE_ADDR

LOADER_STACK_TOP equ LOADER_BASE_ADDR

jmp loader_start

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

 ;以下是gdt指针，前两字节是gdt界限，后4字节是gdt起始地址
    gdt_ptr dw GDT_LIMIT
            dd GDT_BASE
    loadermsg db '2 loader in real'

    SELECTOR_CODE equ (0x0001 << 3)+TI_GDT+RPL0;相当与(CODE_DESC - GDT_BASE)/8 + TI_GDT + RPL0
    SELECTOR_DATA equ (0x0002 << 3)+TI_GDT + RPL0;同上
    SELECTOR_VIDEO equ (0x0003 << 3)+TI_GDT+RPL0;同上

loader_start:

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
  mov dx,0x200
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

    mov byte [gs:0x14],'p'

;创建 目录及页表并初始化页内存位图
    jmp setup_page

;要将描述符表地址及偏移量写入内存 gdt_ptr ，一会儿用新地址重新加载
next:
    sgdt [gdt_ptr] ;存储到原来 gdt 所有的位置

;gdt 描述符中视频段描述符中的段基址＋OxcOOOOOOO
    mov ebx, [gdt_ptr + 2]
    or dword [ebx + 0x18 + 4], 0xc0000000
;视频段是第 个段描述符，每个描述符是 字节，故 Ox18
;段描述符的高 字节的最高位是段基扯的第 31 24

;将 gdt 的基址加上 OxcOOOOOOO 使其成为内核所在的高地址
    add dword [gdt_ptr + 2], 0xc0000000

    add esp, 0xc0000000

;把页目录地址赋给 cr3
;将校指针同样映射到内核地址
    mov eax, PAGE_DIR_TABLE_POS
    mov cr3, eax

;打开 crO pg 位（第 31 位）
    mov eax, cr0
    or eax, 0x80000000
    mov cr0 , eax

;在开启分页后，用 gdt 新的地址重新加载
    lgdt [gdt_ptr] ;重新加载

    mov byte [gs:0x00], 'V'
    mov byte [gs:0x01],0xA4
;见频段段基址已经被更新，用字符 表示 virtual addr

    jmp $




 ;-------------创建页目录及页表-------------
setup_page:
    ;先把页目录占用的空间逐字节清 0
    mov ecx, 4096
    mov esi,0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi],0
    inc esi
    loop .clear_page_dir

;开始创建页目录项（ PDE)
.create_pde :  ;创建 Page Directory Entry
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x1000  ;此时 eax 为第一个页表的位置及属性
    mov ebx, eax  ;此处为 ebx 赋值，是为 .create_pte 做准备， ebx 为基址

 ; 下面将页目录项 OxcOO 都存为第一个页表的地址，每个页表表示 4MB 内存
; 这样 Oxc03f ff ff 以下的地址和 Ox003fffff 以下的地址都指向相同的页表
; 这是为将地址映射为内核地址做准备
    or eax, PG_US_U | PG_RW_W | PG_P
    ;页目录项的属性 RW 位为 1, us ，表示用户属性，所有特权级别都可以访问
    mov [PAGE_DIR_TABLE_POS + 0x0], eax  ;第1个目录项
    ;在页目录表中的第 目录项写入第一个页表的位量（ 0x101000 ）及属性（ 7)
    mov [PAGE_DIR_TABLE_POS + 0xc00], eax
;一个页表项占用4字节
; OxcOO 表示第 768 个页表占用的目录项， OxcOO 以上的目录项用于内核空间
;也就是页表的 Ox cOOOOOOO Oxf fff f ff 共计 lG 属于内核
    ;OxO - Oxbfffffff 共计 3G 属于用户进程
    sub eax, 0x1000
    mov [PAGE_DIR_TABLE_POS + 4092], eax
;使最后一个目录项指向页目录表自己的地址

;下面创建页表项（ PTE)
    mov ecx, 256 ; lM 低端内存／每页大小 4k = 256
    mov esi,0
    mov edx, PG_US_U | PG_RW_W | PG_P  ;属性为 7, OS=l, RW=l, P=l
.create_pte :  ;创建 Page Table Entry
    mov [ebx+esi*4],edx
;此时的 ebx 已经在上茵通过 eax 赋值为 Ox 101000 也就是第一个页袤的地址
    add edx,4096
    inc esi
    loop .create_pte

;创建内核其他页表的 PDE
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x2000  ;此时 eax 为第二个页表的位置
    or eax, PG_US_U | PG_RW_W | PG_P  ;页目录项的属性 us RW 位都为
    mov ebx, PAGE_DIR_TABLE_POS
    mov ecx, 254  ;范围为第 769-1022 的所有目录项数
    mov esi, 769
.create_kernel_pde:
    mov [ebx+esi*4],eax
    inc esi
    add eax,0x1000
    loop .create_kernel_pde
    jmp next


