const std = @import("std");

pub const DtbHeader = packed struct {
    magic: u32,           // 0xd00dfeed
    totalsize: u32,       // total size of DTB in bytes
    off_dt_struct: u32,   // offset to structure block
    off_dt_strings: u32,  // offset to strings block
    off_mem_rsvmap: u32,  // offset to memory reserve map
    version: u32,         // DTB format version
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,

    pub fn isValid(self: *const DtbHeader) bool {
        return self.magic == 0xd00dfeed;
    }
};

pub fn readDtbHeader(addr: usize) *const DtbHeader {
    return @as(*const DtbHeader, @ptrCast(@alignCast(@as(*const u8, @ptrFromInt(addr)))));
}
