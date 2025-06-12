const std = @import("std");
const rt = @import("test/runtime_test.zig");
const TestMode = rt.TestMode;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    // Set up for ARM64 bare metal target
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .aarch64,
            .os_tag = .freestanding,
            .abi = .none,
            .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.cortex_a72 },
        },
    });

    // For bare metal, we want to optimize for size initially
    const optimize = b.standardOptimizeOption(.{
        //.preferred_optimize_mode = .ReleaseSmall,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "ZadOS",
        .root_module = exe_mod,
    });

    const test_mode = b.option(TestMode, "test-mode", "Run a specific runtime test. This option is for the rt-test step. Available options: ") orelse .None;

    const exe_options = b.addOptions();
    exe_options.addOption(TestMode, "test_mode", test_mode);
    exe_mod.addOptions("build_options", exe_options);

    // Add assembly file
    exe.addAssemblyFile(b.path("src/arch/aarch64/start.S"));

    // Set linker script
    exe.setLinkerScript(b.path("src/arch/aarch64/linker.ld"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Common QEMU settings
    const QemuArgs = struct {
        pub const normal: []const []const u8 = &[_][]const u8{
            "qemu-system-aarch64",
            "-machine",
            "virt",
            "-cpu",
            "cortex-a72",
            "-nographic",
            "-kernel",
        };
        pub const debug: []const []const u8 = &[_][]const u8{
            "-S", // Start CPU halted
            "-gdb", "tcp::1234", // Listen for GDB connection on port 1234
        };
    };

    // Create normal QEMU run step
    var qemu_cmd = std.ArrayList([]const u8).init(b.allocator);
    defer qemu_cmd.deinit();
    qemu_cmd.appendSlice(QemuArgs.normal) catch unreachable;
    qemu_cmd.append(b.getInstallPath(.bin, "ZadOS")) catch unreachable;

    const qemu = b.addSystemCommand(qemu_cmd.items);
    qemu.step.dependOn(b.getInstallStep());

    // Create debug QEMU run step
    var qemu_debug_cmd = std.ArrayList([]const u8).init(b.allocator);
    defer qemu_debug_cmd.deinit();
    qemu_debug_cmd.appendSlice(QemuArgs.normal) catch unreachable;
    qemu_debug_cmd.append(b.getInstallPath(.bin, "ZadOS")) catch unreachable;
    qemu_debug_cmd.appendSlice(QemuArgs.debug) catch unreachable;

    const qemu_debug = b.addSystemCommand(qemu_debug_cmd.items);
    std.log.info("QEMU debug command: {s}", .{qemu_debug_cmd.items});
    qemu_debug.step.dependOn(b.getInstallStep());

    // Add QEMU run steps
    const qemu_step = b.step("qemu", "Run the kernel in QEMU");
    qemu_step.dependOn(&qemu.step);

    const debug_step = b.step("debug", "Run the kernel in QEMU with GDB server");
    debug_step.dependOn(&qemu_debug.step);

    // Add debugging symbols and disable optimization for debug builds
    exe.want_lto = false;

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&qemu.step); // Make run step use QEMU

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
