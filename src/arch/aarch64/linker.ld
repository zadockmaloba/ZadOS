ENTRY(_start)

/*SECTIONS_TMP {*/
/*    . = 0x40100000;*/ /* RAM starts at 0x40000000 but if we ask to load the kernel there, QEMU will not load a DTB */
 /*   .startup . : { boot.o(.text) }*/
/*    .text : { *(.text) }*/
/*    .data : { *(.data) }*/
/*    .bss : { *(.bss COMMON) }*/
/*    . = ALIGN(8);*/
/*    . += 0x1000;*/ /* 4kB of stack memory */
/*    stack_top = .;*/
/*}*/

/* ARM64 memory layout for QEMU virt machine
 * Physical memory:
 * - RAM starts at 0x40000000
 * - We load at 0x40080000 to leave room for DTB
 * Virtual memory (when MMU is enabled):
 * - Kernel space starts at 0xFFFF000000000000
 */
KERNEL_ADDR_OFFSET = 0; /*0xFFFF000000000000;*/
KERNEL_VIRT_BASE = KERNEL_ADDR_OFFSET + 0x80000;

SECTIONS
{
    /* Load kernel at 0x40080000 physical address */
    . = 0x40080000;
    KERNEL_PHYSADDR_START = .;

    .text.boot : {
        *(.text.boot)
    }

    . += KERNEL_ADDR_OFFSET;

    .text ALIGN(4K) : AT (ADDR(.text) - KERNEL_ADDR_OFFSET) {
        *(.text .text.*)
    }

    .rodata ALIGN(4K) : AT (ADDR(.rodata) - KERNEL_ADDR_OFFSET) {
        *(.rodata .rodata.*)
    }

    .data ALIGN(4K) : AT (ADDR(.data) - KERNEL_ADDR_OFFSET) {
        *(.data .data.*)
    }

    __bss_start = .;
    .bss ALIGN(4K) : AT (ADDR(.bss) - KERNEL_ADDR_OFFSET) {
        *(COMMON)
        *(.bss)
    }
    __bss_end = .;

    .bss.stack ALIGN(4K) : AT (ADDR(.bss.stack) - KERNEL_ADDR_OFFSET) {
		    KERNEL_STACK_START = .;
		    KEEP(*(.bss.stack))
		    KERNEL_STACK_END = .;
        stack_top = .;
    }

    KERNEL_VADDR_END = .;
    KERNEL_PHYSADDR_END = . - KERNEL_ADDR_OFFSET;
    __STACKSIZE = KERNEL_STACK_END - KERNEL_STACK_START;
}
