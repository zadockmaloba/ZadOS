/* ARM64 Kernel Linker Script - Cortex-A72/QEMU virt style
 * Inspired by SEGGER .icf layout
 */

ENTRY(_start)

/* ---- Memory Layout Constants ---- */
KERNEL_ADDR_OFFSET = 0x00;
KERNEL_BASE      = 0x40080000;           /* Physical load address */
KERNEL_VIRT      = 0xFFFF000040080000;   /* Virtual address when MMU enabled */
PAGE_SIZE        = 0x1000;               /* 4KB pages */
HEAP_SIZE        = 0x100000;             /* 1MB heap */
STACK_SIZE       = 0x8000;               /* 32KB stack */
STACK_SIZE_ABT   = 0x1000;
STACK_SIZE_FIQ   = 0x1000;
STACK_SIZE_UND   = 0x1000;
STACK_SIZE_IRQ   = 0x1000;
STACK_SIZE_SVC   = 0x1000;

SECTIONS
{
    . = KERNEL_BASE;

    /* ---- Exception Vector Table ---- */
    .vectors ALIGN(PAGE_SIZE) : {
        KEEP(*(.vectors))
    }

    /* ---- Boot Code ---- */
    .text.boot ALIGN(PAGE_SIZE) : {
        *(.text.boot)
    }

    /* ---- Main Executable Code ---- */
    .text ALIGN(PAGE_SIZE) : {
        *(.text .text.*)
    }

    /* ---- Read-Only Data ---- */
    .rodata ALIGN(PAGE_SIZE) : {
        *(.rodata .rodata.*)
    }

    /* ---- ARM Exception Unwind ---- */
    .ARM.exidx ALIGN(8) : {
        *(.ARM.exidx*)
    }

    /* ---- Constructors/Destructors ---- */
    .ctors ALIGN(8) : {
        KEEP(*(.ctors*))
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
    }
    .dtors ALIGN(8) : {
        KEEP(*(.dtors*))
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array))
    }

    /* ---- Thread-Local Storage ---- */
    .tdata ALIGN(8) : {
        *(.tdata .tdata.*)
    }
    .tbss ALIGN(8) : {
        *(.tbss .tbss.*)
    }

    /* ---- Initialized Data ---- */
    .data ALIGN(PAGE_SIZE) : {
        __data_start = .;
        *(.data .data.*)
        __data_end = .;
    }

    /* ---- Uninitialized Data ---- */
    .bss ALIGN(PAGE_SIZE) (NOLOAD) : {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    }

    /* ---- Heap ---- */
    .heap ALIGN(8) (NOLOAD) : {
        __heap_start = .;
        . += HEAP_SIZE;
        __heap_end = .;
    }

    /* ---- Mode-specific Stacks ---- */
    .stack_abt ALIGN(8) (NOLOAD) : {
        __stack_abt_start = .;
        . += STACK_SIZE_ABT;
        __stack_abt_end = .;
    }
    .stack_fiq ALIGN(8) (NOLOAD) : {
        __stack_fiq_start = .;
        . += STACK_SIZE_FIQ;
        __stack_fiq_end = .;
    }
    .stack_und ALIGN(8) (NOLOAD) : {
        __stack_und_start = .;
        . += STACK_SIZE_UND;
        __stack_und_end = .;
    }
    .stack_irq ALIGN(8) (NOLOAD) : {
        __stack_irq_start = .;
        . += STACK_SIZE_IRQ;
        __stack_irq_end = .;
    }
    .stack_svc ALIGN(8) (NOLOAD) : {
        __stack_svc_start = .;
        . += STACK_SIZE_SVC;
        __stack_svc_end = .;
    }

    /* ---- Main Stack (at end of RAM region) ---- */
    .stack ALIGN(16) (NOLOAD) : {
        __stack_start = .;
        . += STACK_SIZE;
        __stack_end = .;
        stack_top = .;
    }

    /* ---- Exported Symbols ---- */
    KERNEL_STACK_START = __stack_start;
    KERNEL_STACK_END   = __stack_end;
    KERNEL_HEAP_START  = __heap_start;
    KERNEL_HEAP_END    = __heap_end;
    KERNEL_VADDR_START = KERNEL_VIRT;
    KERNEL_VADDR_END   = KERNEL_VIRT + (. - KERNEL_BASE);
    KERNEL_PHYSADDR_START = KERNEL_BASE;
    KERNEL_PHYSADDR_END   = .;

    /* ---- Discard Unused Sections ---- */
    /DISCARD/ : {
        *(.comment)
        *(.gnu*)
        *(.note*)
        *(.eh_frame*)
        *(.debug*)
    }
}