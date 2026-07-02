const std = @import("std");
const mimalloc = @import("mimalloc");

const Alignment = std.mem.Alignment;

const assert = std.debug.assert;

pub const vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

fn alloc(
    _: *anyopaque,
    len: usize,
    alignment: Alignment,
    _: usize,
) ?[*]u8 {
    const ptr = mimalloc.mi_malloc_aligned(len, alignment.toByteUnits()) orelse return null;
    assert(alignment.check(@intFromPtr(ptr)));
    return @ptrCast(ptr);
}

fn resize(
    _: *anyopaque,
    memory: []u8,
    _: Alignment,
    new_len: usize,
    _: usize,
) bool {
    return mimalloc.mi_expand(
        memory.ptr,
        new_len,
    ) != null;
}

fn remap(
    _: *anyopaque,
    memory: []u8,
    alignment: Alignment,
    new_len: usize,
    _: usize,
) ?[*]u8 {
    return @ptrCast(mimalloc.mi_realloc_aligned(
        memory.ptr,
        new_len,
        alignment.toByteUnits(),
    ) orelse return null);
}

fn free(
    _: *anyopaque,
    memory: []u8,
    alignment: Alignment,
    _: usize,
) void {
    mimalloc.mi_free_aligned(
        memory.ptr,
        alignment.toByteUnits(),
    );
}
