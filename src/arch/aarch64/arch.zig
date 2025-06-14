const std = @import("std");
const Allocator = std.mem.Allocator;
const gic = @import("gic.zig");
const log = std.log.scoped(.arm64_arch);
const builtin = @import("builtin");
const uart = @import("uart.zig");
const serial = @import("serial.zig");
const mem = @import("../../kernel/mem.zig");
const paging = @import("paging.zig");
const vmm = @import("../../kernel/vmm.zig");
const keyboard = @import("keyboard.zig");
const Serial = @import("../../kernel/serial.zig").Serial;
const panic = @import("../../kernel/panic.zig").panic;
const TTY = @import("../../kernel/tty.zig").TTY;
const Keyboard = @import("../../kernel/keyboard.zig").Keyboard;
const Task = @import("../../kernel/task.zig").Task;
const MemProfile = @import("../../kernel/mem.zig").MemProfile;

/// The type of a device.
pub const Device = struct {}; // ARM64 devices will be defined later

/// The type of the date and time structure.
pub const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

/// Virtual and physical memory layout constants
extern var KERNEL_VADDR_END: *u64;
extern var KERNEL_VADDR_START: *u64;
extern var KERNEL_PHYSADDR_END: *u64;
extern var KERNEL_PHYSADDR_START: *u64;
extern var KERNEL_ADDR_OFFSET: *u64;
extern var KERNEL_STACK_START: *u64;
extern var KERNEL_STACK_END: *u64;

/// ARM64 CPU state saved during exceptions/interrupts
pub const CpuState = packed struct {
    // General purpose registers
    x0: u64,
    x1: u64,
    x2: u64,
    x3: u64,
    x4: u64,
    x5: u64,
    x6: u64,
    x7: u64,
    x8: u64,
    x9: u64,
    x10: u64,
    x11: u64,
    x12: u64,
    x13: u64,
    x14: u64,
    x15: u64,
    x16: u64,
    x17: u64,
    x18: u64,
    x19: u64,
    x20: u64,
    x21: u64,
    x22: u64,
    x23: u64,
    x24: u64,
    x25: u64,
    x26: u64,
    x27: u64,
    x28: u64,
    x29: u64, // Frame pointer
    x30: u64, // Link register

    // Special registers
    sp: u64, // Stack pointer
    pc: u64, // Program counter
    pstate: u64, // Processor state
    ttbr0: u64, // Translation table base register 0
    ttbr1: u64, // Translation table base register 1

    spsr: u64, // Saved Program Status Register
    elr: u64, // Exception Link Register

    // Exception info
    esr: u64, // Exception syndrome register
    far: u64, // Fault address register

    error_code: u64 = 0x00,
    eip: u64 = 0x00, // Exception instruction pointer

    pub fn empty() CpuState {
        return .{
            .x0 = undefined,
            .x1 = undefined,
            .x2 = undefined,
            .x3 = undefined,
            .x4 = undefined,
            .x5 = undefined,
            .x6 = undefined,
            .x7 = undefined,
            .x8 = undefined,
            .x9 = undefined,
            .x10 = undefined,
            .x11 = undefined,
            .x12 = undefined,
            .x13 = undefined,
            .x14 = undefined,
            .x15 = undefined,
            .x16 = undefined,
            .x17 = undefined,
            .x18 = undefined,
            .x19 = undefined,
            .x20 = undefined,
            .x21 = undefined,
            .x22 = undefined,
            .x23 = undefined,
            .x24 = undefined,
            .x25 = undefined,
            .x26 = undefined,
            .x27 = undefined,
            .x28 = undefined,
            .x29 = undefined,
            .x30 = undefined,
            .sp = undefined,
            .pc = undefined,
            .pstate = undefined,
            .ttbr0 = undefined,
            .ttbr1 = undefined,
            .esr = undefined,
            .far = undefined,
            .spsr = undefined,
            .elr = undefined,
        };
    }
};

/// The boot payload contains physical memory info and device tree pointer
pub const BootPayload = struct {
    dtb_ptr: u64, // Device Tree Binary pointer
    mem_size: u64, // Total physical memory size
};

/// The type of the payload passed to a virtual memory mapper
pub const VmmPayload = *paging.PageTable;

/// The payload used in the kernel virtual memory manager
pub const KERNEL_VMM_PAYLOAD = &paging.kernel_page_table;

/// The architecture's virtual memory mapper
pub const VMM_MAPPER: vmm.Mapper(VmmPayload) = vmm.Mapper(VmmPayload){
    .mapFn = &paging.map,
    .unmapFn = &paging.unmap,
};

/// The size of each allocatable block of memory (64KB for ARM64)
pub const MEMORY_BLOCK_SIZE: usize = 64 * 1024;

/// Data Memory Barrier - ensures all memory accesses before it complete
pub fn ioWait() void {
    asm volatile ("dmb sy" ::: "memory");
}

///
/// Enable interrupts.
///
pub fn enableInterrupts() void {
    asm volatile ("msr daifclr, #0xf");
}

///
/// Disable interrupts.
///
pub fn disableInterrupts() void {
    asm volatile ("msr daifset, #0xf");
}

///
/// Halt the CPU, but interrupts will still be called.
///
pub fn halt() void {
    asm volatile ("wfi");
}

///
/// Wait the kernel but still can handle interrupts.
///
pub fn spinWait() noreturn {
    enableInterrupts();
    while (true) {
        halt();
    }
}

///
/// Halt the kernel. No interrupts will be handled.
///
pub fn haltNoInterrupts() noreturn {
    while (true) {
        disableInterrupts();
        halt();
    }
}

///
/// Write a byte to serial port com1. Used by the serial initialiser
///
/// Arguments:
///     IN byte: u8 - The byte to write
///
fn writeSerialCom1(byte: u8) void {
    serial.write(byte, serial.Port.COM1);
}

fn writeUart(byte: u8) void {
    uart.putc(byte) catch {
        @panic("Error writing to UART\n");
    };
}

///
/// Initialise serial communication using port COM1 and construct a Serial instance
///
/// Arguments:
///     IN boot_payload: arch.BootPayload - The payload passed at boot. Not currently used by x86
///
/// Return: serial.Serial
///     The Serial instance constructed with the function used to write bytes
///
pub fn initSerial(boot_payload: BootPayload) Serial {
    _ = boot_payload;
    return Serial{
        .write = writeUart,
    };
}

///
/// Initialise the TTY and construct a TTY instance
///
/// Arguments:
///     IN boot_payload: BootPayload - The payload passed to the kernel on boot
///
/// Return: tty.TTY
///     The TTY instance constructed with the information required by the rest of the kernel
///
pub fn initTTY(boot_payload: BootPayload) TTY {
    _ = boot_payload;
    return .{
        .print = uart.print,
        .setCursor = uart.setCursor,
        .cols = 80,
        .rows = 25,
        .clear = uart.clear,
    };
}

///
/// Initialise the system's memory. Populates a memory profile with boot modules from grub, the amount of available memory, the reserved regions of virtual and physical memory as well as the start and end of the kernel code
///
/// Arguments:
///     IN mb_info: *multiboot.multiboot_info_t - The multiboot info passed by grub
///
/// Return: mem.MemProfile
///     The constructed memory profile
///
/// Error: Allocator.Error
///     Allocator.Error.OutOfMemory - There wasn't enough memory in the allocated created to populate the memory profile, consider increasing mem.FIXED_ALLOC_SIZE
///
pub fn initMem(boot_payload: BootPayload) Allocator.Error!MemProfile {
    log.info("Init memory\n", .{});
    defer log.info("Done\n", .{});

    log.debug("KERNEL_ADDR_OFFSET:    0x{X}\n", .{@intFromPtr(&KERNEL_ADDR_OFFSET)});
    log.debug("KERNEL_STACK_START:    0x{X}\n", .{@intFromPtr(&KERNEL_STACK_START)});
    log.debug("KERNEL_STACK_END:      0x{X}\n", .{@intFromPtr(&KERNEL_STACK_END)});
    log.debug("KERNEL_VADDR_START:    0x{X}\n", .{@intFromPtr(&KERNEL_VADDR_START)});
    log.debug("KERNEL_VADDR_END:      0x{X}\n", .{@intFromPtr(&KERNEL_VADDR_END)});
    log.debug("KERNEL_PHYSADDR_START: 0x{X}\n", .{@intFromPtr(&KERNEL_PHYSADDR_START)});
    log.debug("KERNEL_PHYSADDR_END:   0x{X}\n", .{@intFromPtr(&KERNEL_PHYSADDR_END)});

    const allocator = mem.fixed_buffer_allocator.allocator();
    const reserved_physical_mem = std.ArrayList(mem.Range).init(allocator);
    var reserved_virtual_mem = std.ArrayList(mem.Map).init(allocator);

    // Map kernel code section
    const kernel_virt = mem.Range{
        .start = @intFromPtr(&KERNEL_VADDR_START),
        .end = @intFromPtr(&KERNEL_STACK_START),
    };
    const kernel_phy = mem.Range{
        .start = mem.virtToPhys(kernel_virt.start),
        .end = mem.virtToPhys(kernel_virt.end),
    };
    try reserved_virtual_mem.append(.{
        .virtual = kernel_virt,
        .physical = kernel_phy,
    });

    // Map kernel stack
    const kernel_stack_virt = mem.Range{
        .start = @intFromPtr(&KERNEL_STACK_START),
        .end = @intFromPtr(&KERNEL_STACK_END),
    };
    const kernel_stack_phy = mem.Range{
        .start = mem.virtToPhys(kernel_stack_virt.start),
        .end = mem.virtToPhys(kernel_stack_virt.end),
    };
    try reserved_virtual_mem.append(.{
        .virtual = kernel_stack_virt,
        .physical = kernel_stack_phy,
    });

    // TODO: Parse device tree to get memory regions

    return MemProfile{
        .vaddr_end = @as([*]u8, @ptrCast(&KERNEL_VADDR_END)),
        .vaddr_start = @as([*]u8, @ptrCast(&KERNEL_VADDR_START)),
        .physaddr_end = @as([*]u8, @ptrCast(&KERNEL_PHYSADDR_END)),
        .physaddr_start = @as([*]u8, @ptrCast(&KERNEL_PHYSADDR_START)),
        .mem_kb = boot_payload.mem_size / 1024,
        .modules = &[_]mem.Module{},
        .physical_reserved = reserved_physical_mem.items,
        .virtual_reserved = reserved_virtual_mem.items,
        .fixed_allocator = mem.fixed_buffer_allocator,
    };
}

///
/// Initialise a stack and vmm payload used for creating a task.
/// Currently only supports fn () noreturn functions for the entry point.
///
/// Arguments:
///     IN task: *Task           - The task to be initialised. The function will only modify whatever
///                                is required by the architecture. In the case of x86, it will put
///                                the initial CpuState on the kernel stack.
///     IN entry_point: usize    - The pointer to the entry point of the function. Functions only
///                                supported is fn () noreturn
///     IN allocator: Allocator - The allocator use for allocating a stack.
///     IN set_up_stack: bool   - Set up the kernel and user stacks (register values, PC etc.) for task entry
///
/// Error: Allocator.Error
///     OutOfMemory - Unable to allocate space for the stack.
///
pub fn initTask(task: *Task, entry_point: usize, allocator: Allocator, set_up_stack: bool) Allocator.Error!void {
    task.vmm.payload = &paging.kernel_page_table;

    if (set_up_stack) {
        const stack = &task.kernel_stack;
        const kernel_stack_bottom = if (task.kernel) task.kernel_stack.len - 36 else task.kernel_stack.len - 38;

        // Set up CPU state at bottom of stack
        var state = @as(*CpuState, @ptrFromInt(stack.*[kernel_stack_bottom]));
        state.* = CpuState.empty();

        // Set up entry point
        state.pc = entry_point;
        state.pstate = 0x3c5; // EL1h, all interrupts enabled
        state.sp = @intFromPtr(&task.kernel_stack[task.kernel_stack.len - 1]);

        if (!task.kernel) {
            state.pstate = 0x3c0; // EL0t
            state.sp = @intFromPtr(&task.user_stack[task.user_stack.len - 1]);
        }

        task.stack_pointer = @intFromPtr(&stack.*[kernel_stack_bottom]);
    }

    if (!task.kernel and !builtin.is_test) {
        // Create new translation tables for user task
        const new_tt = try allocator.create(paging.PageTable);
        new_tt.* = paging.kernel_page_table;
        task.vmm.payload = new_tt;
    }
}

///
/// Initialise the architecture
///
/// Arguments:
///     IN mem_profile: *const MemProfile - The memory profile of the computer. Used to set up
///                                         paging.
///
pub fn init(mem_profile: *const MemProfile) void {
    // Initialize exception vectors

    // asm volatile (
    //     \\.align 11
    //     \\adr x0, vector_table
    //     \\msr vbar_el1, x0
    //     ::: "x0");

    // Initialize MMU and caches
    paging.init(mem_profile);

    // Initialize UART for early output
    // TODO: Fix issues with uart.init()
    //uart.init();
}

///
/// Check the state of the user task used for runtime testing for the expected values. These should mirror those in test/user_program.s
///
/// Arguments:
///     IN ctx: *const CpuState - The task's saved state
///
/// Return: bool
///     True if the expected values were found, else false
///
pub fn runtimeTestCheckUserTaskState(ctx: *const CpuState) bool {
    return ctx.x0 == 0xCAFE and ctx.x1 == 0xBEEF;
}

///
/// Trigger a page fault to test paging and its diagnostics
///
/// Arguments:
///     IN the_vmm: The VMM to get an unallocated test address from
///
pub fn runtimeTestChecksMem(the_vmm: *const vmm.VirtualMemoryManager(VmmPayload)) void {
    var addr = the_vmm.start;
    while (addr < the_vmm.end and (the_vmm.isSet(addr) catch unreachable)) {
        addr += vmm.BLOCK_SIZE;
    }
    const should_fault = @as(*usize, @ptrFromInt(addr)).*;
    log.debug("This should not be printed: {x}\n", .{should_fault});
}
