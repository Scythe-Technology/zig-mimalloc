const std = @import("std");
pub const c = @import("mimalloc");

const Basic = @import("basic.zig");

const Allocator = std.mem.Allocator;

pub const basic_allocator = Allocator{
    .ptr = undefined,
    .vtable = &Basic.vtable,
};

test "basic allocator" {
    const allocator = basic_allocator;

    {
        const mem = try allocator.alloc(u8, 1024);
        defer allocator.free(mem);

        try std.testing.expect(mem.len == 1024);
    }
    {
        const mem = try allocator.alloc(u8, 13);
        defer allocator.free(mem);

        @memcpy(mem[0..13], "Hello, world!");

        try std.testing.expect(mem.len == 13);
        try std.testing.expectEqualStrings(mem, "Hello, world!");
    }
    {
        const value = try allocator.create(u64);
        defer allocator.destroy(value);

        value.* = 0;

        try std.testing.expect(value.* == 0);

        value.* = 1;

        try std.testing.expect(value.* == 1);

        value.* = std.math.maxInt(u64);
        try std.testing.expect(value.* == std.math.maxInt(u64));
    }
    // issue: https://github.com/microsoft/mimalloc/issues/1304
    // {
    //     const mem = try allocator.alloc(u8, 1024);
    //     defer allocator.free(mem);

    //     @memcpy(mem[0..13], "Hello, world!");

    //     try std.testing.expect(mem.len == 1024);

    //     const new_mem = allocator.remap(mem, 2048) orelse return error.OutOfMemory;
    //     defer allocator.free(new_mem);

    //     try std.testing.expect(new_mem.len == 2048);
    // }
}
