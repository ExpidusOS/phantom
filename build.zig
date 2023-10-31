const std = @import("std");
const metap = @import("metaplus").@"meta+";

pub const BackendType = metap.enums.fromDecls(struct {
    const shouldImport = blk: {
        for (@import("root").dependencies.root_deps) |dep| {
            if (std.mem.eql(u8, dep[0], "phantom")) break :blk true;
        }
        break :blk false;
    };

    const root = if (shouldImport) @import("root.@build") else struct {};

    pub usingnamespace @import("src/phantom/scene/backends.zig");
    pub usingnamespace if (@hasDecl(root, "phantom")) if (@hasDecl(root.phantom, "backends")) root.phantom.backends else struct {} else struct {};
});

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_docs = b.option(bool, "no-docs", "skip installing documentation") orelse false;
    const backend = b.option(BackendType, "backend", "The backend to use for the example") orelse .headless;

    const vizops = b.dependency("vizops", .{
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("vizops", .{
        .source_file = .{
            .path = vizops.builder.pathFromRoot(vizops.module("vizops").source_file.path),
        },
    });

    const metaplus = b.dependency("metaplus", .{
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("meta+", .{
        .source_file = .{
            .path = metaplus.builder.pathFromRoot(metaplus.module("meta+").source_file.path),
        },
    });

    const phantom = b.addModule("phantom", .{
        .source_file = .{ .path = b.pathFromRoot("src/phantom.zig") },
        .dependencies = &.{
            .{
                .name = "vizops",
                .module = vizops.module("vizops"),
            },
            .{
                .name = "meta+",
                .module = metaplus.module("meta+"),
            },
        },
    });

    const step_test = b.step("test", "Run all unit tests");

    const unit_tests = b.addTest(.{
        .root_source_file = .{
            .path = b.pathFromRoot("src/phantom.zig"),
        },
        .target = target,
        .optimize = optimize,
    });

    unit_tests.addModule("vizops", vizops.module("vizops"));
    unit_tests.addModule("meta+", metaplus.module("meta+"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    step_test.dependOn(&run_unit_tests.step);

    const exe_options = b.addOptions();
    exe_options.addOption(BackendType, "backend", backend);

    const exe_example = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{
            .path = b.pathFromRoot("src/example.zig"),
        },
        .target = target,
        .optimize = optimize,
    });

    exe_example.addModule("phantom", phantom);
    exe_example.addModule("vizops", vizops.module("vizops"));
    exe_example.addOptions("options", exe_options);
    b.installArtifact(exe_example);

    if (!no_docs) {
        const docs = b.addInstallDirectory(.{
            .source_dir = unit_tests.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });

        b.getInstallStep().dependOn(&docs.step);
    }
}
