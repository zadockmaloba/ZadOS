const arch = @import("arch.zig");
const uart = @import("uart.zig");

/// The multiboot header
const MultiBoot = packed struct {
    magic: i32,
    flags: i32,
    checksum: i32,
};

const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const MAGIC = 0x1BADB002;
const FLAGS = ALIGN | MEMINFO;

const KERNEL_PAGE_NUMBER = 0xC0000000 >> 22;
// The number of pages occupied by the kernel, will need to be increased as we add a heap etc.
const KERNEL_NUM_PAGES = 1;

export var multiboot align(4) linksection(".rodata.boot") = MultiBoot{
    .magic = MAGIC,
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

// The initial page directory used for booting into the higher half. Should be overwritten later
export var boot_page_directory: [1024]u32 align(4096) linksection(".rodata.boot") = init: {
    // Increase max number of branches done by comptime evaluator
    @setEvalBranchQuota(1024);
    // Temp value
    var dir: [1024]u32 = undefined;

    // Page for 0 -> 4 MiB. Gets unmapped later
    dir[0] = 0x00000083;

    var i = 0;
    var idx = 1;

    // Fill preceding pages with zeroes. May be unnecessary but incurs no runtime cost
    while (i < KERNEL_PAGE_NUMBER - 1) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0;
    }

    // Map the kernel's higher half pages increasing by 4 MiB every time
    i = 0;
    while (i < KERNEL_NUM_PAGES) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0x00000083 | (i << 22);
    }
    // Fill succeeding pages with zeroes. May be unnecessary but incurs no runtime cost
    i = 0;
    while (i < 1024 - KERNEL_PAGE_NUMBER - KERNEL_NUM_PAGES) : ({
        i += 1;
        idx += 1;
    }) {
        dir[idx] = 0;
    }
    break :init dir;
};

export var kernel_stack: [16 * 1024]u8 align(16) linksection(".bss.stack") = undefined;

const PAGE_SIZE = 4096;
const PAGE_SHIFT = 12;
const PAGE_MASK = PAGE_SIZE - 1;

/// Translation table entry flags
const TTEntry = packed struct {
    valid: bool, // Bit 0: Entry is valid
    table: bool, // Bit 1: Entry is a table descriptor
    attrs: u10, // Bits 2-11: Attributes
    address: u36, // Bits 12-47: Output address
    reserved: u4, // Bits 48-51: Reserved
    ignored: u7, // Bits 52-58: Software use
    pxn: bool, // Bit 59: Privileged Execute Never
    uxn: bool, // Bit 60: Unprivileged Execute Never
    ap: u2, // Bits 61-62: Access Permissions
    ns: bool, // Bit 63: Non-secure bit
};

// Constants from linker script
extern const KERNEL_ADDR_OFFSET: u64;
extern const KERNEL_VIRT_BASE: u64;
extern const KERNEL_PHYSADDR_START: u64;

// Stack for the boot CPU (defined in start.S)
extern const stack_top: u64;
