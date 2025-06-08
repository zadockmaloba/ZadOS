//! The main kernel file for ZadOS
const std = @import("std");

// This is our kernel entry point called from start.S
export fn kernel_main() callconv(.C) void {
    // In bare metal, we can't use std.debug.print yet
    // We'll implement UART output later
    while (true) {
        @import("std").atomic.spinLoopHint();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
