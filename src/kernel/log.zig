const std = @import("std");
const fmt = std.fmt;
const build_options = @import("build_options");
const scheduler = @import("scheduler.zig");
const uart = @import("../arch/aarch64/uart.zig");

/// The errors that can occur when logging
const LoggingError = error{};

/// The Writer for the format function
const Writer = std.io.Writer(*uart.Uart, LoggingError, logCallback);
const bufferedWriter = std.io.bufferedWriter(Writer{ .context = &uart.uart0});

const TerminalWriter = uart.UartWriter;

///
/// The call back function for the std library format function.
///
/// Arguments:
///     context: void   - The context of the printing. There isn't a need for a context for this
///                       so is void.
///     str: []const u8 - The string to print to the serial terminal.
///
/// Return: usize
///     The number of bytes written. This will always be the length of the string to print.
///
/// Error: LoggingError
///     {} - No error as LoggingError is empty.
///
fn logCallback(context: *uart.Uart, str: []const u8) LoggingError!usize {
    // Suppress unused var warning
    _ = context;
    uart.simple_print(str);
    return str.len;
}

///
/// Write a message to the log output stream with a certain logging level.
///
/// Arguments:
///     IN comptime level: std.log.Level - The logging level to use. Determines the message prefix
///                                        and whether it is filtered.
///     IN comptime format: []const u8   - The message format. Uses the standard format
///                                        specification options.
///     IN args: anytype                 - A struct of the parameters for the format string.
///
pub fn log(comptime level: std.log.Level, comptime format: []const u8, args: anytype) void {
    scheduler.taskSwitching(false);
    uart.printf("[" ++ @tagName(level) ++ "] " ++ format, args) catch {
        // If the UART fails, we can't log anything, so just ignore the error
        // This is a critical failure, but we can't do anything about it
        uart.simple_print("Failed to log message: ");
    };
    //fmt.format(Writer{ .context = &uart.uart0}, "[" ++ @tagName(level) ++ "] " ++ format, args) catch unreachable;
    scheduler.taskSwitching(true);
}

///
/// Initialise the logging stream using the given Serial instance.
///
/// Arguments:
///     IN ser: Serial - The serial instance to use when logging
///
pub fn init() void {
    uart.init();
    switch (build_options.test_mode) {
        .Initialisation => runtimeTests(),
        else => {},
    }
}

///
/// The logging runtime tests that will test all logging levels.
///
fn runtimeTests() void {
    inline for (@typeInfo(std.log.Level).Enum.fields) |field| {
        const level = @field(std.log.Level, field.name);
        log(level, "Test " ++ field.name ++ " level\n", .{});
        log(level, "Test " ++ field.name ++ " level with args {s}, {}\n", .{ "a", @as(u32, 1) });
    }
}
