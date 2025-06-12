//! PL011 UART driver implementation for ARM64
//! This implements a basic UART driver for the PL011 UART controller
//! commonly found in ARM platforms and QEMU.

const std = @import("std");

//For simple UART operations without configuration
pub fn simple_putc(c: u8) void {
    // Directly write to UART data register
    const uart_base = @as(*volatile u32, @ptrFromInt(0x09000000 + 0x000));
    uart_base.* = @as(u32, c);
}

//For simple UART operations without configuration
pub fn simple_getc() u8 {
    // Read from UART data register
    const uart_base = @as(*volatile u32, @ptrFromInt(0x09000000 + 0x000));
    return @truncate(uart_base.*);
}

//For simple UART operations without configuration
pub fn simple_print(str: []const u8) void {
    for (str) |c| {
        simple_putc(c);
    }
}

/// UART Base address for QEMU virt machine
const UART_BASE = 0x09000000;

/// UART register offsets
const Register = struct {
    const DR = 0x000; // Data Register
    const FR = 0x018; // Flag Register
    const IBRD = 0x024; // Integer Baud Rate Divisor
    const FBRD = 0x028; // Fractional Baud Rate Divisor
    const LCRH = 0x02C; // Line Control Register
    const CR = 0x030; // Control Register
    const IMSC = 0x038; // Interrupt Mask Set/Clear Register
    const ICR = 0x044; // Interrupt Clear Register
};

/// Flag register bits
const FR_BUSY = 1 << 3;
const FR_RXFE = 1 << 4; // Receive FIFO empty
const FR_TXFF = 1 << 5; // Transmit FIFO full

/// Line Control Register bits
const LCRH_FEN = 1 << 4; // FIFO enable
const LCRH_WLEN_8 = 3 << 5; // 8 bit word length

/// Control Register bits
const CR_UARTEN = 1 << 0; // UART enable
const CR_TXE = 1 << 8; // Transmit enable
const CR_RXE = 1 << 9; // Receive enable

/// UART Error type
pub const Error = error{
    Busy,
    BufferFull,
    BufferEmpty,
};

/// UART configuration struct
const Config = struct {
    baud_rate: u32 = 115200,
    data_bits: u4 = 8,
    stop_bits: u2 = 1,
    parity: bool = false,
};

/// UART instance struct
const Uart = struct {
    base_addr: usize,
    config: Config,

    const Self = @This();

    /// Initialize UART with the given configuration
    pub fn init(self: *Self) void {
        // Disable UART before configuration
        self.writeReg(Register.CR, 0);

        // Calculate baud rate divisors
        // UART_CLK = 48MHz (typical for QEMU virt)
        // Divisor = UART_CLK / (16 * baud_rate)
        const uart_clock: u32 = 48_000_000;
        const divisor = uart_clock / (16 * self.config.baud_rate);
        const fractional = @as(u32, @intFromFloat((@as(f32, @floatFromInt(uart_clock)) / (16.0 * @as(f32, @floatFromInt(self.config.baud_rate))) -
            @as(f32, @floatFromInt(divisor))) * 64.0 + 0.5));

        // Set baud rate
        self.writeReg(Register.IBRD, divisor);
        self.writeReg(Register.FBRD, fractional);

        // Configure line control (8N1)
        self.writeReg(Register.LCRH, LCRH_FEN | LCRH_WLEN_8);

        // Enable UART, RX and TX
        self.writeReg(Register.CR, CR_UARTEN | CR_TXE | CR_RXE);
    }

    /// Write a single byte to UART
    pub fn writeByte(self: *Self, byte: u8) Error!void {
        // Wait until UART is ready to transmit
        while ((self.readReg(Register.FR) & FR_TXFF) != 0) {
            if ((self.readReg(Register.FR) & FR_BUSY) != 0) {
                return Error.Busy;
            }
            std.atomic.spinLoopHint();
        }

        self.writeReg(Register.DR, byte);
    }

    /// Read a single byte from UART
    pub fn readByte(self: *Self) Error!u8 {
        // Check if receive FIFO is empty
        if ((self.readReg(Register.FR) & FR_RXFE) != 0) {
            return Error.BufferEmpty;
        }

        return @truncate(self.readReg(Register.DR));
    }

    /// Write a string to UART
    pub fn writeString(self: *Self, str: []const u8) Error!void {
        for (str) |byte| {
            try self.writeByte(byte);
        }
    }

    /// Helper function to read a register
    inline fn readReg(self: *const Self, reg: u32) u32 {
        const ptr = @as(*volatile u32, @ptrFromInt(self.base_addr + reg));
        return ptr.*;
    }

    /// Helper function to write a register
    inline fn writeReg(self: *const Self, reg: u32, value: u32) void {
        const ptr = @as(*volatile u32, @ptrFromInt(self.base_addr + reg));
        ptr.* = value;
    }
};

/// Global UART instance
var uart0 = Uart{
    .base_addr = UART_BASE,
    .config = .{},
};

/// Initialize the UART driver
pub fn init() void {
    uart0.init();
}

/// Write a byte to UART
pub fn putc(c: u8) Error!void {
    return uart0.writeByte(c);
}

/// Read a byte from UART
pub fn getc() Error!u8 {
    return uart0.readByte();
}

/// Write a string to UART
pub fn print(str: []const u8) Error!void {
    return uart0.writeString(str);
}

/// Write a formatted string to UART
pub fn printf(comptime format: []const u8, args: anytype) Error!void {
    var buf: [10]u8 = [_]u8{0} ** 10; // Buffer for formatted output
    const str = std.fmt.bufPrintZ(&buf, format ++ "\x00", args) catch {
        simple_print("Error formatting string\n");
        return Error.BufferFull;
    };
    simple_print(str);
    return uart0.writeString(format);
}

pub fn setCursor(_: u8, _: u8) void {
    // Not implemented for UART, as it is a simple output device
    // Cursor management is typically handled by terminal emulators
}

pub fn clear() void {
    // Not implemented for UART, as it is a simple output device
    // Cursor management is typically handled by terminal emulators
}
