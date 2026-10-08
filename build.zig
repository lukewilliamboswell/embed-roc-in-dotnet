//! Build the platform's precompiled adapters for both supported Roc targets.
//! These are static link inputs, not the final plugin: roc build later links an
//! adapter with a particular application's compiled code into a shared library.

const std = @import("std");

/// Copy Linux and Windows adapter archives under platform/targets/.
pub fn build(b: *std.Build) void {
    // ReleaseSafe is the correctness-validation default for this demonstration.
    // A performance investigation should request ReleaseFast explicitly.
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Zig optimization mode (default ReleaseSafe)") orelse .ReleaseSafe;
    const install = b.getInstallStep();
    // Names correspond exactly to platform/main.roc's target entries. Windows
    // uses the MSVC ABI so the resulting app DLL fits the native Windows toolchain.
    const targets = .{
        .{ "x64musl", std.Target.Query{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl }, "libhost.a" },
        .{ "x64win", std.Target.Query{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc }, "host.lib" },
    };
    inline for (targets) |entry| {
        const lib = b.addLibrary(.{
            .name = "host",
            .linkage = .static,
            .root_module = b.createModule(.{
                .root_source_file = b.path("host-shim/host.zig"),
                .target = b.resolveTargetQuery(entry[1]),
                .optimize = optimize,
                // The archive's code becomes part of a dynamically loaded library.
                .pic = true,
            }),
        });
        // Keep Windows compiler support routines in the distributed link input.
        lib.bundle_compiler_rt = std.mem.eql(u8, entry[0], "x64win");
        // The normal archive contains its object bytes, even when member names
        // contain build-cache paths. Copy it directly into the platform inventory.
        const copy = b.addUpdateSourceFiles();
        copy.addCopyFileToSource(lib.getEmittedBin(), b.fmt("platform/targets/{s}/{s}", .{ entry[0], entry[2] }));
        install.dependOn(&copy.step);
    }
}
