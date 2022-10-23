const std = @import("std");
const n = @import("node.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

const serz = &[_]u8{ 'S', 'E', 'R', 'Z' };
const unknown = &[_]u8{ 0x00, 0x00, 0x01, 0x00 };
const ff41 = &[_]u8{ 0xFF, 0x41 };
const ff4e = &[_]u8{ 0xFF, 0x4e };
const ff50 = &[_]u8{ 0xFF, 0x50 };
const ff56 = &[_]u8{ 0xFF, 0x56 };
const ff70 = &[_]u8{ 0xFF, 0x70 };
const newStr = &[_]u8{ 0xFF, 0xFF };

const strMapType = struct {
    map: std.StringHashMap(u16),
    currentPos: u16,
};

const lineMapType = struct {
    map: std.StringHashMap(u8),
    currentPos: u8,
};

const status = struct {
    current: usize,
    source: n.textNode,
    stringMap: strMapType,
    lineMap: lineMapType,
    parentStack: ?std.ArrayList(*n.textNode),
    result: std.ArrayList(u8),

    fn init(src: n.textNode) status {
        return status{
            .current = 0,
            .source = src,
            .stringMap = strMapType{ .map = std.StringHashMap(u16).init(allocator), .currentPos = 0 },
            .lineMap = lineMapType{ .map = std.StringHashMap(u8).init(allocator), .currentPos = 0 },
            .parentStack = null,
            .result = std.ArrayList(u8).init(allocator),
        };
    }

    fn checkStringMap(self: *status, str: []const u8) ![]const u8 {
        var resultArray = std.ArrayList(u8).init(allocator);
        const result: ?u16 = self.stringMap.map.get(str);
        if (result == null) {
            try self.stringMap.map.put(str, self.stringMap.currentPos);
            self.stringMap.currentPos += 1;

            const strLen: u32 = @truncate(u32, @bitCast(u64, str.len));
            try resultArray.appendSlice(&[_]u8{ 0xFF, 0xFF });
            try resultArray.appendSlice(&std.mem.toBytes(strLen));
            try resultArray.appendSlice(str);
            return resultArray.items;
        } else {
            try resultArray.appendSlice(&std.mem.toBytes(result.?));
            return resultArray.items;
        }
    }

    fn checkLineMap(self: *status, node: n.textNode) !?u8 {
        var nodeAsStr = std.ArrayList(u8).init(allocator);
        switch (node) {
            .ff41NodeT => |n| {
                try nodeAsStr.appendSlice(ff41);
                try nodeAsStr.appendSlice(n.name);
                try nodeAsStr.appendSlice(n.dType);
            },
            .ff50NodeT => |n| {
                try nodeAsStr.appendSlice(ff50);
                try nodeAsStr.appendSlice(n.name);
            },
            .ff56NodeT => |n| {
                try nodeAsStr.appendSlice(ff56);
                try nodeAsStr.appendSlice(n.name);
                try nodeAsStr.appendSlice(n.dType);
            },
            .ff70NodeT => |n| {
                try nodeAsStr.appendSlice(ff70);
                try nodeAsStr.appendSlice(n.name);
            },
            else => {},
        }

        const result: ?u8 = self.lineMap.map.get(nodeAsStr.items);
        if (result == null and self.lineMap.currentPos < 255) {
            try self.lineMap.map.put(nodeAsStr.items, self.lineMap.currentPos);
            self.lineMap.currentPos += 1;
            return null;
        }
        return result;
    }

    fn getCurrentParent(self: *status) *n.textNode {
        return self.parentStack.items[self.parentStack.len - 1];
    }
};

pub fn parse(inputString: []const u8) ![]const u8 {
    var stream = std.json.TokenStream.init(inputString);
    var rootNode = try std.json.parse(n.textNode, &stream, .{ .allocator = allocator });
    var parserStatus = status.init(rootNode);
    try addPrelude(&parserStatus);
    try walkNodes(&parserStatus, rootNode);
    return parserStatus.result.items;
}

fn addPrelude(s: *status) !void {
    try s.result.appendSlice(serz);
    try s.result.appendSlice(unknown);
}

fn walkNodes(s: *status, parentNode: n.textNode) !void {
    try s.result.appendSlice(try convertTnode(s, parentNode));
    for (parentNode.ff50NodeT.children) |child| {
        switch (child) {
            .ff50NodeT => try walkNodes(s, child),
            else => |node| try s.result.appendSlice(try convertTnode(s, node)),
        }
    }
    const closingNode = n.textNode{ .ff70NodeT = n.ff70NodeT{ .name = parentNode.ff50NodeT.name } };
    try s.result.appendSlice(try convertTnode(s, closingNode));
}

fn convertTnode(s: *status, node: n.textNode) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);

    const savedLine = try s.checkLineMap(node);
    if (savedLine != null) {
        try s.result.append(savedLine.?);
    }

    switch (node) {
        .ff56NodeT => |ff56node| {
            if (std.mem.eql(u8, ff56node.name, "LastPantographControlValue")) {
                std.debug.print("{any}\n", .{ff56node});
                std.os.exit(1);
            }
            try result.appendSlice(ff56);
            try result.appendSlice(try s.checkStringMap(ff56node.name));
            try result.appendSlice(try s.checkStringMap(ff56node.dType));
            try result.appendSlice(try convertDataUnion(s, ff56node.value, ff56node.dType));
        },
        .ff41NodeT => |ff41node| {
            try result.appendSlice(ff41);
            try result.appendSlice(try s.checkStringMap(ff41node.name));
            try result.appendSlice(try s.checkStringMap(ff41node.dType));
            try result.append(ff41node.numElements);
            for (ff41node.values) |val| {
                try result.appendSlice(try convertDataUnion(s, val, ff41node.dType));
            }
        },
        .ff4eNodeT => {
            try result.appendSlice(ff4e);
        },
        .ff50NodeT => |ff50node| {
            const numChildren = @truncate(u32, @bitCast(u64, ff50node.children.len));
            try result.appendSlice(ff50);
            try result.appendSlice(try s.checkStringMap(ff50node.name));
            try result.appendSlice(&std.mem.toBytes(ff50node.id));
            try result.appendSlice(&std.mem.toBytes(numChildren));
        },
        .ff70NodeT => |ff70node| {
            try result.appendSlice(ff70);
            try result.appendSlice(try s.checkStringMap(ff70node.name));
        },
    }
    return result.items;
}

fn convertDataUnion(s: *status, data: n.dataUnion, expectedDtype: []const u8) ![]const u8 {
    var returnSlice = std.ArrayList(u8).init(allocator);
    switch (data) {
        ._bool => |bVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(bVal));
        },
        ._sUInt8 => |u8Val| {
            try returnSlice.appendSlice(&std.mem.toBytes(u8Val));
        },
        ._sInt32 => |iVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(iVal));
        },
        ._sFloat32 => |fVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(fVal));
            std.os.exit(1);
        },
        ._sUInt64 => |u64Val| {
            try returnSlice.appendSlice(&std.mem.toBytes(u64Val));
        },
        ._cDeltaString => |sVal| {
            try returnSlice.appendSlice(try s.checkStringMap(sVal));
        },
    }
    return returnSlice.items;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////  Test Area ////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

test "stringMap functionality" {
    // Arrange
    const inputString1 = "Jupiter";
    const inputString2 = "Saturn";
    const inputString3 = "Jupiter";
    const inputString4 = "Saturn";

    const dummyNode = n.textNode{ .ff56NodeT = n.ff56NodeT{ .name = "name", .dType = "bool", .value = n.dataUnion{ ._bool = true } } };
    var s = status.init(dummyNode);

    // Act
    const result1 = try s.checkStringMap(inputString1);
    const result2 = try s.checkStringMap(inputString2);
    const result3 = try s.checkStringMap(inputString3);
    const result4 = try s.checkStringMap(inputString4);

    // Assert
    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x07, 0x00, 0x00, 0x00, 'J', 'u', 'p', 'i', 't', 'e', 'r' }, result1);
    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x06, 0x00, 0x00, 0x00, 'S', 'a', 't', 'u', 'r', 'n' }, result2);
    try expectEqualSlices(u8, &[_]u8{ 0x00, 0x00 }, result3);
    try expectEqualSlices(u8, &[_]u8{ 0x01, 0x00 }, result4);
}

test "convertDataUnion test" {
    // Arrange
    const dummyNode = n.textNode{ .ff56NodeT = n.ff56NodeT{ .name = "name", .dType = "bool", .value = n.dataUnion{ ._bool = true } } };
    var s = status.init(dummyNode);

    const boolUnionT = n.dataUnion{ ._bool = true };
    const boolUnionF = n.dataUnion{ ._bool = false };
    const sUInt8Union = n.dataUnion{ ._sUInt8 = 129 };
    const sInt32Union = n.dataUnion{ ._sInt32 = 3002 };
    const sFloat32Union = n.dataUnion{ ._sFloat32 = 0.12345 };
    const sUInt64Union = n.dataUnion{ ._sUInt64 = 123_456 };
    const cDeltaStringUnion = n.dataUnion{ ._cDeltaString = "Hello World" };

    // Act
    const boolTResult = try convertDataUnion(&s, boolUnionT);
    const boolFResult = try convertDataUnion(&s, boolUnionF);
    const sUint8Result = try convertDataUnion(&s, sUInt8Union);
    const sInt32Result = try convertDataUnion(&s, sInt32Union);
    const sFloat32Result = try convertDataUnion(&s, sFloat32Union);
    const sUInt64Result = try convertDataUnion(&s, sUInt64Union);
    const cDeltaStringResult = try convertDataUnion(&s, cDeltaStringUnion);

    // Assert
    try expectEqualSlices(u8, &[_]u8{0x01}, boolTResult);
    try expectEqualSlices(u8, &[_]u8{0x00}, boolFResult);
    try expectEqualSlices(u8, &[_]u8{0x81}, sUint8Result);
    try expectEqualSlices(u8, &[_]u8{ 0xBA, 0x0B, 0x00, 0x00 }, sInt32Result);
    try expectEqualSlices(u8, &[_]u8{ 0x5B, 0xD3, 0xFC, 0x3D }, sFloat32Result);
    try expectEqualSlices(u8, &[_]u8{ 0x40, 0xE2, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00 }, sUInt64Result);
    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x0B, 0x00, 0x00, 0x00, 'H', 'e', 'l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd' }, cDeltaStringResult);
}

test "ff56 to bin, no compress" {
    // Arrange
    const testNode = n.textNode{ .ff56NodeT = n.ff56NodeT{ .name = "Node1", .dType = "sInt32", .value = n.dataUnion{ ._sInt32 = 1003 } } };
    const expected = &[_]u8{ 0xFF, 0x56, 0xFF, 0xFF, 0x05, 0x00, 0x00, 0x00, 'N', 'o', 'd', 'e', '1', 0xFF, 0xFF, 0x06, 0x00, 0x00, 0x00, 's', 'I', 'n', 't', '3', '2', 0xEB, 0x03, 0x00, 0x00 };
    var s = status.init(testNode);

    // Act
    const result = try convertTnode(&s, testNode);

    // Assert
    try expectEqualSlices(u8, expected, result);
}

test "ff41 to bin, no compress" {
    // Arrange
    var valuesArray = [4]n.dataUnion{ n.dataUnion{ ._sUInt8 = 1 }, n.dataUnion{ ._sUInt8 = 2 }, n.dataUnion{ ._sUInt8 = 3 }, n.dataUnion{ ._sUInt8 = 4 } };
    const testNode = n.textNode{ .ff41NodeT = n.ff41NodeT{ .name = "Node2", .dType = "sUInt8", .numElements = 4, .values = &valuesArray } };
    const expected = &[_]u8{ 0xFF, 0x41, 0xFF, 0xFF, 0x05, 0x00, 0x00, 0x00, 'N', 'o', 'd', 'e', '2', 0xFF, 0xFF, 0x06, 0x00, 0x00, 0x00, 's', 'U', 'I', 'n', 't', '8', 0x04, 0x01, 0x02, 0x03, 0x04 };
    var s = status.init(testNode);

    // Act
    const result = try convertTnode(&s, testNode);

    // Assert
    try expectEqualSlices(u8, expected, result);
}

test "ff4e to bin, no compress" {
    // Arrange
    const testNode = n.textNode{ .ff4eNodeT = n.ff4eNodeT{} };
    const expected = &[_]u8{ 0xFF, 0x4E };
    var s = status.init(testNode);

    // Act
    const result = try convertTnode(&s, testNode);

    // Assert
    try expectEqualSlices(u8, expected, result);
}

test "ff50 to bin, no compress" {
    // Arrange
    var testChildren = [_]n.textNode{
        n.textNode{ .ff4eNodeT = n.ff4eNodeT{} },
        n.textNode{ .ff4eNodeT = n.ff4eNodeT{} },
        n.textNode{ .ff4eNodeT = n.ff4eNodeT{} },
    };
    const testNode = n.textNode{ .ff50NodeT = n.ff50NodeT{ .name = "Node3", .id = 12345, .children = &testChildren } };
    const expected = &[_]u8{ 0xFF, 0x50, 0xFF, 0xFF, 0x05, 0x00, 0x00, 0x00, 'N', 'o', 'd', 'e', '3', 0x39, 0x30, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00 };
    var s = status.init(testNode);

    // Act
    const result = try convertTnode(&s, testNode);

    // Assert
    try expectEqualSlices(u8, expected, result);
}

test "line saving logic test" {
    // Arrange
    var node1 = n.textNode{ .ff56NodeT = n.ff56NodeT{ .name = "Node1", .dType = "bool", .value = n.dataUnion{ ._bool = true } } };
    var node2 = n.textNode{ .ff56NodeT = n.ff56NodeT{ .name = "Node2", .dType = "bool", .value = n.dataUnion{ ._bool = false } } };
    var s = status.init(node1);

    // Act
    const result1 = s.checkLineMap(node1);
    const result2 = s.checkLineMap(node2);
    const result3 = try s.checkLineMap(node1);
    const result4 = try s.checkLineMap(node2);

    // Assert
    try expectEqual(result1, null);
    try expectEqual(result2, null);
    try expectEqual(result3.?, 0);
    try expectEqual(result4.?, 1);
}
