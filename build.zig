const std = @import("std");
const rt = @import("test/runtime_test.zig");
const TestMode = rt.TestMode;

const SupportedArchitectures = enum {
    AArch64,
    RiscV64,
    X86_64,
};

const SupportedBoards = enum {
    Qemu_Virt,
    RaspberryPi4,
    RaspberryPi400,
    Pine64,
    OdroidN2,
    OdroidN2Plus,
    OdroidC4,
    RockPro64,
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Get architecture and board from build options, default to AArch64/Qemu_Virt
    const arch = b.option(SupportedArchitectures, "arch", "Target architecture (AArch64, RiscV64, X86_64)") orelse .AArch64;
    const board = b.option(SupportedBoards, "board", "Target board") orelse .Qemu_Virt;

    // Select CPU and board-specific settings
    var cpu_model: *const std.Target.Cpu.Model = &std.Target.aarch64.cpu.cortex_a72;
    var cpu_name: []const u8 = "generic";
    var qemu_machine: []const u8 = "virt";
    var qemu_cpu: []const u8 = "cortex-a72";
    var qemu_mem: []const u8 = "256";
    // Set CPU model and QEMU parameters based on architecture and board

    var disabled_features = std.Target.Cpu.Feature.Set.empty;

    switch (arch) {
        .AArch64 => {
            const features = std.Target.aarch64.Feature;
            disabled_features = std.Target.aarch64.featureSet(&.{
                features.fp_armv8, // Disable floating point support
                features.neon, // Disable NEON support
                features.crypto, // Disable crypto extensions
                features.fullfp16,
            });
            switch (board) {
                .Qemu_Virt => {
                    cpu_model = &std.Target.aarch64.cpu.cortex_a72;
                    cpu_name = "cortex-a72";
                    //Ref: https://docs.u-boot.org/en/latest/develop/devicetree/dt_qemu.html#obtaining-the-qemu-devicetree
                    qemu_machine = "virt";
                    qemu_cpu = "cortex-a72";
                    qemu_mem = "1G";
                },
                .RaspberryPi4 => {
                    cpu_model = &std.Target.aarch64.cpu.cortex_a72;
                    cpu_name = "cortex-a72";
                    qemu_machine = "raspi4b";
                    qemu_cpu = "cortex-a72";
                    qemu_mem = "1024";
                },
                .RaspberryPi400 => {
                    cpu_model = &std.Target.aarch64.cpu.cortex_a72;
                    cpu_name = "cortex-a72";
                    qemu_machine = "raspi4b";
                    qemu_cpu = "cortex-a72";
                    qemu_mem = "1024";
                },
                .Pine64 => {
                    cpu_model = &std.Target.aarch64.cpu.cortex_a53;
                    cpu_name = "cortex-a53";
                    qemu_machine = "virt";
                    qemu_cpu = "cortex-a53";
                    qemu_mem = "1024";
                },
                .RockPro64 => {
                    cpu_model = &std.Target.aarch64.cpu.cortex_a53;
                    cpu_name = "cortex-a53";
                    qemu_machine = "virt";
                    qemu_cpu = "cortex-a53";
                    qemu_mem = "1024";
                },
                .OdroidN2 => {
                    cpu_model = &std.Target.aarch64.cpu.cortex_a73;
                    cpu_name = "cortex-a73";
                    qemu_machine = "virt";
                    qemu_cpu = "cortex-a73";
                    qemu_mem = "4096";
                },
                .OdroidN2Plus => {
                    cpu_model = &std.Target.aarch64.cpu.cortex_a73;
                    cpu_name = "cortex-a73";
                    qemu_machine = "virt";
                    qemu_cpu = "cortex-a73";
                    qemu_mem = "4096";
                },
                .OdroidC4 => {
                    cpu_model = &std.Target.aarch64.cpu.cortex_a73;
                    cpu_name = "cortex-a73";
                    qemu_machine = "virt";
                    qemu_cpu = "cortex-a73";
                    qemu_mem = "4096";
                },
            }
        },
        .RiscV64 => {
            cpu_name = "generic-rv64";
            qemu_machine = "virt";
            qemu_cpu = "rv64";
            qemu_mem = "256";
        },
        .X86_64 => {
            cpu_name = "x86_64";
            qemu_machine = "pc";
            qemu_cpu = "qemu64";
            qemu_mem = "256";
        },
    }

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = switch (arch) {
                .AArch64 => .aarch64,
                .RiscV64 => .riscv64,
                .X86_64 => .x86_64,
            },
            .os_tag = .freestanding,
            .abi = .none,
            .cpu_model = .{ .explicit = cpu_model },
            .cpu_features_sub = disabled_features,
        },
    });

    // For bare metal, we want to optimize for size initially
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
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
    exe_options.addOption(SupportedArchitectures, "target_arch", arch);
    exe_options.addOption(SupportedBoards, "target_board", board);
    exe_mod.addOptions("build_options", exe_options);

    // Add assembly file
    exe.addAssemblyFile(b.path("src/arch/aarch64/start.S"));

    // Set linker script
    exe.setLinkerScript(b.path("src/arch/aarch64/linker.ld"));

    exe.stack_size = 0x1000_000; // 1 MiB stack size

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

    // QEMU command line is now board/arch dependent
    // Remove QemuArgs struct (if present)

    // Create normal QEMU run step
    const qemu_bin = std.fmt.allocPrint(b.allocator, "qemu-system-{s}", .{switch (arch) {
        .AArch64 => "aarch64",
        .RiscV64 => "riscv64",
        .X86_64 => "x86_64",
    }}) catch unreachable;
    defer b.allocator.free(qemu_bin);

    var qemu_cmd = std.ArrayList([]const u8).init(b.allocator);
    defer qemu_cmd.deinit();
    qemu_cmd.append(qemu_bin) catch unreachable;
    qemu_cmd.append("-machine") catch unreachable;
    qemu_cmd.append(qemu_machine) catch unreachable;
    qemu_cmd.append("-cpu") catch unreachable;
    qemu_cmd.append(qemu_cpu) catch unreachable;
    qemu_cmd.append("-smp") catch unreachable;
    qemu_cmd.append("4") catch unreachable;
    qemu_cmd.append("-m") catch unreachable;
    qemu_cmd.append(qemu_mem) catch unreachable;
    qemu_cmd.append("-nographic") catch unreachable;
    qemu_cmd.append("-kernel") catch unreachable;
    qemu_cmd.append(b.getInstallPath(.bin, "ZadOS")) catch unreachable;
    //const loader_arg = std.fmt.allocPrint(b.allocator, "loader,addr=0x40200000,cpu-num=0,file={s}", .{b.getInstallPath(.bin, "ZadOS")}) catch unreachable;
    //defer b.allocator.free(loader_arg);
    //qemu_cmd.append("-device") catch unreachable;
    //qemu_cmd.append(loader_arg) catch unreachable;

    const qemu = b.addSystemCommand(qemu_cmd.items);
    qemu.step.dependOn(b.getInstallStep());

    // Create debug QEMU run step
    var qemu_debug_cmd = std.ArrayList([]const u8).init(b.allocator);
    defer qemu_debug_cmd.deinit();
    for (qemu_cmd.items) |arg| {
        qemu_debug_cmd.append(arg) catch unreachable;
    }
    //qemu_debug_cmd.append("-s") catch unreachable;
    qemu_debug_cmd.append("-S") catch unreachable;
    qemu_debug_cmd.append("-gdb") catch unreachable;
    qemu_debug_cmd.append("tcp::1234") catch unreachable;

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
