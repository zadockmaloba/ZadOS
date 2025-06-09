//! The main kernel file for ZadOS
const std = @import("std");
const uart = @import("arch/aarch64/uart.zig");

pub const std_options: std.Options = .{
    .enable_segfault_handler = true, // Enable segfault handler
    .page_size_max = 4096, // Set max page size to 4KB
    .page_size_min = 1024, // Set min page size to 1KB
};

// This is our kernel entry point called from start.S
export fn kernel_main() callconv(.C) void {
    // Initialize UART
    //uart.init();

    uart.simple_print("ZadOS is booting 1...\n");
    // Print welcome message
    _ = uart.printf("ZadOS is booting {d}...\n", .{2}) catch {
        uart.simple_print("Failed to print welcome message\n");
    };

    // Main kernel loop
    while (true) {
        std.atomic.spinLoopHint();
    }
}
