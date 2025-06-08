//! The main kernel file for ZadOS
const std = @import("std");
const uart = @import("drivers/uart.zig");

// This is our kernel entry point called from start.S
export fn kernel_main() callconv(.C) void {
    // Initialize UART
    uart.init();

    // Print welcome message
    _ = uart.print("ZadOS is booting...\n") catch {};

    // Main kernel loop
    while (true) {
        std.atomic.spinLoopHint();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
