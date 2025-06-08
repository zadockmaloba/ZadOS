ENTRY(_start)

SECTIONS
{
    /* Kernel starts at 0x80000 for Raspberry Pi 3 */
    . = 0x80000;

    .text.boot : {
        *(.text.boot)
    }

    .text : {
        *(.text)
    }

    .rodata : {
        *(.rodata)
    }

    .data : {
        *(.data)
    }

    . = ALIGN(8);
    __bss_start = .;
    .bss : {
        *(.bss)
    }
    __bss_end = .;

    /* Add a stack section */
    . = ALIGN(16);
    . = . + 0x4000; /* 16KB stack */
    stack_top = .;
}
