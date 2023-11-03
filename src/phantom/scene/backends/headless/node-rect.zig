const std = @import("std");
const Allocator = std.mem.Allocator;
const vizops = @import("vizops");
const math = @import("../../../math.zig");
const Scene = @import("../../base.zig");
const Node = @import("../../node.zig");
const NodeRect = @This();

const RadiusSide = struct {
    left: ?f32,
    right: ?f32,

    pub fn equal(self: RadiusSide, other: RadiusSide) bool {
        return std.simd.countTrues(@Vector(2, bool){
            self.left == other.left,
            self.right == other.right,
        }) == 2;
    }
};

const Radius = struct {
    top: ?RadiusSide,
    bottom: ?RadiusSide,

    pub fn equal(self: Radius, other: Radius) bool {
        return std.simd.countTrues(@Vector(2, bool){
            if (self.top == null and other.top != null) false else if (self.top != null and other.top == null) false else self.top.?.equal(other.top.?),
            if (self.bottom == null and other.bottom != null) false else if (self.bottom != null and other.bottom == null) false else self.bottom.?.equal(other.bottom.?),
        }) == 2;
    }
};

pub const Options = struct {
    radius: ?Radius,
    size: vizops.vector.Float32Vector2,
    color: vizops.vector.Float32Vector4,
};

const State = struct {
    radius: ?Radius,
    color: vizops.vector.Float32Vector4,

    pub fn init(alloc: Allocator, options: Options) Allocator.Error!*State {
        const self = try alloc.create(State);
        self.* = .{
            .radius = options.radius,
            .color = options.color,
        };
        return self;
    }

    pub fn equal(self: *State, other: *State) bool {
        return std.simd.countTrues(@Vector(2, bool){
            if (self.radius == null and other.radius != null) false else if (self.radius != null and other.radius == null) false else self.radius.?.equal(other.radius.?),
            std.simd.countTrues(self.color.value == other.color.value) == 4,
        }) == 2;
    }

    pub fn deinit(self: *State, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

allocator: Allocator,
options: Options,
node: Node,

pub fn create(id: ?usize, args: std.StringHashMap(?*anyopaque)) !*Node {
    const size: *vizops.vector.Float32Vector2 = @ptrCast(@alignCast(args.get("size") orelse return error.MissingKey));
    const color: *vizops.vector.Float32Vector4 = @ptrCast(@alignCast(args.get("color") orelse return error.MissingKey));
    return &(try new(args.allocator, id orelse @returnAddress(), .{
        .size = vizops.vector.Float32Vector2.init(size.value),
        .color = vizops.vector.Float32Vector4.init(color.value),
        .radius = .{
            .top = .{
                .left = if (args.get("topLeft")) |v| @floatCast(@as(f64, @bitCast(@intFromPtr(v)))) else 0,
                .right = if (args.get("topRight")) |v| @floatCast(@as(f64, @bitCast(@intFromPtr(v)))) else 0,
            },
            .bottom = .{
                .left = if (args.get("bottomLeft")) |v| @floatCast(@as(f64, @bitCast(@intFromPtr(v)))) else 0,
                .right = if (args.get("bottomRight")) |v| @floatCast(@as(f64, @bitCast(@intFromPtr(v)))) else 0,
            },
        },
    })).node;
}

pub fn new(alloc: Allocator, id: ?usize, options: Options) Allocator.Error!*NodeRect {
    const self = try alloc.create(NodeRect);
    errdefer alloc.destroy(self);

    self.* = .{
        .allocator = alloc,
        .options = options,
        .node = .{
            .ptr = self,
            .type = @typeName(NodeRect),
            .id = id orelse @returnAddress(),
            .vtable = &.{
                .dupe = dupe,
                .state = state,
                .preFrame = preFrame,
                .frame = frame,
                .deinit = deinit,
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
    const self: *NodeRect = @ptrCast(@alignCast(ctx));
    return &(try new(self.allocator, @returnAddress(), self.options)).node;
}

fn state(ctx: *anyopaque, frameInfo: Node.FrameInfo) anyerror!Node.State {
    const self: *NodeRect = @ptrCast(@alignCast(ctx));
    return .{
        .size = math.rel(frameInfo, self.options.size),
        .frame_info = frameInfo,
        .allocator = self.allocator,
        .ptr = try State.init(self.allocator, self.options),
        .ptrEqual = stateEqual,
        .ptrFree = stateFree,
    };
}

fn preFrame(ctx: *anyopaque, frameInfo: Node.FrameInfo, _: *Scene) anyerror!Node.State {
    const self: *NodeRect = @ptrCast(@alignCast(ctx));
    return .{
        .size = math.rel(frameInfo, self.options.size),
        .frame_info = frameInfo,
        .allocator = self.allocator,
        .ptr = try State.init(self.allocator, self.options),
        .ptrEqual = stateEqual,
        .ptrFree = stateFree,
    };
}

fn frame(ctx: *anyopaque, _: *Scene) anyerror!void {
    const self: *NodeRect = @ptrCast(@alignCast(ctx));
    _ = self;
}

fn deinit(ctx: *anyopaque) void {
    const self: *NodeRect = @ptrCast(@alignCast(ctx));
    self.allocator.destroy(self);
}
