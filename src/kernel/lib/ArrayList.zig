const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;
const mem = std.mem;
const testing = std.testing;
const log = std.log.scoped(.kArrayList);

extern var KERNEL_TMP_STACK_START: *u64;
extern var KERNEL_TMP_STACK_END: *u64;

/// A dynamically-sized array list implementation suitable for kernel use.
/// The list owns the memory it allocates.
pub fn ArrayList(comptime T: type) type {
    return struct {
        /// Items stored in the list
        items: []T,
        /// Number of items currently in the list
        len: usize,
        /// The allocator used for managing memory
        allocator: Allocator,

        const Self = @This();

        /// Error set for ArrayList operations
        pub const Error = error{
            OutOfMemory,
            CapacityOverflow,
        };

        /// Initialize a new ArrayList with the given allocator
        pub fn init(allocator: Allocator) Self {
            return .{
                .items = allocator.alloc(T, 1) catch {
                    @panic("ArrayList: Out of memory during initialization");
                }, //@as([*]align(@alignOf(T)) T, @ptrCast(&KERNEL_TMP_STACK_START))[0..10],
                .len = 0,
                .allocator = allocator,
            };
        }

        /// Initialize with capacity
        pub fn initCapacity(allocator: Allocator, _capacity: usize) Error!Self {
            log.debug("Initialising ArrayList with capacity: {}\n", .{_capacity});
            var self = Self.init(allocator);
            log.debug("Initialised ArrayList -> ensuring capacity: {}\n", .{_capacity});
            try self.ensureTotalCapacity(_capacity);
            return self;
        }

        /// Free all allocated memory
        pub fn deinit(self: *Self) void {
            if (self.items.len == 0) return;
            self.allocator.free(self.items);
            self.items = &[_]T{}; //@as([*]align(@alignOf(T)) T, @ptrFromInt(0))[0..0];
            self.len = 0;
        }

        /// Current capacity of the list
        pub fn capacity(self: Self) usize {
            return self.items.len;
        }

        /// Ensure total capacity in the list
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Error!void {
            if (new_capacity <= self.capacity()) return;

            // Calculate new capacity using exponential growth
            var better_capacity = self.capacity();
            while (true) {
                better_capacity +|= better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }

            return self.ensureTotalCapacityPrecise(better_capacity);
        }

        /// Ensure exact capacity
        pub fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) Error!void {
            if (new_capacity <= self.capacity()) return;

            const new_items = try self.allocator.alloc(T, new_capacity);
            @memcpy(new_items[0..self.len], self.items[0..self.len]);

            if (self.items.len != 0) {
                self.allocator.free(self.items);
            }

            self.items = new_items;
        }

        /// Append a single item
        pub fn append(self: *Self, item: T) Error!void {
            try self.ensureTotalCapacity(self.len + 1);
            self.appendAssumeCapacity(item);
        }

        /// Append assuming we have capacity
        pub fn appendAssumeCapacity(self: *Self, item: T) void {
            self.items[self.len] = item;
            self.len += 1;
        }

        /// Append a slice of items
        pub fn appendSlice(self: *Self, items: []const T) Error!void {
            try self.ensureTotalCapacity(self.len + items.len);
            self.appendSliceAssumeCapacity(items);
        }

        /// Append slice assuming we have capacity
        pub fn appendSliceAssumeCapacity(self: *Self, items: []const T) void {
            @memcpy(self.items[self.len..][0..items.len], items);
            self.len += items.len;
        }

        /// Remove and return the last element
        pub fn pop(self: *Self) T {
            self.len -= 1;
            return self.items[self.len];
        }

        /// Remove and return the last element, or null if empty
        pub fn popOrNull(self: *Self) ?T {
            if (self.len == 0) return null;
            return self.pop();
        }

        /// Remove N elements from the end
        pub fn resize(self: *Self, new_len: usize) void {
            if (new_len > self.len) {
                @panic("ArrayList: cannot resize to larger length");
            }
            self.len = new_len;
        }

        /// Remove the element at the given index and shift elements after it
        pub fn orderedRemove(self: *Self, i: usize) T {
            const newlen = self.len - 1;
            if (newlen == i) return self.pop();
            const old_item = self.items[i];
            for (self.items[i..newlen], 0..) |*b, j| {
                b.* = self.items[i + 1 + j];
            }
            self.len = newlen;
            return old_item;
        }

        /// Swap remove - fast removal by swapping with last element
        pub fn swapRemove(self: *Self, i: usize) T {
            if (i >= self.len) @panic("ArrayList: index out of bounds");
            const old_item = self.items[i];
            self.items[i] = self.items[self.len - 1];
            self.len -= 1;
            return old_item;
        }

        /// Insert item at index, shifting elements after it
        pub fn insert(self: *Self, i: usize, item: T) Error!void {
            if (i > self.len) @panic("ArrayList: index out of bounds");
            try self.ensureTotalCapacity(self.len + 1);
            self.len += 1;

            // Shift items to the right
            var j: usize = self.len - 1;
            while (j > i) : (j -= 1) {
                self.items[j] = self.items[j - 1];
            }
            // Insert new item
            self.items[i] = item;
        }

        /// Return slice of all items
        pub fn toSlice(self: Self) []T {
            return self.items[0..self.len];
        }

        /// Return const slice of all items
        pub fn toSliceConst(self: Self) []const T {
            return self.items[0..self.len];
        }

        /// Clear the list (keeping allocated memory)
        pub fn clearRetainingCapacity(self: *Self) void {
            self.len = 0;
        }

        /// Clear the list and free memory
        pub fn clearAndFree(self: *Self) void {
            if (self.items.len == 0) return;
            self.allocator.free(self.items);
            self.items = &[_]T{};
            self.len = 0;
        }
    };
}

test "ArrayList: basic functionality" {
    var list = ArrayList(i32).init(testing.allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try testing.expectEqual(@as(usize, 3), list.len);
    try testing.expectEqual(@as(i32, 1), list.items[0]);
    try testing.expectEqual(@as(i32, 2), list.items[1]);
    try testing.expectEqual(@as(i32, 3), list.items[2]);
}

test "ArrayList: remove operations" {
    var list = ArrayList(i32).init(testing.allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);
    try list.append(4);

    const removed = list.orderedRemove(1);
    try testing.expectEqual(@as(i32, 2), removed);
    try testing.expectEqual(@as(usize, 3), list.len);
    try testing.expectEqual(@as(i32, 1), list.items[0]);
    try testing.expectEqual(@as(i32, 3), list.items[1]);
    try testing.expectEqual(@as(i32, 4), list.items[2]);
}

test "ArrayList: capacity growth" {
    var list = ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    try testing.expectEqual(@as(usize, 0), list.capacity());
    try list.append(1);
    try testing.expect(list.capacity() >= 1);

    const initial_cap = list.capacity();
    try list.appendSlice(&[_]u8{ 2, 3, 4, 5, 6, 7, 8, 9, 10 });
    try testing.expect(list.capacity() > initial_cap);
}
