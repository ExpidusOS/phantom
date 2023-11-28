const std = @import("std");
const Allocator = std.mem.Allocator;
const vizops = @import("vizops");
const math = @import("../../../math.zig");
const Scene = @import("../../base.zig");
const Node = @import("../../node.zig");
const Fb = @import("../../../painting/fb/base.zig");
const NodeFrameBuffer = @This();

pub const Options = struct {
    source: *Fb,
    scale: vizops.vector.Float32Vector2 = .{ .value = @splat(1.0) },
    offset: vizops.vector.UsizeVector2 = .{},
    blend: vizops.color.BlendMode = .normal,
    size: ?vizops.vector.Float32Vector2 = null,
};

const State = struct {
    source: *Fb,
    scale: vizops.vector.Float32Vector2,
    offset: vizops.vector.UsizeVector2,
    blend: vizops.color.BlendMode,
    size: ?vizops.vector.Float32Vector2 = null,

    pub fn init(alloc: Allocator, options: Options) Allocator.Error!*State {
        const self = try alloc.create(State);
        self.* = .{
            .source = options.source,
            .scale = options.scale,
            .offset = options.offset,
            .blend = options.blend,
            .size = options.size,
        };
        return self;
    }

    pub fn equal(self: *State, other: *State) bool {
        return std.simd.countTrues(@Vector(5, bool){
            self.scale.eq(other.scale),
            self.offset.eq(other.offset),
            self.blend == other.blend,
            if (self.size != null and other.size != null) self.size.?.eq(other.size.?) else false,
            @as(usize, @intFromPtr(self.source)) == @as(usize, @intFromPtr(other.source)) or (self.source.addr() catch null == other.source.addr() catch null),
        }) == 5;
    }

    pub fn deinit(self: *State, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

options: Options,
node: Node,

pub fn create(id: ?usize, args: std.StringHashMap(?*anyopaque)) !*Node {
    const source: *Fb = @ptrCast(@alignCast(args.get("source") orelse return error.MissingKey));
    return &(try new(args.allocator, id orelse @returnAddress(), .{
        .source = source,
        .scale = if (args.get("scale")) |v| @as(*vizops.vector.Float32Vector2, @ptrCast(@alignCast(v))).* else vizops.vector.Float32Vector2.init(1.0),
        .offset = if (args.get("offset")) |v| @as(*vizops.vector.UsizeVector2, @ptrCast(@alignCast(v))).* else vizops.vector.UsizeVector2.init(0),
        .blend = if (args.get("blend")) |v| @enumFromInt(@intFromPtr(v)) else .normal,
    })).node;
}

pub fn new(alloc: Allocator, id: ?usize, options: Options) Allocator.Error!*NodeFrameBuffer {
    const self = try alloc.create(NodeFrameBuffer);
    errdefer alloc.destroy(self);

    self.* = .{
        .options = options,
        .node = .{
            .allocator = alloc,
            .ptr = self,
            .type = @typeName(NodeFrameBuffer),
            .id = id orelse @returnAddress(),
            .vtable = &.{
                .dupe = dupe,
                .state = state,
                .preFrame = preFrame,
                .frame = frame,
                .deinit = deinit,
                .format = format,
                .setProperties = setProperties,
            },
        },
    };
    return self;
}

fn stateEqual(ctx: *anyopaque, otherctx: *anyopaque) bool {
    const self: *State = @ptrCast(@alignCast(ctx));
    const other: *State = @ptrCast(@alignCast(otherctx));
    return self.equal(other);
}

fn stateFree(ctx: *anyopaque, alloc: std.mem.Allocator) void {
    const self: *State = @ptrCast(@alignCast(ctx));
    self.deinit(alloc);
}

fn dupe(ctx: *anyopaque) anyerror!*Node {
    const self: *NodeFrameBuffer = @ptrCast(@alignCast(ctx));
    return &(try new(self.node.allocator, @returnAddress(), self.options)).node;
}

fn calcSize(self: NodeFrameBuffer, frameInfo: Node.FrameInfo) vizops.vector.UsizeVector2 {
    const base = if (self.options.size) |size| math.rel(frameInfo, size) else self.options.source.info().res;
    const scaled = base.cast(f32).mul(self.options.scale).cast(usize);
    return if (self.options.size == null) scaled.sub(self.options.offset) else scaled;
}

fn state(ctx: *anyopaque, frameInfo: Node.FrameInfo) anyerror!Node.State {
    const self: *NodeFrameBuffer = @ptrCast(@alignCast(ctx));
    return .{
        .size = self.calcSize(),
        .frame_info = frameInfo,
        .allocator = self.node.allocator,
        .ptr = try State.init(self.node.allocator, self.options),
        .ptrEqual = stateEqual,
        .ptrFree = stateFree,
        .type = @typeName(NodeFrameBuffer),
    };
}

fn preFrame(ctx: *anyopaque, frameInfo: Node.FrameInfo, _: *Scene) anyerror!Node.State {
    const self: *NodeFrameBuffer = @ptrCast(@alignCast(ctx));
    return .{
        .size = self.calcSize(),
        .frame_info = frameInfo,
        .allocator = self.node.allocator,
        .ptr = try State.init(self.node.allocator, self.options),
        .ptrEqual = stateEqual,
        .ptrFree = stateFree,
        .type = @typeName(NodeFrameBuffer),
    };
}

fn frame(ctx: *anyopaque, _: *Scene) anyerror!void {
    const self: *NodeFrameBuffer = @ptrCast(@alignCast(ctx));
    _ = self;
}

fn deinit(ctx: *anyopaque) void {
    const self: *NodeFrameBuffer = @ptrCast(@alignCast(ctx));
    self.options.source.deinit();
    self.node.allocator.destroy(self);
}

fn format(ctx: *anyopaque, _: ?Allocator) anyerror!std.ArrayList(u8) {
    const self: *NodeFrameBuffer = @ptrCast(@alignCast(ctx));

    var output = std.ArrayList(u8).init(self.node.allocator);
    errdefer output.deinit();

    try output.writer().print("{{ .scale = {}, .source = {} }}", .{ self.options.scale, self.options.source });
    return output;
}

fn setProperties(ctx: *anyopaque, args: std.StringHashMap(?*anyopaque)) anyerror!void {
    const self: *NodeFrameBuffer = @ptrCast(@alignCast(ctx));

    var iter = args.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        if (value == null) continue;

        if (std.mem.eql(u8, key, "scale")) {
            self.options.scale.value = @as(*vizops.vector.Float32Vector2, @ptrCast(@alignCast(value.?))).value;
        } else if (std.mem.eql(u8, key, "source")) {
            self.options.source.deinit();
            self.options.source = try @as(*Fb, @ptrCast(@alignCast(value.?))).dupe();
        } else return error.InvalidKey;
    }
}
