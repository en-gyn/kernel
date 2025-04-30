

bochs:
	bochs -q -f bochsrc.disk

.PHONY:NASM

NASM:
	nasm boot.asm -o boot.bin -I ./include/
clean:
