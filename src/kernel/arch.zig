const std = @import("std");
const builtin = @import("builtin");
const is_test = builtin.is_test;
const build_options = @import("build_options");

pub const internals = if (is_test) @import("../../test/mock/kernel/arch_mock.zig") else switch (builtin.cpu.arch) {
    .aarch64 => @import("../arch/aarch64/arch.zig"),
    else => unreachable,
};
