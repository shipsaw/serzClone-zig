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

    std.debug.print("{s}\n", .{@tagName(t1val.x)});
}
