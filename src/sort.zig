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

const textNode = union(enum) {
    ff41NodeT: ff41NodeT,
    ff4eNodeT: ff4eNodeT,
    ff50NodeT: ff50NodeT,
    ff56NodeT: ff56NodeT,
    ff70NodeT: ff70NodeT,
};

const ff41NodeT = struct {
    name: []const u8,
    numElements: u8,
    dType: []const u8,
    values: ?[]n.dataUnion,
};

const ff4eNodeT = struct {};

const ff50NodeT = struct {
    name: []const u8,
    id: ?u32,
    childrenSlice: ?[]textNode,
};

const ff56NodeT = struct {
    name: []const u8,
    dType: []const u8,
    value: n.dataUnion,
};

const ff70NodeT = struct {
    name: []const u8,
};

fn sort(nodes: []n.node) ![]textNode {
    var dataTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try dataTypeMap.put(n.dataType._bool, "bool");
    try dataTypeMap.put(n.dataType._sUInt8, "sUInt8");
    try dataTypeMap.put(n.dataType._sInt32, "sInt32");
    try dataTypeMap.put(n.dataType._sUInt64, "sUInt64");
    try dataTypeMap.put(n.dataType._sFloat32, "sFloat32");
    try dataTypeMap.put(n.dataType._cDeltaString, "cDeltaString");

    var textNodesList = std.ArrayList(textNode).init(allocator);
    for (nodes) |node| {
        try textNodesList.append(switch (node) {
            .ff41node => |ff41| textNode{ .ff41NodeT = ff41NodeT{
                .name = ff41.name,
                .dType = dataTypeMap.get(ff41.dType).?,
                .numElements = ff41.numElements,
                .values = ff41.values.items,
            } },
            .ff4enode => textNode{ .ff4eNodeT = ff4eNodeT{} },
            .ff50node => |ff50| textNode{ .ff50NodeT = ff50NodeT{
                .name = node.ff50node.name,
                .id = ff50.id,
                .childrenSlice = (try std.ArrayList(textNode).initCapacity(allocator, ff50.children)).items,
            } },
            .ff56node => textNode{ .ff56NodeT = ff56NodeT{
                .name = node.ff56node.name,
                .dType = "ff56",
                .value = n.dataUnion{ ._bool = true },
            } },
            .ff70node => textNode{ .ff70NodeT = ff70NodeT{ .name = node.ff70node.name } },
        });
    }
    return textNodesList.items;
}

pub fn main() !void {
    var file = try std.fs.cwd().openFile("testFiles/Scenario.bin", .{});

    const testBytes = try file.readToEndAlloc(allocator, size_limit);
    var testStatus = parser.status.init(testBytes);

    const nodes = (try parser.parse(&testStatus)).items;

    const textNodesList = try sort(nodes);

    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(textNodesList, .{}, string.writer());
    std.debug.print("{s}", .{string.items});
}

// fn convertNode(node: n.node) textNode {
//     return (switch (node) {
//         .ff41node => |ff41| textNode{ .ff41NodeT = ff41NodeT{
//             .name = ff41.name,
//             .dType = dataTypeMap.get(ff41.dType).?,
//             .numElements = ff41.numElements,
//             .values = ff41.values.items,
//         } },
//         .ff4enode => textNode{ .ff4eNodeT = ff4eNodeT{} },
//         .ff50node => |ff50| textNode{ .ff50NodeT = ff50NodeT{
//             .name = node.ff50node.name,
//             .id = ff50.id,
//             .childrenSlice = null,
//         } },
//         .ff56node => textNode{ .ff56NodeT = ff56NodeT{
//             .name = node.ff56node.name,
//             .dType = "ff56",
//             .value = n.dataUnion{ ._bool = true },
//         } },
//         .ff70node => textNode{ .ff70NodeT = ff70NodeT{ .name = node.ff70node.name } },
//     });
// }
