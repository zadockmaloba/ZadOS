ENTRY(_start)

/* Memory layout constants */
KERNEL_BASE = 0x40080000;           /* Physical load address */
KERNEL_VIRT = 0xFFFF000040080000;   /* Virtual address when MMU enabled */
PAGE_SIZE = 0x1000;                 /* 4KB pages */
STACK_SIZE = 0x20000;               /* 128KB stack */
HEAP_SIZE = 0x100000;               /* 1MB heap */
KERNEL_ADDR_OFFSET = 0x00;

SECTIONS {
    . = KERNEL_BASE;

    /* Boot code must be first and at physical address */
    .text.boot ALIGN(PAGE_SIZE) : {
        *(.text.boot)
    }

    /* Code sections */
    .text ALIGN(PAGE_SIZE) : {
        *(.text .text.*);
    }

    /* Read-only data */
    .rodata ALIGN(PAGE_SIZE) : {
        *(.rodata .rodata.*);
    }

    /* Global offset table */
    .got ALIGN(16) : {
        *(.got);
        *(.got.plt);
    }

    /* Initialized data */
    .data ALIGN(PAGE_SIZE) : {
        __data_start = .;
        *(.data .data.*);
        __data_end = .;
    }

    /* Zero-initialized data */
    .bss ALIGN(PAGE_SIZE) (NOLOAD) : {
        __bss_start = .;
        *(.bss .bss.*);
        *(.lbss);
        *(.lbss.*);
        *(COMMON)
        . = ALIGN(PAGE_SIZE);
        __bss_end = .;
    }

    /* Heap section */
    /*.heap ALIGN(PAGE_SIZE) (NOLOAD) : {
        __heap_start = .;
        *(.heap .heap.*);
        . += HEAP_SIZE;
        . = ALIGN(PAGE_SIZE);
        __heap_end = .;
    }*/

    .kernel_heap ALIGN(PAGE_SIZE) (NOLOAD) : {
      __kernel_heap_start = .;
      *(.kernel_heap .kernel_heap.*);
      . += HEAP_SIZE;
      . = ALIGN(PAGE_SIZE);
      __kernel_heap_end = .;
    }

    .kernel_stack ALIGN(PAGE_SIZE) (NOLOAD) : {
      __kernel_stack_start = .;
      /**(.kernel_stack .kernel_stack.*)*/
      . += STACK_SIZE;
      . = ALIGN(PAGE_SIZE);
      __kernel_stack_end = .;
    }

    /* Stack must be properly aligned for ARM64 */
    .stack ALIGN(PAGE_SIZE) (NOLOAD) : {
        . = ALIGN(PAGE_SIZE);
        __stack_start = .;
        /**(.stack .stack.*)*/
        . = . + STACK_SIZE;
        . = ALIGN(PAGE_SIZE);
        __stack_end = .;
        stack_top = .;
    }

    /* Provide symbols needed by kernel */
    /*KERNEL_HEAP_START = __heap_start;
    KERNEL_HEAP_END = __heap_end;*/
    KERNEL_TMP_STACK_START = __kernel_stack_start;
    KERNEL_TMP_STACK_END = __kernel_stack_end;
    KERNEL_STACK_START = __stack_start;
    KERNEL_STACK_END = __stack_end;
    KERNEL_VADDR_START = KERNEL_VIRT;
    KERNEL_VADDR_END = KERNEL_VIRT + (. - KERNEL_BASE);
    KERNEL_PHYSADDR_START = KERNEL_BASE;
    KERNEL_PHYSADDR_END = .;

    /* Discard unnecessary sections */
    /DISCARD/ : {
        *(*.eh_frame);
        *(*.eh_frame_hdr);
        /**(.eh_frame*)
        *(.comment)
        *(.gnu*)
        *(.note*)
        *(.interp)
        *(.dynsym)
        *(.dynstr)
        *(.hash)*/
    }
}