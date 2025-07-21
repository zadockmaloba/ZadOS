const std = @import("std");
const testing = std.testing;
const expectEqual = testing.expectEqual;
const expect = testing.expect;
const log = std.log.scoped(.arm64_paging);
const builtin = @import("builtin");
const is_test = builtin.is_test;
const panic = @import("../../kernel/panic.zig").panic;
const build_options = @import("build_options");
const arch = if (builtin.is_test) @import("../../../../test/mock/kernel/arch_mock.zig") else @import("arch.zig");
const isr = @import("isr.zig");
const MemProfile = @import("../../kernel/mem.zig").MemProfile;
const tty = @import("../../kernel/tty.zig");
const mem = @import("../../kernel/mem.zig");
const vmm = @import("../../kernel/vmm.zig");
const pmm = @import("../../kernel/pmm.zig");
const multiboot = @import("multiboot.zig");
const Allocator = std.mem.Allocator;

const faulted = true;
const use_callback2 = true;
const rt_fault_callback2 = true;
const rt_fault_callback = true;

/// ARM64 translation levels
const LEVEL_0: u3 = 0;
const LEVEL_1: u3 = 1;
const LEVEL_2: u3 = 2;
const LEVEL_3: u3 = 3;

/// ARM64 page sizes
pub const PAGE_SIZE_4KB: usize = 0x1000;
pub const PAGE_SIZE_2MB: usize = 0x200000;
pub const PAGE_SIZE_1GB: usize = 0x40000000;

/// Number of entries per table at each level
const ENTRIES_PER_TABLE: u32 = 512;
const ENTRIES_PER_DIRECTORY: u32 = ENTRIES_PER_TABLE;

/// Page table entry bit masks
const PTE_VALID: u64 = 1 << 0; // Entry is valid
const PTE_TABLE: u64 = 1 << 1; // Entry points to next level table
const PTE_AF: u64 = 1 << 10; // Access flag
const PTE_SHAREABLE: u64 = 3 << 8; // Inner shareable
const PTE_RO: u64 = 1 << 7; // Read-only
const PTE_USER: u64 = 1 << 6; // Unprivileged access allowed
const PTE_NG: u64 = 1 << 11; // Not global
const PTE_ATTR_IDX: u64 = 3 << 2; // Memory attributes index
const PTE_ADDR_MASK: u64 = 0x0000_FFFF_FFFF_F000; // Physical address mask

/// A page table entry for ARM64
const PageTableEntry = u64;
const TableEntry = PageTableEntry;

/// A page table containing 512 entries
pub const PageTable = struct {
    entries: [ENTRIES_PER_TABLE]PageTableEntry align(PAGE_SIZE_4KB),

    const Self = @This();

    pub fn init() Self {
        return Self{
            .entries = [_]PageTableEntry{0} ** ENTRIES_PER_TABLE,
        };
    }
};

pub const Table = PageTable;
pub const Directory = PageTable;
pub const DirectoryEntry = PageTableEntry;

/// The top-level translation table (equivalent to PGD in x86)
pub var kernel_page_table: PageTable align(PAGE_SIZE_4KB) = PageTable.init();

///
/// Convert a virtual address to an index within an array of table entries.
///
/// Arguments:
///     IN virt: usize - The virtual address to convert.
///
/// Return: usize
///     The index into an array of table entries.
///
inline fn virtToTableEntryIdx(virt: usize) usize {
    return virt / PAGE_SIZE_4KB;
}

///
/// Set the bit(s) associated with an attribute of a table or directory entry.
///
/// Arguments:
///     val: *align(1) u32 - The entry to modify
///     attr: u32 - The bits corresponding to the attribute to set
///
inline fn setAttribute(val: *align(1) u32, attr: u32) void {
    val.* |= attr;
}

///
/// Clear the bit(s) associated with an attribute of a table or directory entry.
///
/// Arguments:
///     val: *align(1) u32 - The entry to modify
///     attr: u32 - The bits corresponding to the attribute to clear
///
inline fn clearAttribute(val: *align(1) u32, attr: u32) void {
    val.* &= ~attr;
}

///
/// Map a page table entry, setting the present, writable, user, access flag, shareable, and physical address bits.
/// Clears the read-only bit. Entry should be zeroed.
///
/// Arguments:
///     IN virt_addr: usize - The start of the virtual space to map
///     IN virt_end: usize - The end of the virtual space to map
///     IN phys_addr: usize - The start of the physical space to map
///     IN phys_end: usize - The end of the physical space to map
///     IN attrs: vmm.Attributes - The attributes to apply to this mapping
///     IN allocator: Allocator - The allocator to use to map any tables needed
///     OUT dir: *Directory - The directory that this entry is in
///
/// Error: vmm.MapperError || Allocator.Error
///     vmm.MapperError.InvalidPhysicalAddress - The physical start address is greater than the end
///     vmm.MapperError.InvalidVirtualAddress - The virtual start address is greater than the end or is larger than 4GB
///     vmm.MapperError.AddressMismatch - The differences between the virtual addresses and the physical addresses aren't the same
///     vmm.MapperError.MisalignedPhysicalAddress - One or both of the physical addresses aren't page size aligned
///     vmm.MapperError.MisalignedVirtualAddress - One or both of the virtual addresses aren't page size aligned
///     Allocator.Error.* - See Allocator.alignedAlloc
///
fn mapTableEntry(dir: *Directory, virt_start: usize, virt_end: usize, phys_start: usize, phys_end: usize, attrs: vmm.Attributes, allocator: Allocator) (vmm.MapperError || Allocator.Error)!void {
    _ = allocator; // Suppress unused var warning
    if (phys_start > phys_end) {
        return vmm.MapperError.InvalidPhysicalAddress;
    }
    if (virt_start > virt_end) {
        return vmm.MapperError.InvalidVirtualAddress;
    }
    if (phys_end - phys_start != virt_end - virt_start) {
        return vmm.MapperError.AddressMismatch;
    }
    if (!std.mem.isAligned(phys_start, PAGE_SIZE_4KB) or !std.mem.isAligned(phys_end, PAGE_SIZE_4KB)) {
        return vmm.MapperError.MisalignedPhysicalAddress;
    }
    if (!std.mem.isAligned(virt_start, PAGE_SIZE_4KB) or !std.mem.isAligned(virt_end, PAGE_SIZE_4KB)) {
        return vmm.MapperError.MisalignedVirtualAddress;
    }

    const entry = virtToTableEntryIdx(virt_start);
    const table_entry = &dir.entries[entry];

    setAttribute(table_entry, PTE_VALID);
    setAttribute(table_entry, PTE_TABLE);
    clearAttribute(table_entry, PTE_RO);

    if (attrs.writable) {
        setAttribute(table_entry, PTE_RO);
    } else {
        clearAttribute(table_entry, PTE_RO);
    }

    if (attrs.kernel) {
        clearAttribute(table_entry, PTE_USER);
    } else {
        setAttribute(table_entry, PTE_USER);
    }

    if (attrs.shareable) {
        setAttribute(table_entry, PTE_SHAREABLE);
    } else {
        clearAttribute(table_entry, PTE_SHAREABLE);
    }

    const table_phys_addr = if (builtin.is_test) @intFromPtr(table_entry) else vmm.kernel_vmm.virtToPhys(@intFromPtr(table_entry)) catch |e| {
        panic(@errorReturnTrace(), "Failed getting the physical address for a page table: {}\n", .{e});
    };
    setAttribute(table_entry, PTE_ADDR_MASK & @as(u32, @intCast(table_phys_addr)));
    if (dir == &kernel_page_table) {
        asm volatile ("invlpg (%[addr])"
            :
            : [addr] "r" (virt_start),
            : "memory"
        );
    }
}

///
/// Unmap a page table entry, clearing the present bits.
///
/// Arguments:
///     IN virt_addr: usize - The start of the virtual space to map
///     IN virt_end: usize - The end of the virtual space to map
///     OUT dir: *Directory - The directory that this entry is in
///     IN allocator: Allocator - The allocator used to map the region to be freed.
///
/// Error: vmm.MapperError
///     vmm.MapperError.NotMapped - If the region being unmapped wasn't mapped in the first place
///
fn unmapTableEntry(dir: *Directory, virt_start: usize, virt_end: usize, allocator: Allocator) vmm.MapperError!void {
    // Suppress unused var warning
    _ = allocator;
    _ = virt_end;
    const entry = virtToTableEntryIdx(virt_start);
    const table_entry = &dir.entries[entry] orelse return vmm.MapperError.NotMapped;
    if (table_entry.* & PTE_VALID != 0) {
        clearAttribute(table_entry, PTE_VALID);
        if (dir == &kernel_page_table) {
            asm volatile ("invlpg (%[addr])"
                :
                : [addr] "r" (virt_start),
                : "memory"
            );
        }
    } else {
        return vmm.MapperError.NotMapped;
    }
}

///
/// Map a virtual region of memory to a physical region with a set of attributes within a directory.
/// If this call is made to a directory that has been loaded by the CPU, the virtual memory will immediately be accessible (given the proper attributes)
/// and will be mirrored to the physical region given. Otherwise it will be accessible once the given directory is loaded by the CPU.
///
/// This call will panic if mapDir returns an error when called with any of the arguments given.
///
/// Arguments:
///     IN virtual_start: usize - The start of the virtual region to map
///     IN virtual_end: usize - The end (exclusive) of the virtual region to map
///     IN physical_start: usize - The start of the physical region to map to
///     IN physical_end: usize - The end (exclusive) of the physical region to map to
///     IN attrs: vmm.Attributes - The attributes to apply to this mapping
///     IN/OUT allocator: Allocator - The allocator to use to allocate any intermediate data structures required to map this region
///     IN/OUT dir: *Directory - The page directory to map within
///
/// Error: vmm.MapperError || Allocator.Error
///     * - See mapDirEntry
///
pub fn map(virtual_start: usize, virtual_end: usize, phys_start: usize, phys_end: usize, attrs: vmm.Attributes, allocator: Allocator, dir: *PageTable) (Allocator.Error || vmm.MapperError)!void {
    if (phys_start > phys_end) {
        return vmm.MapperError.InvalidPhysicalAddress;
    }
    if (virtual_start > virtual_end) {
        return vmm.MapperError.InvalidVirtualAddress;
    }
    if (phys_end - phys_start != virtual_end - virtual_start) {
        return vmm.MapperError.AddressMismatch;
    }
    if (!std.mem.isAligned(phys_start, PAGE_SIZE_4KB) or !std.mem.isAligned(phys_end, PAGE_SIZE_4KB)) {
        return vmm.MapperError.MisalignedPhysicalAddress;
    }
    if (!std.mem.isAligned(virtual_start, PAGE_SIZE_4KB) or !std.mem.isAligned(virtual_end, PAGE_SIZE_4KB)) {
        return vmm.MapperError.MisalignedVirtualAddress;
    }

    var virt = @as(u64, virtual_start);
    var phys = @as(u64, phys_start);

    while (virt < virtual_end) : ({
        virt += PAGE_SIZE_4KB;
        phys += PAGE_SIZE_4KB;
    }) {
        // Get the indices for each level
        const l0_idx = virtToL0Index(virt);
        const l1_idx = virtToL1Index(virt);
        const l2_idx = virtToL2Index(virt);
        const l3_idx = virtToL3Index(virt);

        // Walk/create the page tables
        var l1: *PageTable = undefined;
        if ((dir.entries[l0_idx] & PTE_VALID) == 0) {
            // Allocate new L1 table
            l1 = &(try allocator.alignedAlloc(PageTable, PAGE_SIZE_4KB, 1))[0];
            l1.entries = [_]PageTableEntry{0} ** ENTRIES_PER_TABLE;
            setTableEntry(&dir.entries[l0_idx], @intFromPtr(l1), true);
        } else {
            l1 = @ptrFromInt(dir.entries[l0_idx] & PTE_ADDR_MASK);
        }

        var l2: *PageTable = undefined;
        if ((l1.entries[l1_idx] & PTE_VALID) == 0) {
            // Allocate new L2 table
            l2 = &(try allocator.alignedAlloc(PageTable, PAGE_SIZE_4KB, 1))[0];
            l2.entries = [_]PageTableEntry{0} ** ENTRIES_PER_TABLE;
            setTableEntry(&l1.entries[l1_idx], @intFromPtr(l2), true);
        } else {
            l2 = @ptrFromInt(l1.entries[l1_idx] & PTE_ADDR_MASK);
        }

        var l3: *PageTable = undefined;
        if ((l2.entries[l2_idx] & PTE_VALID) == 0) {
            // Allocate new L3 table
            l3 = &(try allocator.alignedAlloc(PageTable, PAGE_SIZE_4KB, 1))[0];
            l3.entries = [_]PageTableEntry{0} ** ENTRIES_PER_TABLE;
            setTableEntry(&l2.entries[l2_idx], @intFromPtr(l3), true);
        } else {
            l3 = @ptrFromInt(l2.entries[l2_idx] & PTE_ADDR_MASK);
        }

        // Map the actual page
        l3.entries[l3_idx] = makePageTableEntry(phys, attrs);

        // Invalidate TLB entry
        if (dir == &kernel_page_table) {
            invalidateTLBEntry(virt);
        }
    }
}

pub fn unmap(virtual_start: usize, virtual_end: usize, allocator: Allocator, dir: *PageTable) vmm.MapperError!void {
    _ = allocator; // Suppress unused var warning
    var virt = @as(u64, virtual_start);

    while (virt < virtual_end) : (virt += PAGE_SIZE_4KB) {
        const l0_idx = virtToL0Index(virt);
        const l1_idx = virtToL1Index(virt);
        const l2_idx = virtToL2Index(virt);
        const l3_idx = virtToL3Index(virt);

        // Walk the page tables
        const l1 = @as(*PageTable, @ptrFromInt(dir.entries[l0_idx] & PTE_ADDR_MASK));
        const l2 = @as(*PageTable, @ptrFromInt(l1.entries[l1_idx] & PTE_ADDR_MASK));
        var l3 = @as(*PageTable, @ptrFromInt(l2.entries[l2_idx] & PTE_ADDR_MASK));

        // Clear the mapping
        if (l3.entries[l3_idx] & PTE_VALID != 0) {
            l3.entries[l3_idx] = 0;

            // Invalidate TLB entry
            if (dir == &kernel_page_table) {
                invalidateTLBEntry(virt);
            }

            // TODO: Free page tables when empty
            // This requires tracking reference counts or scanning for usage
        } else {
            return vmm.MapperError.NotMapped;
        }
    }
}
///
/// Called when a data abort or instruction abort occurs.
/// This will log the CPU state and system registers as well as human-readable information.
///
/// Arguments:
///     IN state: *arch.CpuState - The CPU's state when the abort occurred.
///
fn pageFault(state: *arch.CpuState) u32 {
    var fault_status: u64 = undefined;
    var fault_addr: u64 = undefined;

    asm volatile (
        \\ mrs %[fsr], esr_el1      // Exception Syndrome Register
        \\ mrs %[far], far_el1      // Fault Address Register
        : [fsr] "=r" (fault_status),
          [far] "=r" (fault_addr),
    );

    const ec = (fault_status >> 26) & 0x3F; // Exception class
    const fsc = fault_status & 0x3F; // Fault status code

    const is_instruction = ec == 0x20 or ec == 0x21; // Check if instruction or data abort
    const level = (fsc >> 2) & 0x3; // Translation level where fault occurred

    // Parse fault status
    const diag_present = if (fsc & 0x1 != 0) "present" else "non-present";
    const diag_rw = if (fsc & 0x2 != 0) "writing to" else "reading from";
    const diag_privilege = if (fault_status & (1 << 6) != 0) "user" else "kernel";
    const diag_fetch = if (is_instruction) "instruction" else "data";

    log.info("Page fault: {s} process {s} a {s} page during {s} access at level {d}\n", .{ diag_privilege, diag_rw, diag_present, diag_fetch, level });

    // Get relevant system registers
    var ttbr0: u64 = undefined;
    var ttbr1: u64 = undefined;
    var tcr: u64 = undefined;
    var sctlr: u64 = undefined;

    asm volatile (
        \\ mrs %[ttbr0], ttbr0_el1  // Translation Table Base Register 0
        \\ mrs %[ttbr1], ttbr1_el1  // Translation Table Base Register 1
        \\ mrs %[tcr], tcr_el1      // Translation Control Register
        \\ mrs %[sctlr], sctlr_el1  // System Control Register
        : [ttbr0] "=r" (ttbr0),
          [ttbr1] "=r" (ttbr1),
          [tcr] "=r" (tcr),
          [sctlr] "=r" (sctlr),
    );

    log.info("TTBR0: 0x{X}, TTBR1: 0x{X}, TCR: 0x{X}, SCTLR: 0x{X}\n", .{ ttbr0, ttbr1, tcr, sctlr });
    log.info("Fault address: 0x{X}, ESR: 0x{X}\n", .{ fault_addr, fault_status });
    log.info("State: {any}\n", .{state});
    @panic("Page fault");
}

///
/// Initialise ARM64 paging, overwriting any previous paging set up.
///
/// Arguments:
///     IN mem_profile: *const MemProfile - The memory profile of the system and kernel
///
pub fn init(mem_profile: *const MemProfile) void {
    log.info("Initializing AArch64 paging...\n", .{});
    defer log.info("MMU initialization complete\n", .{});

    // Register data/instruction abort handlers
    isr.registerIsr(isr.DATA_ABORT, if (build_options.test_mode == .Initialisation) rt_pageFault else pageFault) catch |e| {
        panic(@errorReturnTrace(), "Failed to register data abort handler: {}\n", .{e});
    };
    isr.registerIsr(isr.PREFETCH_ABORT, if (build_options.test_mode == .Initialisation) rt_pageFault else pageFault) catch |e| {
        panic(@errorReturnTrace(), "Failed to register instruction abort handler: {}\n", .{e});
    };

    // Get physical address of kernel page table
    const table_physaddr = @intFromPtr(mem.virtToPhys(&kernel_page_table));

    // Set up Translation Control Register (TCR_EL1)
    // - T0SZ=16 (48-bit VA space)
    // - 4KB granule
    // - Inner/Outer Write-Back Cacheable
    // - Inner/Outer Shareable
    const tcr_val: u64 = (16 << 0) | // T0SZ=16 (48-bit VA)
        (1 << 8) | // IRGN0=1 (Inner WB, WA)
        (1 << 10) | // ORGN0=1 (Outer WB, WA)
        (3 << 12) | // SH0=3 (Inner Shareable)
        (0 << 14) | // TG0=0 (4KB granule)
        (2 << 32); // IPS=2 (40-bit PA)

    // Set up Memory Attribute Indirection Register (MAIR_EL1)
    // Attr0 - Normal Memory, Write-Back
    // Attr1 - Device Memory, nGnRnE
    const mair_val: u64 = 0xFF << 0 | // Attr0 = Normal WB (Inner and Outer)
        0x00 << 8; // Attr1 = Device nGnRnE

    // Configure translation registers
    asm volatile (
        \\ msr mair_el1, %[mair]    // Set up memory attributes
        \\ msr tcr_el1, %[tcr]      // Set up translation control
        \\ msr ttbr0_el1, %[ttbr0]  // Set up translation table base
        \\ isb
        :
        : [mair] "r" (mair_val),
          [tcr] "r" (tcr_val),
          [ttbr0] "r" (table_physaddr),
    );

    // Ensure all table updates are complete
    asm volatile ("dsb sy" ::: "memory");

    // Enable MMU and caches in SCTLR_EL1
    // Set: MMU, I-cache, D-cache, SP alignment check
    // Clear: EE, E0E, WXN
    asm volatile (
        \\ mrs x0, sctlr_el1
        \\ orr x0, x0, #(1 << 0)    // MMU enable
        \\ orr x0, x0, #(1 << 2)    // D-cache enable
        \\ orr x0, x0, #(1 << 12)   // I-cache enable
        \\ orr x0, x0, #(1 << 3)    // SP alignment check
        \\ bic x0, x0, #(1 << 25)   // Clear EE (little endian)
        \\ bic x0, x0, #(1 << 24)   // Clear E0E
        \\ bic x0, x0, #(1 << 19)   // Clear WXN
        \\ msr sctlr_el1, x0
        \\ isb
    );

    const v_end = std.mem.alignForward(usize, @intFromPtr(mem_profile.vaddr_end), PAGE_SIZE_4KB);
    switch (build_options.test_mode) {
        .Initialisation => runtimeTests(v_end),
        else => {},
    }
}

fn checkTableEntry(entry: TableEntry, page_phys: usize, attrs: vmm.Attributes, present: bool) !void {
    try expectEqual(entry & PTE_VALID, if (present) PTE_VALID else 0);
    try expectEqual(entry & PTE_RO, if (attrs.writable) 0 else PTE_RO);
    try expectEqual(entry & PTE_USER, if (attrs.kernel) 0 else PTE_USER);
    try expectEqual(entry & PTE_SHAREABLE, if (attrs.shareable) PTE_SHAREABLE else 0);
    try expectEqual(entry & PTE_ADDR_MASK, page_phys);
}

test "setAttribute and clearAttribute" {
    var val: u32 = 0;
    const attrs = [_]u32{ PTE_VALID, PTE_RO, PTE_USER, PTE_SHAREABLE, PTE_AF, PTE_NG, PTE_ATTR_IDX, PTE_ADDR_MASK };

    for (attrs) |attr| {
        const old_val = val;
        setAttribute(&val, attr);
        try std.testing.expectEqual(val, old_val | attr);
    }

    for (attrs) |attr| {
        const old_val = val;
        clearAttribute(&val, attr);
        try std.testing.expectEqual(val, old_val & ~attr);
    }
}

test "virtToTableEntryIdx" {
    try expectEqual(virtToTableEntryIdx(0), 0);
    try expectEqual(virtToTableEntryIdx(123), 0);
    try expectEqual(virtToTableEntryIdx(PAGE_SIZE_4KB - 1), 0);
    try expectEqual(virtToTableEntryIdx(PAGE_SIZE_4KB), 1);
    try expectEqual(virtToTableEntryIdx(PAGE_SIZE_4KB + 1), 1);
    try expectEqual(virtToTableEntryIdx(PAGE_SIZE_4KB * 2), 2);
    try expectEqual(virtToTableEntryIdx(PAGE_SIZE_4KB * (ENTRIES_PER_TABLE - 1)), ENTRIES_PER_TABLE - 1);
    try expectEqual(virtToTableEntryIdx(PAGE_SIZE_4KB * (ENTRIES_PER_TABLE)), 0);
}

test "makePageTableEntry" {
    const attrs1 = vmm.Attributes{ .kernel = false, .writable = true, .cachable = true };
    const phys1: u64 = 0x1234000; // Must be page aligned
    const entry1 = makePageTableEntry(phys1, attrs1);

    try expectEqual(entry1 & PTE_VALID, PTE_VALID);
    try expectEqual(entry1 & PTE_RO, 0); // Writable, so no read-only
    try expectEqual(entry1 & PTE_USER, PTE_USER); // User access
    try expectEqual(entry1 & PTE_ADDR_MASK, phys1);

    const attrs2 = vmm.Attributes{ .kernel = true, .writable = false, .cachable = false };
    const phys2: u64 = 0x5678000;
    const entry2 = makePageTableEntry(phys2, attrs2);

    try expectEqual(entry2 & PTE_VALID, PTE_VALID);
    try expectEqual(entry2 & PTE_RO, PTE_RO); // Read-only
    try expectEqual(entry2 & PTE_USER, 0); // Kernel only
    try expectEqual(entry2 & PTE_ADDR_MASK, phys2);
    try expectEqual(entry2 & PTE_ATTR_IDX, PTE_ATTR_IDX); // Device memory
}

test "virtToPageTableIndex" {
    const vaddr: u64 = 0x0000_1234_5678_9000; // Example virtual address

    // Level 0 index should be bits [47:39]
    try expectEqual(virtToL0Index(vaddr), @as(u9, 0x0));

    // Level 1 index should be bits [38:30]
    try expectEqual(virtToL1Index(vaddr), @as(u9, 0x4));

    // Level 2 index should be bits [29:21]
    try expectEqual(virtToL2Index(vaddr), @as(u9, 0xD1));

    // Level 3 index should be bits [20:12]
    try expectEqual(virtToL3Index(vaddr), @as(u9, 0x167));
}

// test "mapTableEntry" {
//     var allocator = std.testing.allocator;
//     var dir: Directory = Directory{ .entries = [_]DirectoryEntry{0} ** ENTRIES_PER_DIRECTORY, .tables = [_]?*Table{null} ** ENTRIES_PER_DIRECTORY };
//     const attrs = vmm.Attributes{ .kernel = false, .writable = false, .cachable = false };
//     vmm.kernel_vmm = try vmm.VirtualMemoryManager(arch.VmmPayload).init(PAGE_SIZE_2MB, 0xFFFFFFFF, allocator, arch.VMM_MAPPER, undefined);
//     defer vmm.kernel_vmm.deinit();
//     {
//         const phys: usize = 0 * PAGE_SIZE_2MB;
//         const phys_end: usize = phys + PAGE_SIZE_2MB;
//         const virt: usize = 1 * PAGE_SIZE_2MB;
//         const virt_end: usize = virt + PAGE_SIZE_2MB;

//         try mapTableEntry(&dir, virt, virt_end, phys, phys_end, attrs, allocator);

//         const entry_idx = virtToTableEntryIdx(virt);
//         const entry = dir.entries[entry_idx];
//         try checkTableEntry(entry, phys, attrs, true);
//         const table_free = @as([*]Table, @ptrCast(table))[0..1];
//         allocator.free(table_free);
//     }
//     {
//         const phys: usize = 7 * PAGE_SIZE_2MB;
//         const phys_end: usize = phys + PAGE_SIZE_2MB;
//         const virt: usize = 8 * PAGE_SIZE_2MB;
//         const virt_end: usize = virt + PAGE_SIZE_2MB;

//         try mapTableEntry(&dir, virt, virt_end, phys, phys_end, attrs, allocator);

//         const entry_idx = virtToTableEntryIdx(virt);
//         const entry = dir.entries[entry_idx];
//         try checkTableEntry(entry, phys, attrs, true);
//         const table_free = @as([*]Table, @ptrCast(table))[0..1];
//         allocator.free(table_free);
//     }
// }

test "mapTableEntry returns errors correctly" {
    const allocator = std.testing.allocator;
    var dir = Directory{ .entries = [_]DirectoryEntry{0} ** ENTRIES_PER_DIRECTORY, .tables = undefined };
    const attrs = vmm.Attributes{ .kernel = true, .writable = true, .cachable = true };
    try testing.expectError(vmm.MapperError.MisalignedVirtualAddress, mapTableEntry(&dir, 1, PAGE_SIZE_4KB + 1, 0, PAGE_SIZE_4KB, attrs, allocator));
    try testing.expectError(vmm.MapperError.MisalignedPhysicalAddress, mapTableEntry(&dir, 0, PAGE_SIZE_4KB, 1, PAGE_SIZE_4KB + 1, attrs, allocator));
    try testing.expectError(vmm.MapperError.AddressMismatch, mapTableEntry(&dir, 0, PAGE_SIZE_4KB, 1, PAGE_SIZE_4KB, attrs, allocator));
    try testing.expectError(vmm.MapperError.InvalidVirtualAddress, mapTableEntry(&dir, 1, 0, 0, PAGE_SIZE_4KB, attrs, allocator));
    try testing.expectError(vmm.MapperError.InvalidPhysicalAddress, mapTableEntry(&dir, 0, PAGE_SIZE_4KB, 1, 0, attrs, allocator));
}

test "map and unmap" {
    const allocator = std.testing.allocator;
    var dir = Directory{ .entries = [_]DirectoryEntry{0} ** ENTRIES_PER_DIRECTORY, .tables = [_]?*Table{null} ** ENTRIES_PER_DIRECTORY };

    vmm.kernel_vmm = try vmm.VirtualMemoryManager(arch.VmmPayload).init(PAGE_SIZE_2MB, 0xFFFFFFFF, allocator, arch.VMM_MAPPER, undefined);
    defer vmm.kernel_vmm.deinit();

    const phys_start: usize = PAGE_SIZE_2MB * 2;
    const virt_start: usize = PAGE_SIZE_2MB * 4;
    const phys_end: usize = PAGE_SIZE_2MB * 4;
    const virt_end: usize = PAGE_SIZE_2MB * 6;
    const attrs = vmm.Attributes{ .kernel = true, .writable = true, .cachable = true };
    try map(virt_start, virt_end, phys_start, phys_end, attrs, allocator, &dir);

    var virt = virt_start;
    var phys = phys_start;
    while (virt < virt_end) : ({
        virt += PAGE_SIZE_2MB;
        phys += PAGE_SIZE_2MB;
    }) {
        const entry_idx = virtToTableEntryIdx(virt);
        const entry = dir.entries[entry_idx];
        try checkTableEntry(entry, phys, attrs, true);
    }

    try unmap(virt_start, virt_end, allocator, &dir);
    virt = virt_start;
    phys = phys_start;
    while (virt < virt_end) : ({
        virt += PAGE_SIZE_2MB;
        phys += PAGE_SIZE_2MB;
    }) {
        const entry_idx = virtToTableEntryIdx(virt);
        const entry = dir.entries[entry_idx];
        try checkTableEntry(entry, phys, attrs, false);
    }
}

test "copy" {
    // Create a dummy page dir
    var dir: Directory = Directory{ .entries = [_]DirectoryEntry{0} ** ENTRIES_PER_DIRECTORY, .tables = [_]?*Table{null} ** ENTRIES_PER_DIRECTORY };
    dir.entries[0] = 123;
    dir.entries[56] = 794;
    var table0 = Table{ .entries = [_]TableEntry{654} ** ENTRIES_PER_TABLE };
    var table56 = Table{ .entries = [_]TableEntry{987} ** ENTRIES_PER_TABLE };
    dir.tables[0] = &table0;
    dir.tables[56] = &table56;
    var dir2 = dir.copy();
    const dir_slice = @as([*]const u8, @ptrCast(&dir))[0..@sizeOf(Directory)];
    const dir2_slice = @as([*]const u8, @ptrCast(&dir2))[0..@sizeOf(Directory)];
    try testing.expectEqualSlices(u8, dir_slice, dir2_slice);

    // Changes to one should not affect the other
    dir2.tables[1] = &table0;
    dir.tables[0] = &table56;
    try expect(!std.mem.eql(u8, dir_slice, dir2_slice));
}

//
// ARM64 page table helper functions
//

fn makePageTableEntry(phys_addr: u64, attrs: vmm.Attributes) PageTableEntry {
    var entry: PageTableEntry = PTE_VALID;
    entry |= PTE_AF; // Set access flag - ARM64 faults if this isn't set
    entry |= PTE_SHAREABLE;

    if (!attrs.writable) {
        entry |= PTE_RO;
    }

    if (!attrs.kernel) {
        entry |= PTE_USER;
    }

    if (!attrs.cachable) {
        entry |= PTE_ATTR_IDX; // Set to device memory
    }

    entry |= phys_addr & PTE_ADDR_MASK;
    return entry;
}

fn virtToPageTableIndex(virt: u64, level: u3) u9 {
    const shift: u6 = @truncate(3 - @as(u32, @intCast(level)) * 9 + 12); // Each level indexes 9 bits, starting from 12
    return @truncate((virt >> shift) & 0x1FF); // 9 bits per level
}

/// Convert virtual address bits [47:39] to level 0 index
fn virtToL0Index(virt: u64) u9 {
    return virtToPageTableIndex(virt, LEVEL_0);
}

/// Convert virtual address bits [38:30] to level 1 index
fn virtToL1Index(virt: u64) u9 {
    return virtToPageTableIndex(virt, LEVEL_1);
}

/// Convert virtual address bits [29:21] to level 2 index
fn virtToL2Index(virt: u64) u9 {
    return virtToPageTableIndex(virt, LEVEL_2);
}

/// Convert virtual address bits [20:12] to level 3 index
fn virtToL3Index(virt: u64) u9 {
    return virtToPageTableIndex(virt, LEVEL_3);
}

fn setTableEntry(entry: *PageTableEntry, phys_addr: u64, is_table: bool) void {
    entry.* = phys_addr & PTE_ADDR_MASK;
    entry.* |= PTE_VALID;
    if (is_table) {
        entry.* |= PTE_TABLE;
    }
}

fn clearTableEntry(entry: *PageTableEntry) void {
    entry.* = 0;
}

fn invalidateTLBEntry(vaddr: u64) void {
    asm volatile (
        \\ dsb ishst            // Data synchronization barrier
        \\ tlbi vaae1is, %[addr] // Invalidate by VA, all ASID, EL1, Inner Shareable
        \\ dsb ish             // Ensure completion of TLB invalidation
        \\ isb                 // Instruction synchronization barrier
        :
        : [addr] "r" (vaddr >> 12),
        : "memory"
    );
}

fn invalidateAllTLB() void {
    asm volatile (
        \\ dsb ishst      // Data synchronization barrier
        \\ tlbi vmalle1is // Invalidate all TLB entries for EL1, Inner Shareable
        \\ dsb ish       // Ensure completion of TLB invalidation
        \\ isb           // Instruction synchronization barrier
        ::: "memory");
}

///
/// Handle page faults during runtime tests
fn rt_pageFault(ctx: *arch.CpuState) u32 {
    faulted = true;
    // Return to the appropriate fault callback
    if (use_callback2) {
        ctx.pc = @intFromPtr(&rt_fault_callback2);
    } else {
        ctx.pc = @intFromPtr(&rt_fault_callback);
    }
    return @intFromPtr(ctx);
}

fn rt_accessUnmappedMem(v_end: u32) void {
    use_callback2 = false;
    faulted = false;
    // Accessing unmapped mem causes a page fault
    const ptr = @as(*u8, @ptrFromInt(v_end));
    const value = ptr.*;
    // Need this as in release builds the above is optimised out so it needs to be used
    log.err("FAILURE: Value: {}\n", .{value});
    // This is the label that we return to after processing the page fault
    asm volatile (
        \\.global rt_fault_callback
        \\rt_fault_callback:
    );
    if (!faulted) {
        panic(@errorReturnTrace(), "FAILURE: Paging should have faulted\n", .{});
    }
    log.info("Tested accessing unmapped memory\n", .{});
}

fn rt_accessMappedMem(v_end: u32) void {
    use_callback2 = true;
    faulted = false;
    // Accessing mapped memory doesn't cause a page fault
    const ptr = @as(*u8, @ptrFromInt(v_end - PAGE_SIZE_4KB));
    // Print the value to avoid the load from being optimised away
    log.info("Read value in mapped memory: {}\n", .{ptr.*});
    asm volatile (
        \\.global rt_fault_callback2
        \\rt_fault_callback2:
    );
    if (faulted) {
        panic(@errorReturnTrace(), "FAILURE: Paging shouldn't have faulted\n", .{});
    }
    log.info("Tested accessing mapped memory\n", .{});
}

/// Run runtime tests for the paging subsystem
pub fn runtimeTests(v_end: u32) void {
    // Enable User Access Prevention (PXN in AArch64) if supported
    asm volatile (
        \\ mrs x0, id_aa64mmfr0_el1   // Memory Model Feature Register
        \\ ubfx x0, x0, #8, #4        // Extract UAO field
        \\ cbz x0, 1f                  // Skip if UAO not supported
        \\ mrs x0, sctlr_el1
        \\ orr x0, x0, #(1 << 23)     // Set UAO bit
        \\ msr sctlr_el1, x0
        \\ isb
        \\1:
    );

    rt_accessUnmappedMem(v_end);
    rt_accessMappedMem(v_end);
}
