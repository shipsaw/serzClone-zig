const std = @import("std");
const parser = @import("binParser.zig");
const n = @import("node.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

const textNode = n.textNode;
const ff41NodeT = n.ff41NodeT;
const ff4eNodeT = n.ff4eNodeT;
const ff50NodeT = n.ff50NodeT;
const ff56NodeT = n.ff56NodeT;
const ff70NodeT = n.ff70NodeT;
const dataTypeMap = std.AutoHashMap(n.dataType, []const u8);

fn sort(nodes: []n.node) ![]textNode {
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    var textNodesList = std.ArrayList(textNode).init(allocator);
    for (nodes) |node| {
        try textNodesList.append(try convertNode(node, &dTypeMap));
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

fn convertNode(node: n.node, dTypeMap: *dataTypeMap) !textNode {
    return switch (node) {
        .ff41node => |ff41| textNode{ .ff41NodeT = ff41NodeT{
            .name = ff41.name,
            .dType = dTypeMap.get(ff41.dType).?,
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
    };
}

fn initDtypeMap(dTypeMap: *dataTypeMap) !void {
    try dTypeMap.put(n.dataType._bool, "bool");
    try dTypeMap.put(n.dataType._sUInt8, "sUInt8");
    try dTypeMap.put(n.dataType._sInt32, "sInt32");
    try dTypeMap.put(n.dataType._sUInt64, "sUInt64");
    try dTypeMap.put(n.dataType._sFloat32, "sFloat32");
    try dTypeMap.put(n.dataType._cDeltaString, "cDeltaString");
}

test "Convert ff41 node" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    var testValues = std.ArrayList(n.dataUnion).init(allocator);
    try testValues.append(n.dataUnion{ ._sInt32 = 1001 });
    try testValues.append(n.dataUnion{ ._sInt32 = 1003 });
    const testNode = n.ff41node{
        .name = "Node1",
        .numElements = 2,
        .dType = n.dataType._sInt32,
        .values = testValues,
    };

    var expectedValues = std.ArrayList(n.dataUnion).init(allocator);
    try expectedValues.append(n.dataUnion{ ._sInt32 = 1001 });
    try expectedValues.append(n.dataUnion{ ._sInt32 = 1003 });

    var expected = ff41NodeT{
        .name = "Node1",
        .numElements = 2,
        .dType = "sInt32",
        .values = expectedValues.items,
    };

    // Act
    var actual = (try convertNode(n.node{ .ff41node = testNode }, &dTypeMap)).ff41NodeT;

    // Assert
    try expectEqualStrings(actual.name, expected.name);
    try expect(actual.numElements == expected.numElements);
    try expectEqualStrings(actual.dType, expected.dType);
    try expect(actual.values[0]._sInt32 == expected.values[0]._sInt32);
    try expect(actual.values[1]._sInt32 == expected.values[1]._sInt32);
}

// test "Convert ff41 node" {
//     // Arrange
//     // Act
//     // Assert
// }
