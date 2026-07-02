const std = @import("std");
pub const apple_sdk = @import("./apple-sdk.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("mimalloc", .{});

    const MI_SECURE = b.option(bool, "mi_secure", "Use security mitigations (like meta data guard pages, allocation randomization, double-free mitigation, and free-list corruption detection)") orelse false;
    const MI_SECURE_FULL = b.option(bool, "mi_secure_full", "Use full security mitigations including guard pages at the end of each mimalloc page (may be expensive)") orelse false;
    const MI_PADDING = b.option(bool, "mi_padding", "Enable padding to detect heap block overflow (always on in DEBUG or SECURE mode, or with Valgrind/ASAN)") orelse false;
    const MI_OVERRIDE = b.option(bool, "mi_override", "Override the standard malloc interface (i.e. define entry points for 'malloc', 'free', etc)") orelse true;
    const MI_XMALLOC = b.option(bool, "mi_xmalloc", "Enable abort() call on memory allocation failure by default") orelse false;
    const MI_SHOW_ERRORS = b.option(bool, "mi_show_errors", "Show error and warning messages by default (only enabled by default in DEBUG mode)") orelse false;
    const MI_GUARDED = b.option(bool, "mi_guarded", "Build with guard pages behind certain object allocations (enabled by default in a debug build)") orelse false;
    const MI_USE_CXX = b.option(bool, "mi_use_cxx", "Use the C++ compiler to compile the library (instead of the C compiler)") orelse false;
    const MI_OSX_INTERPOSE = b.option(bool, "mi_osx_interpose", "Use  interpose to override standard malloc on macOS") orelse true;
    const MI_OSX_ZONE = b.option(bool, "mi_osx_zone", "Use malloc zone to override standard malloc on macOS") orelse true;
    const MI_WIN_REDIRECT = b.option(bool, "mi_win_redirect", "Use redirection module ('mimalloc-redirect') on Windows if compiling mimalloc as a DLL") orelse true;
    const MI_WIN_USE_FIXED_TLS = b.option(bool, "mi_win_use_fixed_tls", "Use a fixed TLS slot on Windows to avoid extra tests in the malloc fast path") orelse false;
    const MI_LOCAL_DYNAMIC_TLS = b.option(bool, "mi_local_dynamic_tls", "Use local-dynamic-tls, a slightly slower but dlopen-compatible thread local storage mechanism (Unix)") orelse false;

    const MI_DEBUG = b.option(bool, "mi_debug", "Enable assertion checks (enabled by default in a debug build)");
    const MI_DEBUG_INTERNAL = b.option(bool, "mi_debug_internal", "Enable assertion and internal invariant checks (enabled by default in a debug build)") orelse false;
    const MI_DEBUG_FULL = b.option(bool, "mi_debug_full", "Enable assertion checks and expensive internal heap invariant checking") orelse false;

    // options
    const VERBOSE = b.option(bool, "verbose", "Enable verbose output") orelse false;
    const EAGER_COMMIT = b.option(u8, "eager_commit", "Enable eager commit");
    const ARENA_EAGER_COMMIT = b.option(u8, "arena_eager_commit", "Enable arena eager commit");
    const ARENA_RESERVE = b.option([]const u8, "arena_reserve", "Enable arena reserve");
    const DISALLOW_ARENA_ALLOC = b.option(u8, "disallow_arena_alloc", "Disallow arena allocation");
    const ALLOW_LARGE_OS_PAGES = b.option(u8, "allow_large_os_pages", "Allow large OS pages support");
    const RESERVE_HUGE_OS_PAGES = b.option(u8, "reserve_huge_os_pages", "Reserve huge OS pages support");
    const RESERVE_OS_MEMORY = b.option(u8, "reserve_os_memory", "Reserve OS memory support");
    const GUARDED_SAMPLE_RATE = b.option(usize, "guarded_sample_rate", "Guarded sample rate support");
    const ALLOW_THP = b.option(u8, "allow_thp", "Allow Transparent Huge Pages (THP) support");

    var flags: std.ArrayList([]const u8) = .empty;
    var sources: std.ArrayList([]const u8) = .empty;

    try sources.append(b.allocator, "static.c");

    const MI_LIBC_MUSL = target.result.abi.isMusl();

    if (MI_LIBC_MUSL) try flags.append(b.allocator, "-DMI_LIBC_MUSL=1");

    if (MI_SECURE_FULL)
        try flags.append(b.allocator, "-DMI_SECURE=5")
    else if (MI_SECURE)
        try flags.append(b.allocator, "-DMI_SECURE=4");

    if (MI_PADDING) try flags.append(b.allocator, "-DMI_PADDING=1");
    if (MI_OVERRIDE) {
        if (target.result.os.tag.isDarwin()) {
            if (MI_OSX_ZONE) {
                try sources.append(b.allocator, "prim/osx/alloc-override-zone.c");
                try flags.append(b.allocator, "-DMI_OSX_ZONE=1");
                if (!MI_OSX_INTERPOSE)
                    std.debug.print("  WARNING: zone overriding usually also needs interpose (use -Dmi_osx_interpose)\n", .{});
            }
            if (MI_OSX_INTERPOSE) {
                try flags.append(b.allocator, "-DMI_OSX_INTERPOSE=1");
                if (!MI_OSX_ZONE)
                    std.debug.print("  WARNING: interpose usually also needs zone overriding (use -Dmi_osx_zone)\n", .{});
            }
        }
    }
    if (MI_XMALLOC) try flags.append(b.allocator, "-DMI_XMALLOC=1");
    if (MI_SHOW_ERRORS) try flags.append(b.allocator, "-DMI_SHOW_ERRORS=1");
    if (MI_GUARDED) try flags.append(b.allocator, "-DMI_GUARDED=1");
    if (MI_USE_CXX) try flags.append(b.allocator, "-DMI_USE_CXX=1");

    if (target.result.os.tag == .windows) {
        if (!MI_WIN_REDIRECT) try flags.append(b.allocator, "-DMI_WIN_NOREDIRECT=1");
    }

    if (MI_WIN_USE_FIXED_TLS) try flags.append(b.allocator, "-DMI_WIN_USE_FIXED_TLS=1");
    if (MI_LOCAL_DYNAMIC_TLS)
        try flags.append(b.allocator, "-ftls-model=local-dynamic")
    else if (MI_LIBC_MUSL) {
        try flags.append(b.allocator, "-ftls-model=local-dynamic");
    } else {
        try flags.append(b.allocator, "-ftls-model=initial-exec");
    }
    if (MI_OVERRIDE) try flags.append(b.allocator, "-fno-builtin-malloc");

    if (MI_DEBUG) |debug| {
        if (MI_DEBUG_FULL)
            try flags.append(b.allocator, "-DMI_DEBUG=3")
        else if (MI_DEBUG_INTERNAL)
            try flags.append(b.allocator, "-DMI_DEBUG=2")
        else if (debug)
            try flags.append(b.allocator, "-DMI_DEBUG=1")
        else
            try flags.append(b.allocator, "-DMI_DEBUG=0");
    } else {
        if (optimize == .Debug) {
            try flags.append(b.allocator, "-DMI_DEBUG=1");
        }
    }

    try flags.append(b.allocator, "-Wall");
    try flags.append(b.allocator, "-Wextra");
    try flags.append(b.allocator, "-Wno-date-time");
    try flags.append(b.allocator, "-Wno-unknown-pragmas");
    try flags.append(b.allocator, "-fvisibility=hidden");

    if (MI_USE_CXX) try flags.append(b.allocator, "-Wno-deprecated");

    if (VERBOSE) try flags.append(b.allocator, "-DMI_DEFAULT_VERBOSE=1");
    if (EAGER_COMMIT) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_EAGER_COMMIT={}", .{v}));
    if (ARENA_EAGER_COMMIT) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_ARENA_EAGER_COMMIT={}", .{v}));
    if (ARENA_RESERVE) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_ARENA_RESERVE={s}", .{v}));
    if (DISALLOW_ARENA_ALLOC) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_DISALLOW_ARENA_ALLOC={}", .{v}));
    if (ALLOW_LARGE_OS_PAGES) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_ALLOW_LARGE_OS_PAGES={}", .{v}));
    if (RESERVE_HUGE_OS_PAGES) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_RESERVE_HUGE_OS_PAGES={}", .{v}));
    if (RESERVE_OS_MEMORY) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_RESERVE_OS_MEMORY={}", .{v}));
    if (GUARDED_SAMPLE_RATE) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_GUARDED_SAMPLE_RATE={}", .{v}));
    if (ALLOW_THP) |v| try flags.append(b.allocator, b.fmt("-DMI_DEFAULT_ALLOW_THP={}", .{v}));

    const mimalloc = b.addTranslateC(.{
        .root_source_file = dep.path("include/mimalloc.h"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("mimalloc", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libcpp = if (MI_USE_CXX) true else null,
    });
    mod.addCSourceFiles(.{
        .root = dep.path("src"),
        .files = sources.items,
        .flags = flags.items,
    });
    mod.addIncludePath(dep.path("include"));

    mod.addImport("mimalloc", mimalloc.createModule());

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "mimalloc",
        .root_module = mod,
    });

    lib.installHeadersDirectory(dep.path("include"), ".", .{});

    b.installArtifact(lib);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    if (target.result.os.tag.isDarwin())
        try apple_sdk.addPaths(b, mod_tests);

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
