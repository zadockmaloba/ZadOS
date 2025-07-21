const std = @import("std");
const build_options = @import("build_options");

const CTRL_ENABLE: u32	= 0x80;
const CTRL_MODE_FREE: u32 = 0x00;
const CTRL_MODE_PERIODIC: u32 =	0x40;
const CTRL_INT_ENABLE: u32 = (1<<5);
const CTRL_DIV_NONE:u32	= 0x00;
const CTRL_DIV_16: u32	= 0x04;
const CTRL_DIV_256: u32	= 0x08;
const CTRL_SIZE_32: u32	= 0x02;
const CTRL_ONESHOT: u32	= 0x01;

const REG_LOAD: u32 = 0x00;
const REG_VALUE: u32 = 0x01;
const REG_CTRL: u32 = 0x02;
const REG_INTCLR: u32 = 0x03;
const REG_INTSTAT: u32 = 0x04;
const REG_INTMASK: u32 = 0x05;
const REG_BGLOAD: u32 = 0x06;



pub const MMIO_BASE: u32 = switch(build_options.arch) {
    .AArch64 => switch(build_options.target_board) {
        .Qemu_Virt => 0x3F000000, // Base address for QEMU Virt
        .RaspberryPi4 => 0x3F000000, // Base address for Raspberry Pi 4
        .RaspberryPi400 => 0x3F000000, // Base address for Raspberry Pi 400
        .Pine64 => 0x01C00000, // Base address for Pine64
        .RockPro64 => 0x01C00000, // Base address for RockPro64
        .OdroidN2 => 0xFF800000, // Base address for Odroid N2
        .OdroidN2Plus => 0xFF800000, // Base address for Odroid N2 Plus
        else => @panic("Unsupported board for AArch64"),
    }, // Base address for AArch64
    .RiscV64 => 0x10000000, // Example base address for RISC-V
    .X86_64 => 0xFEC00000, // Example base address for x86_64
};

pub inline fn mmio_write(reg: u32, value: u32) void {
    @as(*volatile u32, @ptrFromInt(MMIO_BASE + reg)).* = value;
}

pub inline fn mmio_read(reg: u32) u32 {
    return @as(u32, @ptrFromInt(MMIO_BASE + reg)).*;
}
