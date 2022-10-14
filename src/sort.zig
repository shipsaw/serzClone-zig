const std = @import("std");
const parser = @import("binParser.zig");
const n = @import("node.zig");
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

const Place = struct {
    lat: f32,
    long: f32,
    hm: []const u8,
};

const textNode = union {
    ff41Node: ff41NodeT,
    ff4eNode: ff4eNodeT,
    ff50Node: ff50NodeT,
    ff56Node: ff56NodeT,
    // ff70Node: ff70NodeT,
};

const ff41NodeT = struct {
    name: []const u8,
    numElements: u8,
    dType: []const u8,
    value: []n.dataUnion,
};

const ff4eNodeT = struct {};

const ff50NodeT = struct {
    name: []const u8,
    id: ?u32,
    children: []textNode,
};

const ff56NodeT = struct {
    name: []const u8,
    dType: []const u8,
    value: n.dataUnion,
};

// const ff70NodeT = struct {
//     name: []const u8,
// };

fn sort(nodes: []n.node) []textNode {
    var textNodesList = std.Arraylist(textNode).init(allocator);
    for (nodes) |node| {
        try textNodesList.append(convertNode(node));
    }
    return textNodesList.items;
}

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

fn convertNode(node: n.node) textNode {
    return switch (node) {
        .ff41node => textNode{ .name = node.ff41node.name, .nType = "ff41", .value = null },
        .ff4enode => textNode{ .name = null, .nType = "ff4e", .value = null },
        .ff50node => textNode{ .name = node.ff50node.name, .nType = "ff50", .value = n.dataUnion{ ._bool = true } },
        .ff56node => textNode{ .name = node.ff56node.name, .nType = "ff56", .value = null },
        .ff70node => textNode{ .name = node.ff70node.name, .nType = "ff70", .value = null },
    };
}
