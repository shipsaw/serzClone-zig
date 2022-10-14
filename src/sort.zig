const std = @import("std");
const parser = @import("binParser.zig");
const t = @import("node.zig");
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

const Place = struct {
    lat: f32,
    long: f32,
    hm: []const u8,
};

const textNode = struct {
    name: ?[]const u8,
    nType: []const u8,
    value: ?[]const u8,
};

pub fn main() !void {
    var file = try std.fs.cwd().openFile("testFiles/Scenario.bin", .{});

    const testBytes = try file.readToEndAlloc(allocator, size_limit);
    var testStatus = parser.status.init(testBytes);

    const nodes = (try parser.parse(&testStatus)).items;
    var textNodesList = std.ArrayList(textNode).init(allocator);

    for (nodes) |node| {
        try textNodesList.append(convertNode(node));
    }

    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(textNodesList.items, .{}, string.writer());
    std.debug.print("{s}", .{string.items});
}

fn convertNode(node: t.node) textNode {
    return switch (node) {
        .ff41node => textNode{ .name = node.ff41node.name },
        .ff4enode => textNode{ .name = null },
        .ff50node => textNode{ .name = node.ff50node.name },
        .ff56node => textNode{ .name = node.ff56node.name },
        .ff70node => textNode{ .name = node.ff70node.name },
    };
}
