//! The main kernel file for ZadOS
const std = @import("std");
const builtin = @import("builtin");
const kmain_log = std.log.scoped(.kmain);
const is_test = builtin.is_test;
const build_options = @import("build_options");
const arch = @import("kernel/arch.zig").internals;
const tty = @import("kernel/tty.zig");
const log_root = @import("kernel/log.zig");
const pmm = @import("kernel/pmm.zig");
//const serial = @import("kernel/serial.zig");
const vmm = @import("kernel/vmm.zig");
const mem = @import("kernel/mem.zig");
const panic_root = @import("kernel/panic.zig");
const task = @import("kernel/task.zig");
const heap = @import("kernel/heap.zig");
const scheduler = @import("kernel/scheduler.zig");
const vfs = @import("kernel/filesystem/vfs.zig");
const initrd = @import("kernel/filesystem/initrd.zig");
const keyboard = @import("kernel/keyboard.zig");
const syscalls = @import("kernel/syscalls.zig");
const Allocator = std.mem.Allocator;

const sys_arch = switch (builtin.cpu.arch) {
    .aarch64 => @import("arch/aarch64/boot.zig"),
    else => unreachable,
};

pub const std_options: std.Options = .{
    .enable_segfault_handler = true,
    .page_size_max = 4096,
    .page_size_min = 4096,
    .logFn = custom_log,
};

// Just call the panic function, as this need to be in the root source file
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ra: ?usize) noreturn {
    @branchHint(.cold);
    _ = ra; // Unused in this context, but can be used for debugging
    panic_root.panic(error_return_trace, "{s}", .{msg});
}

pub const log_level: std.log.Level = .debug;
// Define root.log to override the std implementation
pub fn custom_log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    log_root.log(level, "(" ++ @tagName(scope) ++ "): " ++ format, args);
}

var kernel_heap: heap.FreeListAllocator = undefined;

// This is our kernel entry point called from start.S
export fn kernel_main() callconv(.C) void {
    // Initialize UART
    //uart.init();

    log_root.init();
    const boot_payload = arch.BootPayload{
        .mem_size = 64 * 1024,
        .dtb_ptr = 0,
    };

    const mem_profile = arch.initMem(boot_payload) catch |e| {
        panic_root.panic(@errorReturnTrace(), "Failed to initialise memory profile: {}", .{e});
    };
    var fixed_allocator = mem_profile.fixed_allocator;

    pmm.init(&mem_profile, fixed_allocator.allocator());
    var kernel_vmm = vmm.init(&mem_profile, fixed_allocator.allocator()) catch |e| {
        panic_root.panic(@errorReturnTrace(), "Failed to initialise kernel VMM: {}", .{e});
        return;
    };

    kmain_log.info("Init arch " ++ @tagName(builtin.cpu.arch) ++ "\n", .{});
    arch.init(&mem_profile);
    kmain_log.info("Arch init done\n", .{});

    panic_root.initSymbols(&mem_profile, fixed_allocator.allocator()) catch |e| {
        panic_root.panic(@errorReturnTrace(), "Failed to initialise panic symbols: {}\n", .{e});
    };

    // The VMM and mem runtime tests can't happen until the architecture has initialised itself
    switch (build_options.test_mode) {
        .Initialisation => vmm.runtimeTests(arch.VmmPayload, kernel_vmm, &mem_profile),
        .Memory => arch.runtimeTestChecksMem(kernel_vmm),
        else => {},
    }

    // Give the kernel heap 10% of the available memory. This can be fine-tuned as time goes on.
    var heap_size = mem_profile.mem_kb / 10 * 1024;
    // The heap size must be a power of two so find the power of two smaller than or equal to the heap_size
    if (!std.math.isPowerOfTwo(heap_size)) {
        heap_size = std.math.floorPowerOfTwo(usize, heap_size);
    }
    kernel_heap = heap.init(arch.VmmPayload, kernel_vmm, vmm.Attributes{ .kernel = true, .writable = true, .cachable = true }, heap_size) catch |e| {
        panic_root.panic(@errorReturnTrace(), "Failed to initialise kernel heap: {}\n", .{e});
    };

    syscalls.init(kernel_heap.allocator());
    tty.init(kernel_heap.allocator(), boot_payload);
    //const arch_kb = keyboard.init(fixed_allocator.allocator()) catch |e| {
    //    panic_root.panic(@errorReturnTrace(), "Failed to inititalise keyboard: {}\n", .{e});
    //};
    //if (arch_kb) |kb| {
    //    keyboard.addKeyboard(kb) catch |e| panic_root.panic(@errorReturnTrace(), "Failed to add architecture keyboard: {}\n", .{e});
    //}

    // Get the ramdisk module
    const rd_module = for (mem_profile.modules) |module| {
        if (std.mem.eql(u8, module.name, "initrd.ramdisk")) {
            break module;
        }
    } else null;

    if (rd_module) |module| {
        // Load the ram disk
        const rd_len: usize = module.region.end - module.region.start;
        const ramdisk_bytes = @as([*]u8, @ptrFromInt(module.region.start))[0..rd_len];
        var initrd_stream = std.io.fixedBufferStream(ramdisk_bytes);
        const ramdisk_filesystem = initrd.InitrdFS.init(&initrd_stream, kernel_heap.allocator()) catch |e| {
            panic_root.panic(@errorReturnTrace(), "Failed to initialise ramdisk: {}\n", .{e});
        };

        // Can now free the module as new memory is allocated for the ramdisk filesystem
        kernel_vmm.free(module.region.start) catch |e| {
            panic_root.panic(@errorReturnTrace(), "Failed to free ramdisk: {}\n", .{e});
        };

        // Need to init the vfs after the ramdisk as we need the root node from the ramdisk filesystem
        vfs.setRoot(ramdisk_filesystem.root_node) catch |e| {
            panic_root.panic(@errorReturnTrace(), "Ramdisk root node isn't a directory node: {}\n", .{e});
        };
    }

    scheduler.init(kernel_heap.allocator(), &mem_profile) catch |e| {
        panic_root.panic(@errorReturnTrace(), "Failed to initialise scheduler: {}\n", .{e});
    };

    // Initialisation is finished, now does other stuff
    kmain_log.info("Init\n", .{});

    // Main initialisation finished so can enable interrupts
    arch.enableInterrupts();

    kmain_log.info("Creating init2\n", .{});

    // Create a init2 task
    const stage2_task = task.Task.create(@intFromPtr(&initStage2), true, kernel_vmm, kernel_heap.allocator(), true) catch |e| {
        panic_root.panic(@errorReturnTrace(), "Failed to create init stage 2 task: {}\n", .{e});
    };
    scheduler.scheduleTask(stage2_task, kernel_heap.allocator()) catch |e| {
        panic_root.panic(@errorReturnTrace(), "Failed to schedule init stage 2 task: {}\n", .{e});
    };

    // Can't return for now, later this can return maybe
    // TODO: Maybe make this the idle task
    arch.spinWait();

    //uart.simple_print("ZadOS is booting 1...\n");
    // Print welcome message
    //_ = uart.printf("ZadOS is booting {d}...\n", .{2}) catch {
    //    uart.simple_print("Failed to print welcome message\n");
    //};

    std.log.debug("Hello World\n", .{});

    // Main kernel loop
    while (true) {
        std.atomic.spinLoopHint();
        asm volatile ("wfe");
    }
}

///
/// Stage 2 initialisation. This will initialise main kernel features after the architecture
/// initialisation.
///
fn initStage2() noreturn {
    tty.clear();
    const logo =
        \\                  _____    _        _    _   _______    ____
        \\                 |  __ \  | |      | |  | | |__   __|  / __ \
        \\                 | |__) | | |      | |  | |    | |    | |  | |
        \\                 |  ___/  | |      | |  | |    | |    | |  | |
        \\                 | |      | |____  | |__| |    | |    | |__| |
        \\                 |_|      |______|  \____/     |_|     \____/
    ;
    tty.print("{s}\n\n", .{logo});

    tty.print("Hello Pluto from kernel :)\n", .{});

    //const devices = arch.getDevices(kernel_heap.allocator()) catch |e| {
    //    panic_root.panic(@errorReturnTrace(), "Unable to get device list: {}\n", .{e});
    //};

    //for (devices) |device| {
    //    device.print();
    //}

    switch (build_options.test_mode) {
        .Initialisation => {
            kmain_log.info("SUCCESS\n", .{});
        },
        else => {},
    }

    // Can't return for now, later this can return maybe
    arch.spinWait();
}
