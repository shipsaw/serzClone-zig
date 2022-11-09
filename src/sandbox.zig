const std = @import("std");

const t1 = struct {
    x: bool,
    y: bool,
};

const t2 = struct {
    xx: bool,
    yy: bool,
};

pub fn main() !void {
    const t1val = t1{ .x = true, .y = true };

    printFields(t1val, "x");
}

fn printFields(t: anytype, comptime str: []const u8) void {
    std.debug.print("{any}\n", .{@field(t, str)});
}
