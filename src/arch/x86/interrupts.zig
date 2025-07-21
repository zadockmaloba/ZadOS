const arch = @import("arch.zig");
const syscalls = @import("syscalls.zig");
const irq = @import("irq.zig");
const std = @import("std");
const log = std.log.scoped(.interrupts);
const gic = @import("gic.zig");
const uart = @import("uart.zig");
const scheduler = @import("../../kernel/scheduler.zig");

extern fn irqHandler(ctx: *arch.CpuState) usize;
extern fn isrHandler(ctx: *arch.CpuState) usize;

///
/// The main handler for all exceptions and interrupts. This will then go and call the correct
/// handler for an ISR or IRQ.
///
/// Arguments:
///     IN ctx: *arch.CpuState - Pointer to the exception context containing the contents
///                              of the registers at the time of a exception.
///
export fn handler(ctx: *arch.CpuState) usize {
    if (ctx.int_num < irq.IRQ_OFFSET or ctx.int_num == syscalls.INTERRUPT) {
        return isrHandler(ctx);
    } else {
        return irqHandler(ctx);
    }
}

///
/// Initialize interrupt handling
///
pub fn init() void {
    log.info("Initializing interrupts...\n", .{});

    // Initialize the GIC
    gic.init();

    // Register handlers for basic interrupts
    gic.registerHandler(IRQ_UART, uart_handler);
    gic.registerHandler(IRQ_TIMER, timer_handler);

    // Enable specific interrupts
    gic.enableInterrupt(IRQ_UART);
    gic.enableInterrupt(IRQ_TIMER);
}

///
/// UART interrupt handler
///
fn uart_handler() void {
    uart.handleInterrupt();
}

///
/// Timer interrupt handler
///
fn timer_handler() void {
    scheduler.tick();
}

///
/// Interrupt numbers for common devices
///
const IRQ_UART: u32 = 33; // PL011 UART
const IRQ_TIMER: u32 = 27; // ARM Generic Timer

///
/// Hardware specific interrupt handling, called from assembly
///
pub export fn handleException(_type: u32, esr: u64, elr: u64) void {
    switch (_type) {
        0 => { // Synchronous
            log.err("Synchronous exception: ESR=0x{X}, ELR=0x{X}\n", .{ esr, elr });
        },
        1 => { // IRQ
            gic.handleInterrupt();
        },
        2 => { // FIQ
            log.err("FIQ not implemented\n", .{});
        },
        3 => { // SError
            log.err("SError: ESR=0x{X}, ELR=0x{X}\n", .{ esr, elr });
        },
        else => {
            log.err("Unknown exception type {}\n", .{_type});
        },
    }
}
