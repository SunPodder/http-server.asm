ASM=nasm
LD=ld
ASMFLAGS=-f elf64 -g

all: main

main: main.o
	@$(LD) -o $@ $^

main.o: main.asm
	@$(ASM) $(ASMFLAGS) $<

run: main
	@./main

clean:
	rm -f main.o main

