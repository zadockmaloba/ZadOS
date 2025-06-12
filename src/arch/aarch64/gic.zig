const std = @import("std");
const log = std.log.scoped(.gic);

/// GIC base addresses for QEMU virt machine
const GICD_BASE: usize = 0x08000000; // GIC Distributor
const GICC_BASE: usize = 0x08010000; // GIC CPU Interface

/// GIC Distributor registers
const GICD_CTLR = 0x000; // Distributor Control Register
const GICD_TYPER = 0x004; // Interrupt Controller Type Register
const GICD_IIDR = 0x008; // Distributor Implementer Identification Register
const GICD_IGROUPR = 0x080; // Interrupt Group Registers
const GICD_ISENABLER = 0x100; // Interrupt Set-Enable Registers
const GICD_ICENABLER = 0x180; // Interrupt Clear-Enable Registers
const GICD_ISPENDR = 0x200; // Interrupt Set-Pending Registers
const GICD_ICPENDR = 0x280; // Interrupt Clear-Pending Registers
const GICD_IPRIORITYR = 0x400; // Interrupt Priority Registers
const GICD_ITARGETSR = 0x800; // Interrupt Processor Targets Registers
const GICD_ICFGR = 0xC00; // Interrupt Configuration Registers

/// GIC CPU Interface registers
const GICC_CTLR = 0x0000; // CPU Interface Control Register
const GICC_PMR = 0x0004; // Interrupt Priority Mask Register
const GICC_BPR = 0x0008; // Binary Point Register
const GICC_IAR = 0x000C; // Interrupt Acknowledge Register ffp
const GICC_EOIR = 0x0010; // End of Interrupt Register
const GICC_RPR = 0x0014; // Running Priority Register
const GICC_HPPIR = 0x0018; // Highest Priority Pending Interrupt Register

/// Max number of interrupts supported by GIC
const MAX_INTERRUPTS: usize = 1024;
const NUM_INT_REGS: usize = MAX_INTERRUPTS / 32;

pub const IRQ_REAL_TIME_CLOCK = 0;
pub const IRW_KEYBOARD = 1;

/// Interrupt handler function type
pub const InterruptHandler = *const fn () callconv(.Naked) void;

/// Interrupt handler table
var handlers: [MAX_INTERRUPTS]?InterruptHandler = .{null} ** MAX_INTERRUPTS;

/// Read a 32-bit register from the GIC Distributor
fn readGicdReg(offset: usize) u32 {
    return @atomicLoad(u32, @as([*]u8, @ptrFromInt(GICD_BASE + offset)), .monotonic);
}

/// Write a 32-bit value to a GIC Distributor register
fn writeGicdReg(offset: usize, value: u32) void {
    @atomicStore(u32, @as([*]u8, @ptrFromInt(GICD_BASE + offset)), value, .monotonic);
}

/// Read a 32-bit register from the GIC CPU Interface
fn readGiccReg(offset: usize) u32 {
    return @atomicLoad(u32, @as([*]u8, @ptrFromInt(GICC_BASE + offset)), .monotonic);
}

/// Write a 32-bit value to a GIC CPU Interface register
fn writeGiccReg(offset: usize, value: u32) void {
    @atomicStore(u32, @as([*]u8, @ptrFromInt(GICC_BASE + offset)), value, .monotonic);
}

/// Initialize the GIC
pub fn init() void {
    log.info("Initializing GIC...\n", .{});

    // Read GIC type information
    const gic_type = readGicdReg(GICD_TYPER);
    const num_irqs = ((gic_type & 0x1F) + 1) * 32;
    log.debug("GIC supports {} interrupts\n", .{num_irqs});

    // Disable the distributor while configuring
    writeGicdReg(GICD_CTLR, 0);

    // Configure all interrupts as level-triggered
    var i: usize = 0;
    while (i < NUM_INT_REGS) : (i += 1) {
        writeGicdReg(GICD_ICFGR + i * 4, 0);
    }

    // Set all interrupts to group 1
    i = 0;
    while (i < NUM_INT_REGS) : (i += 1) {
        writeGicdReg(GICD_IGROUPR + i * 4, 0xFFFFFFFF);
    }

    // Set priority for all interrupts
    i = 0;
    while (i < MAX_INTERRUPTS) : (i += 1) {
        writeGicdReg(GICD_IPRIORITYR + i, 0xA0); // Priority 0xA0 (medium-low)
    }

    // Set target of all interrupts to CPU0
    i = 0;
    while (i < MAX_INTERRUPTS) : (i += 1) {
        writeGicdReg(GICD_ITARGETSR + i * 4, 0x01);
    }

    // Clear pending status of all interrupts
    i = 0;
    while (i < NUM_INT_REGS) : (i += 1) {
        writeGicdReg(GICD_ICPENDR + i * 4, 0xFFFFFFFF);
    }

    // Disable all interrupts
    i = 0;
    while (i < NUM_INT_REGS) : (i += 1) {
        writeGicdReg(GICD_ICENABLER + i * 4, 0xFFFFFFFF);
    }

    // Enable the distributor
    writeGicdReg(GICD_CTLR, 1);

    // Initialize CPU interface
    writeGiccReg(GICC_CTLR, 1); // Enable CPU interface
    writeGiccReg(GICC_PMR, 0xFF); // Set priority mask
    writeGiccReg(GICC_BPR, 0x07); // Binary point register
}

/// Enable a specific interrupt
pub fn enableInterrupt(irq: u32) void {
    const reg = GICD_ISENABLER + (irq / 32) * 4;
    const bit = @as(u32, 1) << @as(u5, @intCast(irq % 32));
    writeGicdReg(reg, bit);
}

/// Disable a specific interrupt
pub fn disableInterrupt(irq: u32) void {
    const reg = GICD_ICENABLER + (irq / 32) * 4;
    const bit = @as(u32, 1) << @as(u5, @intCast(irq % 32));
    writeGicdReg(reg, bit);
}

/// Register an interrupt handler
pub fn registerHandler(irq: u32, handler: InterruptHandler) void {
    if (irq >= MAX_INTERRUPTS) {
        log.err("Invalid interrupt number: {}\n", .{irq});
        return;
    }
    handlers[irq] = handler;
}

/// Get the current interrupt number
pub fn getActiveInterrupt() u32 {
    const iar = readGiccReg(GICC_IAR);
    return iar & 0x3FF; // Mask to get interrupt ID
}

/// Signal completion of interrupt handling
pub fn endOfInterrupt(irq: u32) void {
    writeGiccReg(GICC_EOIR, irq);
}

/// Handle an interrupt
pub fn handleInterrupt() void {
    const irq = getActiveInterrupt();

    if (irq >= MAX_INTERRUPTS) {
        log.err("Invalid interrupt number: {}\n", .{irq});
        return;
    }

    // Call the registered handler if it exists
    if (handlers[irq]) |handler| {
        handler();
    } else {
        log.warn("No handler for interrupt {}\n", .{irq});
    }

    endOfInterrupt(irq);
}
