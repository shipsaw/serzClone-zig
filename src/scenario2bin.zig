const std = @import("std");
const n = @import("node.zig");
const sm = @import("scenarioModel.zig");
const json = @import("custom_json.zig");
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
const ff52 = &[_]u8{ 0xFF, 0x52 };
const ff56 = &[_]u8{ 0xFF, 0x56 };
const ff70 = &[_]u8{ 0xFF, 0x70 };
const newStr = &[_]u8{ 0xFF, 0xFF };

const stringContext = enum {
    NAME,
    DTYPE,
    VALUE,
};

const strMapType = struct {
    map: std.StringHashMap(u16),
    currentPos: u16,
};

const lineMapType = struct {
    map: std.StringHashMap(u8),
    posMap: std.AutoHashMap(u8, []const u8),
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
            .lineMap = lineMapType{
                .map = std.StringHashMap(u8).init(allocator),
                .posMap = std.AutoHashMap(u8, []const u8).init(allocator),
                .currentPos = 0,
            },
            .parentStack = null,
            .result = std.ArrayList(u8).init(allocator),
        };
    }

    fn checkStringMap(self: *status, str: []const u8, ctx: stringContext) ![]const u8 {
        const correctedStr = if (str.len > 0 and str[0] == '_' and ctx == stringContext.VALUE) str[1..] else str;
        var resultArray = std.ArrayList(u8).init(allocator);
        const result: ?u16 = self.stringMap.map.get(correctedStr);
        if (result == null) {
            try self.stringMap.map.put(correctedStr, self.stringMap.currentPos);
            self.stringMap.currentPos += 1;

            const strLen: u32 = @truncate(u32, @bitCast(u64, correctedStr.len));
            try resultArray.appendSlice(&[_]u8{ 0xFF, 0xFF });
            try resultArray.appendSlice(&std.mem.toBytes(strLen));
            try resultArray.appendSlice(correctedStr);
            return resultArray.items;
        } else {
            try resultArray.appendSlice(&std.mem.toBytes(result.?));
            return resultArray.items;
        }
    }

    fn checkLineMap(self: *status, node: n.textNode) !?u8 {
        var nodeAsStr = std.ArrayList(u8).init(allocator);
        switch (node) {
            .ff41NodeT => |nde| {
                try nodeAsStr.appendSlice(ff41);
                try nodeAsStr.appendSlice(nde.name);
                try nodeAsStr.appendSlice(nde.dType);
            },
            .ff50NodeT => |nde| {
                try nodeAsStr.appendSlice(ff50);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff52NodeT => |nde| {
                try nodeAsStr.appendSlice(ff52);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff56NodeT => |nde| {
                try nodeAsStr.appendSlice(ff56);
                try nodeAsStr.appendSlice(nde.name);
                try nodeAsStr.appendSlice(nde.dType);
            },
            .ff70NodeT => |nde| {
                try nodeAsStr.appendSlice(ff70);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff4eNodeT => {
                try nodeAsStr.appendSlice(ff4e);
            },
        }

        const result: ?u8 = self.lineMap.map.get(nodeAsStr.items);
        if (result == null) {
            // Remove the existing entry in the "buffer"
            const lineToRemove = self.lineMap.posMap.get(self.lineMap.currentPos);
            if (lineToRemove != null) {
                _ = self.lineMap.map.remove(lineToRemove.?);
            }

            // Add the new line to the buffer
            try self.lineMap.map.put(nodeAsStr.items, self.lineMap.currentPos);
            try self.lineMap.posMap.put(self.lineMap.currentPos, nodeAsStr.items);
            self.lineMap.currentPos = (self.lineMap.currentPos + 1) % 255;
            return null;
        }
        return result;
    }

    fn getCurrentParent(self: *status) *n.textNode {
        return self.parentStack.items[self.parentStack.len - 1];
    }
};

pub fn parse(inputString: []const u8) ![]const u8 {
    var stream = json.TokenStream.init(inputString);
    var rootNode = try json.parse(sm.cRecordSet, &stream, .{ .allocator = allocator });
    // var parserStatus = status.init(rootNode);
    // try addPrelude(&parserStatus);
    // try walkNodes(&parserStatus, rootNode);
    // return parserStatus.result.items;
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
    var isSavedLine = false;

    const savedLine = try s.checkLineMap(node);
    if (savedLine != null) {
        try s.result.append(savedLine.?);
        isSavedLine = true;
    }

    switch (node) {
        .ff56NodeT => |ff56node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff56);
                try result.appendSlice(try s.checkStringMap(ff56node.name, stringContext.NAME));
                try result.appendSlice(try s.checkStringMap(ff56node.dType, stringContext.VALUE));
            }
            try result.appendSlice(try convertDataUnion(s, ff56node.value, ff56node.dType));
        },
        .ff52NodeT => |ff52node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff52);
                try result.appendSlice(try s.checkStringMap(ff52node.name, stringContext.NAME));
            }
            try result.appendSlice(&std.mem.toBytes(ff52node.value));
        },
        .ff41NodeT => |ff41node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff41);
                try result.appendSlice(try s.checkStringMap(ff41node.name, stringContext.NAME));
                try result.appendSlice(try s.checkStringMap(ff41node.dType, stringContext.DTYPE));
            }
            try result.append(ff41node.numElements);
            for (ff41node.values) |val| {
                try result.appendSlice(try convertDataUnion(s, val, ff41node.dType));
            }
        },
        .ff4eNodeT => {
            if (isSavedLine == false) {
                try result.appendSlice(ff4e);
            }
        },
        .ff50NodeT => |ff50node| {
            const numChildren = @truncate(u32, @bitCast(u64, ff50node.children.len));
            if (isSavedLine == false) {
                try result.appendSlice(ff50);
                try result.appendSlice(try s.checkStringMap(ff50node.name, stringContext.NAME));
            }
            try result.appendSlice(&std.mem.toBytes(ff50node.id));
            try result.appendSlice(&std.mem.toBytes(numChildren));
        },
        .ff70NodeT => |ff70node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff70);
                try result.appendSlice(try s.checkStringMap(ff70node.name, stringContext.NAME));
            }
        },
    }
    return result.items;
}

fn convertDataUnion(s: *status, data: n.dataUnion, expectedType: []const u8) ![]const u8 {
    var returnSlice = std.ArrayList(u8).init(allocator);
    const correctedType = try correctType(data, expectedType);
    switch (correctedType) {
        ._bool => |bVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(bVal));
        },
        ._sUInt8 => |u8Val| {
            try returnSlice.appendSlice(&std.mem.toBytes(u8Val));
        },
        ._sInt16 => |i16Val| {
            try returnSlice.appendSlice(&std.mem.toBytes(i16Val));
        },
        ._sInt32 => |iVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(iVal));
        },
        ._sUInt32 => |uVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(uVal));
        },
        ._sFloat32 => |fVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(fVal));
        },
        ._sUInt64 => |u64Val| {
            try returnSlice.appendSlice(&std.mem.toBytes(u64Val));
        },
        ._cDeltaString => |sVal| {
            if (std.mem.eql(u8, expectedType, "sFloat32")) { // If "Negative zero" case
                try returnSlice.appendSlice(&[_]u8{ 0x00, 0x00, 0x00, 0x80 });
            } else {
                try returnSlice.appendSlice(try s.checkStringMap(sVal, stringContext.VALUE));
            }
        },
    }
    return returnSlice.items;
}

fn correctType(data: n.dataUnion, expectedType: []const u8) !n.dataUnion {
    const expected = n.dataTypeMap.get(expectedType).?;
    const actual = switch (data) {
        ._bool => n.dataType._bool,
        ._sUInt8 => n.dataType._sUInt8,
        ._sInt16 => n.dataType._sInt16,
        ._sInt32 => n.dataType._sInt32,
        ._sUInt32 => n.dataType._sUInt32,
        ._sFloat32 => n.dataType._sFloat32,
        ._sUInt64 => n.dataType._sUInt64,
        ._cDeltaString => n.dataType._cDeltaString,
    };

    if (expected == actual) return data;

    return switch (data) {
        ._sUInt8 => try fixSuint8(data, expected),
        ._sInt16 => try fixSint16(data, expected),
        ._sInt32 => try fixSint32(data, expected),
        ._sUInt32 => try fixSuint32(data, expected),
        ._sUInt64 => try fixSuint64(data, expected),
        ._cDeltaString => data,
        else => unreachable,
    };
}

fn fixSuint8(data: n.dataUnion, expectedType: n.dataType) !n.dataUnion {
    const boxedData = data._sUInt8;
    return switch (expectedType) {
        n.dataType._sInt32 => n.dataUnion{ ._sInt32 = @intCast(i32, boxedData) },
        n.dataType._sInt16 => n.dataUnion{ ._sInt16 = @intCast(i16, boxedData) },
        n.dataType._sUInt32 => n.dataUnion{ ._sUInt32 = @intCast(u32, boxedData) },
        n.dataType._sUInt64 => n.dataUnion{ ._sUInt64 = @intCast(u64, boxedData) },
        n.dataType._sFloat32 => n.dataUnion{ ._sFloat32 = @intToFloat(f32, boxedData) },
        n.dataType._cDeltaString => {
            return n.dataUnion{ ._cDeltaString = try std.fmt.allocPrint(allocator, "{any}", .{boxedData}) };
        },
        else => unreachable,
    };
}

// TODO: test
fn fixSint16(data: n.dataUnion, expectedType: n.dataType) !n.dataUnion {
    const boxedData = data._sInt16;
    return switch (expectedType) {
        n.dataType._sInt32 => n.dataUnion{ ._sInt32 = @intCast(i32, boxedData) },
        n.dataType._sUInt32 => n.dataUnion{ ._sUInt32 = @intCast(u32, boxedData) },
        n.dataType._sUInt64 => n.dataUnion{ ._sUInt64 = @intCast(u64, boxedData) },
        n.dataType._sFloat32 => n.dataUnion{ ._sFloat32 = @intToFloat(f32, boxedData) },
        n.dataType._cDeltaString => {
            return n.dataUnion{ ._cDeltaString = try std.fmt.allocPrint(allocator, "{any}", .{boxedData}) };
        },
        else => unreachable,
    };
}

fn fixSint32(data: n.dataUnion, expectedType: n.dataType) !n.dataUnion {
    const boxedData = data._sInt32;
    return switch (expectedType) {
        n.dataType._sInt32 => n.dataUnion{ ._sInt32 = @intCast(i32, boxedData) },
        n.dataType._sUInt32 => n.dataUnion{ ._sUInt32 = @intCast(u32, boxedData) },
        n.dataType._sUInt64 => n.dataUnion{ ._sUInt64 = @intCast(u64, boxedData) },
        n.dataType._sFloat32 => n.dataUnion{ ._sFloat32 = @intToFloat(f32, boxedData) },
        n.dataType._cDeltaString => {
            return n.dataUnion{ ._cDeltaString = try std.fmt.allocPrint(allocator, "{any}", .{boxedData}) };
        },
        else => unreachable,
    };
}

// TODO: test
fn fixSuint32(data: n.dataUnion, expectedType: n.dataType) !n.dataUnion {
    const boxedData = data._sUInt32;
    return switch (expectedType) {
        n.dataType._sInt32 => n.dataUnion{ ._sInt32 = @intCast(i32, boxedData) },
        n.dataType._sUInt32 => n.dataUnion{ ._sUInt32 = @intCast(u32, boxedData) },
        n.dataType._sUInt64 => n.dataUnion{ ._sUInt64 = @intCast(u64, boxedData) },
        n.dataType._sFloat32 => n.dataUnion{ ._sFloat32 = @intToFloat(f32, boxedData) },
        n.dataType._cDeltaString => {
            return n.dataUnion{ ._cDeltaString = try std.fmt.allocPrint(allocator, "{any}", .{boxedData}) };
        },
        else => unreachable,
    };
}

fn fixSuint64(data: n.dataUnion, expectedType: n.dataType) !n.dataUnion {
    const boxedData = data._sUInt64;
    return switch (expectedType) {
        n.dataType._cDeltaString => {
            return n.dataUnion{ ._cDeltaString = try std.fmt.allocPrint(allocator, "{any}", .{boxedData}) };
        },
        else => unreachable,
    };
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
    const result1 = try s.checkStringMap(inputString1, stringContext.NAME);
    const result2 = try s.checkStringMap(inputString2, stringContext.NAME);
    const result3 = try s.checkStringMap(inputString3, stringContext.NAME);
    const result4 = try s.checkStringMap(inputString4, stringContext.NAME);

    // Assert
    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x07, 0x00, 0x00, 0x00, 'J', 'u', 'p', 'i', 't', 'e', 'r' }, result1);
    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x06, 0x00, 0x00, 0x00, 'S', 'a', 't', 'u', 'r', 'n' }, result2);
    try expectEqualSlices(u8, &[_]u8{ 0x00, 0x00 }, result3);
    try expectEqualSlices(u8, &[_]u8{ 0x01, 0x00 }, result4);
}

test "stringMap underScore functionality" {
    // Arrange
    const inputString1 = "_0123";
    const inputString2 = "Saturn";
    const inputString3 = "Jupiter";

    const dummyNode = n.textNode{ .ff56NodeT = n.ff56NodeT{ .name = "name", .dType = "bool", .value = n.dataUnion{ ._bool = true } } };
    var s = status.init(dummyNode);

    // Act
    const result1 = try s.checkStringMap(inputString1, stringContext.VALUE);
    const result2 = try s.checkStringMap(inputString1, stringContext.NAME);
    const result3 = try s.checkStringMap(inputString2, stringContext.NAME);
    const result4 = try s.checkStringMap(inputString3, stringContext.VALUE);

    // Assert
    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x04, 0x00, 0x00, 0x00, '0', '1', '2', '3' }, result1);
    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x05, 0x00, 0x00, 0x00, '_', '0', '1', '2', '3' }, result2);

    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x06, 0x00, 0x00, 0x00, 'S', 'a', 't', 'u', 'r', 'n' }, result3);
    try expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0x07, 0x00, 0x00, 0x00, 'J', 'u', 'p', 'i', 't', 'e', 'r' }, result4);
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
    const boolTResult = try convertDataUnion(&s, boolUnionT, "bool");
    const boolFResult = try convertDataUnion(&s, boolUnionF, "bool");
    const sUint8Result = try convertDataUnion(&s, sUInt8Union, "sUInt8");
    const sInt32Result = try convertDataUnion(&s, sInt32Union, "sInt32");
    const sFloat32Result = try convertDataUnion(&s, sFloat32Union, "sFloat32");
    const sUInt64Result = try convertDataUnion(&s, sUInt64Union, "sUInt64");
    const cDeltaStringResult = try convertDataUnion(&s, cDeltaStringUnion, "cDeltaString");

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

test "ff56 to bin, no compress, negative float" {
    // Arrange
    const testNode = n.textNode{ .ff56NodeT = n.ff56NodeT{ .name = "Node1", .dType = "sFloat32", .value = n.dataUnion{ ._cDeltaString = "(-0)" } } };
    const expected = &[_]u8{ 0xFF, 0x56, 0xFF, 0xFF, 0x05, 0x00, 0x00, 0x00, 'N', 'o', 'd', 'e', '1', 0xFF, 0xFF, 0x08, 0x00, 0x00, 0x00, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0x00, 0x00, 0x00, 0x80 };
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
    var node3 = n.textNode{ .ff4eNodeT = n.ff4eNodeT{} };
    var s = status.init(node1);

    // Act
    const result1 = s.checkLineMap(node1);
    const result2 = s.checkLineMap(node2);
    const result3 = try s.checkLineMap(node1);
    const result4 = try s.checkLineMap(node2);
    const result5 = s.checkLineMap(node3);
    const result6 = try s.checkLineMap(node3);

    // Assert
    try expectEqual(result1, null);
    try expectEqual(result2, null);
    try expectEqual(result3.?, 0);
    try expectEqual(result4.?, 1);
    try expectEqual(result5, null);
    try expectEqual(result6.?, 2);
}










fn make_ff50nodeT(name: []const u8, id: u32, children: u32) n.textNode {
    return n.textNode{ .ff50nodeT = n.ff50nodeT{ .name = name, .id = id, .children = children } };
}

fn make_ff56nodeT(name: []const u8, dType: []const u8, value: n.dataUnion) n.textNode {
    return n.textNode{ .ff56nodeT = n.ff56nodeT{ .name = name, .dType = dType, .value = value } };
}

fn make_ff70nodeT(name: []const u8) n.textNode {
    return n.textNode{ .ff70NodeT = n.ff70NodeT{ .name = name } };
}

fn parseNode(s: *status) n.dataUnion {
    defer s.current += 1;
    return s.nodeList[s.current].ff56node.value;
    return n.node{ .ff56node = n.ff56node { .
}

fn parse_sTimeOfDay(s: *status, nde: sm.sTimeOfDay) void {
    const sTimeOfDayNode = make_ff50nodeT("sTimeOfDay", 0, 3);
    const iHourNode = make_ff56nodeT("_iHour", "sInt32", n.dataUnion{ .sInt32 = nde.iHour });
    const iMinuteNode = make_ff56nodeT("_iMinute", "sInt32", n.dataUnion{ .sInt32 = nde.iMinute });
    const iSecondsNode = make_ff56nodeT("_iSeconds", "sInt32", n.dataUnion{ .sInt32 = nde.iSeconds });
    const closeNode = make_ff70nodeT("sTimeOfDay);

    s.result.append(convertTnode(s, sTimeOfDayNode));
    s.result.append(convertTnode(s, iHourNode));
    s.result.append(convertTnode(s, iMinuteNode));
    s.result.append(convertTnode(s, iSecondsNode));
    s.result.append(convertTnode(s, closeNode));
}

fn parse_parseLocalisation_cUserLocalisedString(s: *status, nde: sm.Localisation_cUserLocalisedString) void {
    const localizationNode = make_ff50nodeT("Localisation_cUserLocalisedString", 0, 10);
    const englishNode = make_ff56nodeT("English", "cDeltaString", n.dataUnion{ .cDeltaString = nde.english });
    const frenchNode = make_ff56nodeT("French", "cDeltaString", n.dataUnion{ .cDeltaString = nde.french });
    const italianNode = make_ff56nodeT("Italian", "cDeltaString", n.dataUnion{ .cDeltaString = nde.italian });
    const germanNode = make_ff56nodeT("German", "cDeltaString", n.dataUnion{ .cDeltaString = nde.german });
    const spanishNode = make_ff56nodeT("Spanish", "cDeltaString", n.dataUnion{ .cDeltaString = nde.spanish });
    const dutchNode = make_ff56nodeT("Dutch", "cDeltaString", n.dataUnion{ .cDeltaString = nde.dutch });
    const polishNode = make_ff56nodeT("Polish", "cDeltaString", n.dataUnion{ .cDeltaString = nde.polish });
    const russianNode = make_ff56nodeT("Russian", "cDeltaString", n.dataUnion{ .cDeltaString = nde.russian });

    const english = parseNode(s)._cDeltaString;
    const french = parseNode(s)._cDeltaString;
    const italian = parseNode(s)._cDeltaString;
    const german = parseNode(s)._cDeltaString;
    const spanish = parseNode(s)._cDeltaString;
    const dutch = parseNode(s)._cDeltaString;
    const polish = parseNode(s)._cDeltaString;
    const russian = parseNode(s)._cDeltaString;

    var otherList = std.ArrayList(sm.Localization_otherLanguage).init(allocator);
    const otherListLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < otherListLen) : (i += 1) {
        const tempNode = sm.Localization_otherLanguage{
            .LangName = s.nodeList[s.current + i].ff56node.name,
            .Value = s.nodeList[s.current + i].ff56node.value._cDeltaString,
        };
        try otherList.append(tempNode);
    }
    s.current += otherListLen + 1;
    const key = parseNode(s)._cDeltaString;

    return sm.Localisation_cUserLocalisedString{
        .English = english,
        .French = french,
        .Italian = italian,
        .German = german,
        .Spanish = spanish,
        .Dutch = dutch,
        .Polish = polish,
        .Russian = russian,
        .Other = otherList.items,
        .Key = key,
    };
}

fn parse_cGUID(s: *status) sm.cGUID {
    std.debug.print("\nBEGIN cGUID\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    // TODO: Add UUID Area
    s.current += 3;
    defer s.current += 2;

    var uuid: [2]u64 = undefined;
    uuid[0] = parseNode(s)._sUInt64;
    uuid[1] = parseNode(s)._sUInt64;
    s.current += 1;

    const devString = parseNode(s)._cDeltaString;

    return sm.cGUID{
        .UUID = uuid,
        .DevString = devString,
    };
}

fn parse_DriverInstruction(s: *status) ![]sm.DriverInstruction {
    std.debug.print("\nBEGIN DriverInstruction\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const numberInstructions = s.nodeList[s.current].ff50node.children;
    s.current += 1;
    defer s.current += 1;

    var i: u32 = 0;
    var instructionArray = std.ArrayList(sm.DriverInstruction).init(allocator);

    while (i < numberInstructions) : (i += 1) {
        const currentName = s.nodeList[s.current].ff50node.name;
        if (std.mem.eql(u8, "cTriggerInstruction", currentName)) {
            const boxedInstruction = sm.DriverInstruction{ .cTriggerInstruction = (try parse_cTriggerInstruction(s)) };
            try instructionArray.append(boxedInstruction);
        } else if (std.mem.eql(u8, "cPickUpPassengers", currentName)) {
            const boxedInstruction = sm.DriverInstruction{ .cPickupPassengers = (try parse_cPickupPassengers(s)) };
            try instructionArray.append(boxedInstruction);
        } else if (std.mem.eql(u8, "cStopAtDestinations", currentName)) {
            const boxedInstruction = sm.DriverInstruction{ .cStopAtDestination = (try parse_cStopAtDestination(s)) };
            try instructionArray.append(boxedInstruction);
        } else if (std.mem.eql(u8, "cConsistOperations", currentName)) {
            const boxedInstruction = sm.DriverInstruction{ .cConsistOperation = (try parse_cConsistOperation(s)) };
            try instructionArray.append(boxedInstruction);
        } else undefined;
    }
    return instructionArray.items;
}

fn parse_cDriverInstructionTarget(s: *status) !?sm.cDriverInstructionTarget {
    std.debug.print("\nBEGIN cDriverInstructionTarget\n", .{});
    s.current += 1;
    defer s.current += 1;
    switch (s.nodeList[s.current]) {
        .ff4enode => {
            s.current += 1;
            return null;
        },
        .ff70node => {
            return null;
        },
        .ff50node => {
            std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
            const idVal = s.nodeList[s.current + 0].ff50node.id;
            s.current += 1;
            defer s.current += 1;

            const displayName = parseNode(s)._cDeltaString;
            const timeTabled = parseNode(s)._bool;
            const performance = parseNode(s)._sInt32;
            const minSpeed = parseNode(s)._sInt32;
            const durationSecs = parseNode(s)._sFloat32;
            const entityName = parseNode(s)._cDeltaString;
            const trainOrder = parseNode(s)._bool;
            const operation = parseNode(s)._cDeltaString;
            const deadline = parse_sTimeOfDay(s);
            const pickingUp = parseNode(s)._bool;
            const duration = parseNode(s)._sUInt32;
            const handleOffPath = parseNode(s)._bool;
            const earliestDepartureTime = parseNode(s)._sFloat32;
            const durationSet = parseNode(s)._bool;
            const reversingAllowed = parseNode(s)._bool;
            const waypoint = parseNode(s)._bool;
            const hidden = parseNode(s)._bool;
            const progressCode = parseNode(s)._cDeltaString;
            const arrivalTime = parseNode(s)._sFloat32;
            const departureTime = parseNode(s)._sFloat32;
            const tickedTime = parseNode(s)._sFloat32;
            const dueTime = parseNode(s)._sFloat32;

            var railVehicleNumbersList = std.ArrayList([]const u8).init(allocator);
            const railVehicleNumbersListLen = s.nodeList[s.current].ff50node.children;
            s.current += 1;
            var i: u32 = 0;
            while (i < railVehicleNumbersListLen) : (i += 1) {
                try railVehicleNumbersList.append(s.nodeList[s.current].ff56node.value._cDeltaString);
            }
            s.current += (1 + railVehicleNumbersListLen);

            const timingTestTime = parseNode(s)._sFloat32;

            const groupName = try parse_parseLocalisation_cUserLocalisedString(s);

            const showRVNumbersWithGroup = parseNode(s)._bool;
            const scenarioChainTarget = parseNode(s)._bool;
            const scenarioChainGUID = parse_cGUID(s);

            return sm.cDriverInstructionTarget{
                .id = idVal,
                .DisplayName = displayName,
                .Timetabled = timeTabled,
                .Performance = performance,
                .MinSpeed = minSpeed,
                .DurationSecs = durationSecs,
                .EntityName = entityName,
                .TrainOrder = trainOrder,
                .Operation = operation,
                .Deadline = deadline,
                .PickingUp = pickingUp,
                .Duration = duration,
                .HandleOffPath = handleOffPath,
                .EarliestDepartureTime = earliestDepartureTime,
                .DurationSet = durationSet,
                .ReversingAllowed = reversingAllowed,
                .Waypoint = waypoint,
                .Hidden = hidden,
                .ProgressCode = progressCode,
                .ArrivalTime = arrivalTime,
                .DepartureTime = departureTime,
                .TickedTime = tickedTime,
                .DueTime = dueTime,
                .RailVehicleNumber = railVehicleNumbersList.items,
                .TimingTestTime = timingTestTime,
                .GroupName = groupName,
                .ShowRVNumbersWithGroup = showRVNumbersWithGroup,
                .ScenarioChainTarget = scenarioChainTarget,
                .ScenarioChainGUID = scenarioChainGUID,
            };
        },
        else => unreachable,
    }
}

fn parse_cPickupPassengers(s: *status) !sm.cPickupPassengers {
    std.debug.print("\nBEGIN cPickupPassengers\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = try parse_parseLocalisation_cUserLocalisedString(s);
    const triggerTrainStop = parseNode(s)._bool;
    const triggerWheelSlip = parseNode(s)._bool;
    const wheelSlipDuration = parseNode(s)._sInt16;

    const triggerSound = parse_cGUID(s);
    const triggerAnimation = parse_cGUID(s);

    const secondsDelay = parseNode(s)._sInt16;
    const active = parseNode(s)._bool;

    const arriveTime = parse_sTimeOfDay(s);
    const departTime = parse_sTimeOfDay(s);

    const condition = parseNode(s)._cDeltaString;
    const successEvent = parseNode(s)._cDeltaString;
    const failureEvent = parseNode(s)._cDeltaString;
    const started = parseNode(s)._bool;
    const satisfied = parseNode(s)._bool;
    const deltaTarget = try parse_cDriverInstructionTarget(s);
    const travelForwards = parseNode(s)._bool;
    const unloadPassengers = parseNode(s)._bool;

    return sm.cPickupPassengers{
        .id = idVal,
        .ActivationLevel = activationLevel,
        .SuccessTextToBeSavedMessage = successTextToBeSavedMessage,
        .FailureTextToBeSavedMessage = failureTextToBeSavedMessage,
        .DisplayTextToBeSavedMessage = displayTextToBeSavedMessage,
        .TriggeredText = triggeredText,
        .UntriggeredText = untriggeredText,
        .DisplayText = displayText,
        .TriggerTrainStop = triggerTrainStop,
        .TriggerWheelSlip = triggerWheelSlip,
        .WheelSlipDuration = wheelSlipDuration,
        .TriggerSound = triggerSound,
        .TriggerAnimation = triggerAnimation,
        .SecondsDelay = secondsDelay,
        .Active = active,
        .ArriveTime = arriveTime,
        .DepartTime = departTime,
        .Condition = condition,
        .SuccessEvent = successEvent,
        .FailureEvent = failureEvent,
        .Started = started,
        .Satisfied = satisfied,
        .DeltaTarget = deltaTarget,
        .TravelForwards = travelForwards,
        .UnloadPassengers = unloadPassengers,
    };
}

fn parse_cConsistOperation(s: *status) !sm.cConsistOperation {
    std.debug.print("\nBEGIN cConsistOperations\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;

    const triggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = try parse_parseLocalisation_cUserLocalisedString(s);

    const triggerTrainStop = parseNode(s)._bool;
    const triggerWheelSlip = parseNode(s)._bool;
    const wheelSlipDuration = parseNode(s)._sInt16;

    const triggerSound = parse_cGUID(s);
    const triggerAnimation = parse_cGUID(s);

    const secondsDelay = parseNode(s)._sInt16;
    const active = parseNode(s)._bool;

    const arriveTime = parse_sTimeOfDay(s);
    const departTime = parse_sTimeOfDay(s);

    const condition = parseNode(s)._cDeltaString;
    const successEvent = parseNode(s)._cDeltaString;
    const failureEvent = parseNode(s)._cDeltaString;
    const started = parseNode(s)._bool;
    const satisfied = parseNode(s)._bool;
    const deltaTarget = try parse_cDriverInstructionTarget(s);
    const operationOrder = parseNode(s)._bool;
    const firstUpdateDone = parseNode(s)._bool;
    const lastCompletedTargetIndex = parseNode(s)._sInt32;
    const currentTargetIndex = parseNode(s)._sUInt32;
    const targetCompletedTime = parseNode(s)._sFloat32;

    return sm.cConsistOperation{
        .id = idVal,
        .ActivationLevel = activationLevel,
        .SuccessTextToBeSavedMessage = successTextToBeSavedMessage,
        .FailureTextToBeSavedMessage = failureTextToBeSavedMessage,
        .DisplayTextToBeSavedMessage = displayTextToBeSavedMessage,
        .TriggeredText = triggeredText,
        .UntriggeredText = untriggeredText,
        .DisplayText = displayText,
        .TriggerTrainStop = triggerTrainStop,
        .TriggerWheelSlip = triggerWheelSlip,
        .WheelSlipDuration = wheelSlipDuration,
        .TriggerSound = triggerSound,
        .TriggerAnimation = triggerAnimation,
        .SecondsDelay = secondsDelay,
        .Active = active,
        .ArriveTime = arriveTime,
        .DepartTime = departTime,
        .Condition = condition,
        .SuccessEvent = successEvent,
        .FailureEvent = failureEvent,
        .Started = started,
        .Satisfied = satisfied,
        .DeltaTarget = deltaTarget,
        .OperationOrder = operationOrder,
        .FirstUpdateDone = firstUpdateDone,
        .LastCompletedTargetIndex = lastCompletedTargetIndex,
        .CurrentTargetIndex = currentTargetIndex,
        .TargetCompletedTime = targetCompletedTime,
    };
}

fn parse_cStopAtDestination(s: *status) !sm.cStopAtDestination {
    std.debug.print("\nBEGIN cStopAtDestinations\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;

    const triggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = try parse_parseLocalisation_cUserLocalisedString(s);
    const triggerTrainStop = parseNode(s)._bool;
    const triggerWheelSlip = parseNode(s)._bool;
    const wheelSlipDuration = parseNode(s)._sInt16;

    const triggerSound = parse_cGUID(s);
    const triggerAnimation = parse_cGUID(s);

    const secondsDelay = parseNode(s)._sInt16;
    const active = parseNode(s)._bool;

    const arriveTime = parse_sTimeOfDay(s);
    const departTime = parse_sTimeOfDay(s);

    const condition = parseNode(s)._cDeltaString;
    const successEvent = parseNode(s)._cDeltaString;
    const failureEvent = parseNode(s)._cDeltaString;
    const started = parseNode(s)._bool;
    const satisfied = parseNode(s)._bool;

    var driverInstructionList = std.ArrayList(sm.cDriverInstructionTarget).init(allocator);
    const driverInstructionListLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < driverInstructionListLen) : (i += 1) {
        s.current -= 1;
        try driverInstructionList.append((try parse_cDriverInstructionTarget(s)).?);
        s.current -= 1;
    }
    s.current += 1;
    const deltaTarget = driverInstructionList.items;

    const travelForwards = parseNode(s)._bool;

    return sm.cStopAtDestination{
        .id = idVal,
        .ActivationLevel = activationLevel,
        .SuccessTextToBeSavedMessage = successTextToBeSavedMessage,
        .FailureTextToBeSavedMessage = failureTextToBeSavedMessage,
        .DisplayTextToBeSavedMessage = displayTextToBeSavedMessage,
        .TriggeredText = triggeredText,
        .UntriggeredText = untriggeredText,
        .DisplayText = displayText,
        .TriggerTrainStop = triggerTrainStop,
        .TriggerWheelSlip = triggerWheelSlip,
        .WheelSlipDuration = wheelSlipDuration,
        .TriggerSound = triggerSound,
        .TriggerAnimation = triggerAnimation,
        .SecondsDelay = secondsDelay,
        .Active = active,
        .ArriveTime = arriveTime,
        .DepartTime = departTime,
        .Condition = condition,
        .SuccessEvent = successEvent,
        .FailureEvent = failureEvent,
        .Started = started,
        .Satisfied = satisfied,
        .DeltaTarget = deltaTarget,
        .TravelForwards = travelForwards,
    };
}

fn parse_cTriggerInstruction(s: *status) !sm.cTriggerInstruction {
    std.debug.print("\nBEGIN cTriggerInstruction\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = try parse_parseLocalisation_cUserLocalisedString(s);
    const triggerTrainStop = parseNode(s)._bool;
    const triggerWheelSlip = parseNode(s)._bool;
    const wheelSlipDuration = parseNode(s)._sInt16;

    const triggerSound = parse_cGUID(s);
    const triggerAnimation = parse_cGUID(s);

    const secondsDelay = parseNode(s)._sInt16;
    const active = parseNode(s)._bool;

    const arriveTime = parse_sTimeOfDay(s);
    const departTime = parse_sTimeOfDay(s);

    const condition = parseNode(s)._cDeltaString;
    const successEvent = parseNode(s)._cDeltaString;
    const failureEvent = parseNode(s)._cDeltaString;
    const started = parseNode(s)._bool;
    const satisfied = parseNode(s)._bool;

    const deltaTarget = try parse_cDriverInstructionTarget(s);

    const startTime = parseNode(s)._sFloat32;

    return sm.cTriggerInstruction{
        .Id = id,
        .ActivationLevel = activationLevel,
        .SuccessTextToBeSavedMessage = successTextToBeSavedMessage,
        .FailureTextToBeSavedMessage = failureTextToBeSavedMessage,
        .DisplayTextToBeSavedMessage = displayTextToBeSavedMessage,
        .TriggeredText = triggeredText,
        .UntriggeredText = untriggeredText,
        .DisplayText = displayText,
        .TriggerTrainStop = triggerTrainStop,
        .TriggerWheelSlip = triggerWheelSlip,
        .WheelSlipDuration = wheelSlipDuration,
        .TriggerSound = triggerSound,
        .TriggerAnimation = triggerAnimation,
        .SecondsDelay = secondsDelay,
        .Active = active,
        .ArriveTime = arriveTime,
        .DepartTime = departTime,
        .Condition = condition,
        .SuccessEvent = successEvent,
        .FailureEvent = failureEvent,
        .Started = started,
        .Satisfied = satisfied,
        .DeltaTarget = deltaTarget,
        .StartTime = startTime,
    };
}

fn parse_cDriverInstructionContainer(s: *status) !sm.cDriverInstructionContainer {
    std.debug.print("\nBEGIN cDriverInstructionContainer\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    s.current += 1;
    const driverInstruction = parse_DriverInstruction(s);
    s.current += 1;

    return sm.cDriverInstructionContainer{
        .id = idVal,
        .DriverInstruction = try driverInstruction,
    };
}

fn parse_cDriver(s: *status) !?sm.cDriver {
    std.debug.print("\nBEGIN cDriver\n", .{});
    switch (s.nodeList[s.current + 1]) {
        .ff4enode => {
            s.current += 3;
            return null;
        },
        .ff50node => {
            std.debug.print("\nBEGIN cDriver\n", .{});
            std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
            const idVal = s.nodeList[s.current].ff50node.id;
            s.current += 2;
            defer s.current += 2;
            const finalDestination = try parse_cDriverInstructionTarget(s);

            const playerDriver = parseNode(s)._bool;

            const serviceName = try parse_parseLocalisation_cUserLocalisedString(s);

            var initialRVList = std.ArrayList([]const u8).init(allocator);
            const initialRVListLength = s.nodeList[s.current].ff50node.children;

            s.current += 1;
            var i: u32 = 0;
            while (i < initialRVListLength) : (i += 1) {
                try initialRVList.append(s.nodeList[s.current].ff56node.value._cDeltaString);
                s.current += 1;
            }
            s.current += 1;

            const initialRV = initialRVList.items;
            const startTime = parseNode(s)._sFloat32;
            const startSpeed = parseNode(s)._sFloat32;
            const endSpeed = parseNode(s)._sFloat32;
            const serviceClass = parseNode(s)._sInt32;
            const expectedPerformance = parseNode(s)._sFloat32;
            const playerControlled = parseNode(s)._bool;
            const priorPathingStatus = parseNode(s)._cDeltaString;
            const pathingStatus = parseNode(s)._cDeltaString;
            const repathIn = parseNode(s)._sFloat32;
            const forcedRepath = parseNode(s)._bool;
            const offPath = parseNode(s)._bool;
            const startTriggerDistanceFromPlayerSquared = parseNode(s)._sFloat32;
            const driverInstructionContainer = try parse_cDriverInstructionContainer(s);
            const unloadedAtStart = parseNode(s)._bool;

            return sm.cDriver{
                .id = idVal,
                .FinalDestination = finalDestination,
                .PlayerDriver = playerDriver,
                .ServiceName = serviceName,
                .InitialRV = initialRV,
                .StartTime = startTime,
                .StartSpeed = startSpeed,
                .EndSpeed = endSpeed,
                .ServiceClass = serviceClass,
                .ExpectedPerformance = expectedPerformance,
                .PlayerControlled = playerControlled,
                .PriorPathingStatus = priorPathingStatus,
                .PathingStatus = pathingStatus,
                .RepathIn = repathIn,
                .ForcedRepath = forcedRepath,
                .OffPath = offPath,
                .StartTriggerDistanceFromPlayerSquared = startTriggerDistanceFromPlayerSquared,
                .DriverInstructionContainer = driverInstructionContainer,
                .UnloadedAtStart = unloadedAtStart,
            };
        },
        else => unreachable,
    }
}

fn parse_cRouteCoordinate(s: *status) sm.cRouteCoordinate {
    std.debug.print("\nBEGIN cRouteCoordinate\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    s.current += 2;
    defer s.current += 2;
    const distance = parseNode(s)._sInt32;
    return sm.cRouteCoordinate{
        .Distance = distance,
    };
}

fn parse_cTileCoordinate(s: *status) sm.cTileCoordinate {
    std.debug.print("\nBEGIN cTileCoordinate\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    s.current += 2;
    defer s.current += 2;
    const distance = parseNode(s)._sFloat32;
    return sm.cTileCoordinate{
        .Distance = distance,
    };
}

fn parse_cFarCoordinate(s: *status) sm.cFarCoordinate {
    std.debug.print("\nBEGIN cFarCoordinate\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    s.current += 2;
    defer s.current += 2;

    const routeCoordinate = parse_cRouteCoordinate(s);
    const tileCoordinate = parse_cTileCoordinate(s);

    return sm.cFarCoordinate{
        .RouteCoordinate = routeCoordinate,
        .TileCoordinate = tileCoordinate,
    };
}

fn parse_cFarVector2(s: *status) sm.cFarVector2 {
    std.debug.print("\nBEGIN cFarVector2\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    const id = s.nodeList[s.current + 1].ff50node.id;
    s.current += 2;
    defer s.current += 2;

    const x = parse_cFarCoordinate(s);
    const z = parse_cFarCoordinate(s);

    return sm.cFarVector2{
        .Id = id,
        .X = x,
        .Z = z,
    };
}

fn parse_Network_cDirection(s: *status) sm.Network_cDirection {
    std.debug.print("\nBEGIN Network_cDirection\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    s.current += 2;
    defer s.current += 2;
    const dir = parseNode(s)._cDeltaString;
    return sm.Network_cDirection{
        ._dir = dir,
    };
}

fn parse_Network_cTrackFollower(s: *status) sm.Network_cTrackFollower {
    std.debug.print("\nBEGIN Network_cTrackFollower\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    const id = s.nodeList[s.current + 1].ff50node.id;
    s.current += 2;
    defer s.current += 2;

    const height = parseNode(s)._sFloat32;
    const tpe = parseNode(s)._cDeltaString;
    const position = parseNode(s)._sFloat32;
    const direction = parse_Network_cDirection(s);
    const ribbonId = parse_cGUID(s);

    return sm.Network_cTrackFollower{
        .Id = id,
        .Height = height,
        ._type = tpe,
        .Position = position,
        .Direction = direction,
        .RibbonId = ribbonId,
    };
}

fn parse_vehicle(s: *status) !sm.Vehicle {
    const vehicleType = s.nodeList[s.current].ff50node.name;
    if (std.mem.eql(u8, vehicleType, "cWagon")) {
        return sm.Vehicle{ .cWagon = (try parse_cWagon(s)) };
    } else if (std.mem.eql(u8, vehicleType, "cEngine")) {
        return sm.Vehicle{ .cEngine = (try parse_cEngine(s)) };
    } else {
        unreachable;
    }
}

fn parse_cEngine(s: *status) !sm.cEngine {
    std.debug.print("\nBEGIN cEngine\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const pantographInfo = parseNode(s)._cDeltaString;
    const pantographIsDirectional = parseNode(s)._bool;
    const lastPantographControlValue = parseNode(s)._sFloat32;
    const flipped = parseNode(s)._bool;
    const uniqueNumber = parseNode(s)._cDeltaString;
    const gUID = parseNode(s)._cDeltaString;

    var followerList = std.ArrayList(sm.Network_cTrackFollower).init(allocator);
    const followerListLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;
    var i: u32 = 0;
    while (i < followerListLen) : (i += 1) {
        s.current -= 1;
        try followerList.append(parse_Network_cTrackFollower(s));
        s.current -= 1;
    }
    s.current += 1;

    const followers = followerList.items;
    const totalMass = parseNode(s)._sFloat32;
    const speed = parseNode(s)._sFloat32;
    const velocity = try parse_cHcRVector4(s);

    const inTunnel = parseNode(s)._bool;
    const disabledEngine = parseNode(s)._bool;
    const awsTimer = parseNode(s)._sFloat32;
    const awsExpired = parseNode(s)._bool;
    const tpwsDistance = parseNode(s)._sFloat32;

    return sm.cEngine{
        .Id = id,
        .PantographInfo = pantographInfo,
        .PantographIsDirectional = pantographIsDirectional,
        .LastPantographControlValue = lastPantographControlValue,
        .Flipped = flipped,
        .UniqueNumber = uniqueNumber,
        .GUID = gUID,
        .Followers = followers,
        .TotalMass = totalMass,
        .Speed = speed,
        .Velocity = velocity,
        .InTunnel = inTunnel,
        .DisabledEngine = disabledEngine,
        .AWSTimer = awsTimer,
        .AWSExpired = awsExpired,
        .TPWSDistance = tpwsDistance,
    };
}

fn parse_cWagon(s: *status) !sm.cWagon {
    std.debug.print("\nBEGIN cWagon\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const pantographInfo = parseNode(s)._cDeltaString;
    const pantographIsDirectional = parseNode(s)._bool;
    const lastPantographControlValue = parseNode(s)._sFloat32;
    const flipped = parseNode(s)._bool;
    const uniqueNumber = parseNode(s)._cDeltaString;
    const gUID = parseNode(s)._cDeltaString;

    var followerList = std.ArrayList(sm.Network_cTrackFollower).init(allocator);
    const followerListLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;
    var i: u32 = 0;
    while (i < followerListLen) : (i += 1) {
        s.current -= 1;
        try followerList.append(parse_Network_cTrackFollower(s));
        s.current -= 1;
    }
    s.current += 1;

    const followers = followerList.items;
    const totalMass = parseNode(s)._sFloat32;
    const speed = parseNode(s)._sFloat32;
    const velocity = try parse_cHcRVector4(s);

    const inTunnel = parseNode(s)._bool;

    return sm.cWagon{
        .Id = id,
        .PantographInfo = pantographInfo,
        .PantographIsDirectional = pantographIsDirectional,
        .LastPantographControlValue = lastPantographControlValue,
        .Flipped = flipped,
        .UniqueNumber = uniqueNumber,
        .GUID = gUID,
        .Followers = followers,
        .TotalMass = totalMass,
        .Speed = speed,
        .Velocity = velocity,
        .InTunnel = inTunnel,
    };
}

fn parse_cHcRVector4(s: *status) !?sm.cHcRVector4 {
    std.debug.print("\nBEGIN cHcRVector4\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    if (s.nodeList[s.current + 1].ff50node.children == 0) {
        return null;
    }
    s.current += 3;
    defer s.current += 3;

    var vectorList = std.ArrayList(f32).init(allocator);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        try vectorList.append(parseNode(s)._sFloat32);
    }

    return sm.cHcRVector4{
        .Element = vectorList.items,
    };
}

fn parse_cScriptComponent(s: *status) sm.cScriptComponent {
    std.debug.print("\nBEGIN cScriptComponent\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const debugDisplay = parseNode(s)._bool;
    const stateName = parseNode(s)._cDeltaString;

    return sm.cScriptComponent{
        .Id = id,
        .DebugDisplay = debugDisplay,
        .StateName = stateName,
    };
}

fn parse_cCargoComponent(s: *status) !sm.cCargoComponent {
    std.debug.print("\nBEGIN cCargoComponent\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const isPreloaded = parseNode(s)._cDeltaString;

    var initialLevelArray = std.ArrayList(f32).init(allocator);
    const initialLevelArrayLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < initialLevelArrayLen) : (i += 1) {
        try initialLevelArray.append(parseNode(s)._sFloat32);
    }
    const initialLevel = initialLevelArray.items;
    s.current += 1;

    return sm.cCargoComponent{
        .Id = id,
        .IsPreLoaded = isPreloaded,
        .InitialLevel = initialLevel,
    };
}

fn parse_cControlContainer(s: *status) sm.cControlContainer {
    std.debug.print("\nBEGIN cControlContainer\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const time = parseNode(s)._sFloat32;
    const frameTime = parseNode(s)._sFloat32;
    const cabEndsWithKey = parseNode(s)._cDeltaString;

    return sm.cControlContainer{
        .Id = id,
        .Time = time,
        .FrameTime = frameTime,
        .CabEndsWithKey = cabEndsWithKey,
    };
}

fn parse_cAnimObjectRender(s: *status) sm.cAnimObjectRender {
    std.debug.print("\nBEGIN cAnimObjectRender\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const detailLevel = parseNode(s)._sInt32;
    const global = parseNode(s)._bool;
    const saved = parseNode(s)._bool;
    const palette0Index = parseNode(s)._sUInt8;
    const palette1Index = parseNode(s)._sUInt8;
    const palette2Index = parseNode(s)._sUInt8;

    return sm.cAnimObjectRender{
        .Id = id,
        .DetailLevel = detailLevel,
        .Global = global,
        .Saved = saved,
        .Palette0Index = palette0Index,
        .Palette1Index = palette1Index,
        .Palette2Index = palette2Index,
    };
}

fn parse_iBlueprintLibrary_cBlueprintSetId(s: *status) sm.iBlueprintLibrary_cBlueprintSetId {
    std.debug.print("\nBEGIN iBlueprintLibrary_cBlueprintSetId\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    s.current += 2;
    defer s.current += 2;

    const provider = parseNode(s)._cDeltaString;
    const product = parseNode(s)._cDeltaString;

    return sm.iBlueprintLibrary_cBlueprintSetId{
        .Provider = provider,
        .Product = product,
    };
}

fn parse_iBlueprintLibrary_cAbsoluteBlueprintID(s: *status) sm.iBlueprintLibrary_cAbsoluteBlueprintID {
    std.debug.print("\nBEGIN iBlueprintLibrary_cAbsoluteBlueprintID\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    s.current += 2;
    defer s.current += 2;

    const blueprintSetId = parse_iBlueprintLibrary_cBlueprintSetId(s);
    const blueprintID = parseNode(s)._cDeltaString;

    return sm.iBlueprintLibrary_cAbsoluteBlueprintID{
        .BlueprintSetId = blueprintSetId,
        .BlueprintID = blueprintID,
    };
}

fn parse_cFarMatrix(s: *status) sm.cFarMatrix {
    std.debug.print("\nBEGIN cFarMatrix\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current + 1].ff50node.name});
    const id = s.nodeList[s.current + 1].ff50node.id;
    s.current += 2;
    defer s.current += 2;

    const height = parseNode(s)._sFloat32;

    var rxAxis: [4]f32 = undefined;
    for (s.nodeList[s.current].ff41node.values.items) |val, i| {
        rxAxis[i] = val._sFloat32;
    }
    s.current += 1;

    var ryAxis: [4]f32 = undefined;
    for (s.nodeList[s.current].ff41node.values.items) |val, i| {
        ryAxis[i] = val._sFloat32;
    }
    s.current += 1;

    var rzAxis: [4]f32 = undefined;
    for (s.nodeList[s.current].ff41node.values.items) |val, i| {
        rzAxis[i] = val._sFloat32;
    }
    s.current += 1;

    const rFarPosition = parse_cFarVector2(s);

    return sm.cFarMatrix{
        .Id = id,
        .Height = height,
        .RXAxis = rxAxis,
        .RYAxis = ryAxis,
        .RZAxis = rzAxis,
        .RFarPosition = rFarPosition,
    };
}

fn parse_cPosOri(s: *status) sm.cPosOri {
    std.debug.print("\nBEGIN cPosOri\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    var scale: [4]f32 = undefined;
    for (s.nodeList[s.current].ff41node.values.items) |val, i| {
        scale[i] = val._sFloat32;
    }
    s.current += 1;

    const rFarMatrix = parse_cFarMatrix(s);

    return sm.cPosOri{
        .Id = id,
        .Scale = scale,
        .RFarMatrix = rFarMatrix,
    };
}

fn parse_cEntityContainer(s: *status) !sm.cEntityContainer {
    std.debug.print("\nBEGIN cEntityContainer\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 2;

    var staticChildrenMatrix = std.ArrayList([16]f32).init(allocator);
    const staticChildrenMatrixLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < staticChildrenMatrixLen) : (i += 1) {
        try staticChildrenMatrix.append([_]f32{0} ** 16);
        var j: u32 = 0;
        while (j < 16) : (j += 1) {
            staticChildrenMatrix.items[i][j] = s.nodeList[s.current].ff41node.values.items[j]._sFloat32;
        }
        s.current += 1;
    }

    return sm.cEntityContainer{
        .Id = id,
        .StaticChildrenMatrix = staticChildrenMatrix.items,
    };
}

fn parse_Component(s: *status) !sm.Component {
    std.debug.print("\nBEGIN Component\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const childCount = s.nodeList[s.current].ff50node.children;
    return switch (childCount) {
        6 => try parse_PassWagon(s),
        7 => try parse_CargoWagon(s),
        8 => try parse_Engine(s),
        else => unreachable,
    };
}

fn parse_PassWagon(s: *status) !sm.Component {
    std.debug.print("\nBEGIN PassWagon\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    s.current += 1;
    defer s.current += 1;

    const wagon = try parse_cWagon(s);
    const animObjectRender = parse_cAnimObjectRender(s);
    const posOri = parse_cPosOri(s);
    const controlContainer = parse_cControlContainer(s);
    const entityContainer = try parse_cEntityContainer(s);
    const scriptComponent = parse_cScriptComponent(s);

    return sm.Component{ .PassWagon = sm.PassWagon{
        .cWagon = wagon,
        .cAnimObjectRender = animObjectRender,
        .cPosOri = posOri,
        .cControlContainer = controlContainer,
        .cEntityContainer = entityContainer,
        .cScriptComponent = scriptComponent,
    } };
}

fn parse_CargoWagon(s: *status) !sm.Component {
    std.debug.print("\nBEGIN CargoWagon\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    s.current += 1;
    defer s.current += 1;

    const wagon = try parse_cWagon(s);
    const animObjectRender = parse_cAnimObjectRender(s);
    const posOri = parse_cPosOri(s);
    const controlContainer = parse_cControlContainer(s);
    const cargoComponent = try parse_cCargoComponent(s);
    const entityContainer = try parse_cEntityContainer(s);
    const scriptComponent = parse_cScriptComponent(s);

    return sm.Component{ .CargoWagon = sm.CargoWagon{
        .cWagon = wagon,
        .cAnimObjectRender = animObjectRender,
        .cPosOri = posOri,
        .cControlContainer = controlContainer,
        .cCargoComponent = cargoComponent,
        .cEntityContainer = entityContainer,
        .cScriptComponent = scriptComponent,
    } };
}

fn parse_Engine(s: *status) !sm.Component {
    std.debug.print("\nBEGIN Engine\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    s.current += 1;
    defer s.current += 1;

    const engine = try parse_cEngine(s);
    const animObjectRender = parse_cAnimObjectRender(s);
    const posOri = parse_cPosOri(s);
    const engineSimContainer = parse_cEngineSimContainer(s);
    const controlContainer = parse_cControlContainer(s);
    const entityContainer = try parse_cEntityContainer(s);
    const scriptComponent = parse_cScriptComponent(s);
    const cargoComponent = try parse_cCargoComponent(s);

    return sm.Component{ .Engine = sm.Engine{
        .cEngine = engine,
        .cAnimObjectRender = animObjectRender,
        .cPosOri = posOri,
        .cEngineSimContainer = engineSimContainer,
        .cControlContainer = controlContainer,
        .cEntityContainer = entityContainer,
        .cScriptComponent = scriptComponent,
        .cCargoComponent = cargoComponent,
    } };
}

fn parse_cEngineSimContainer(s: *status) u32 {
    std.debug.print("\nBEGIN cEngineSimContainer\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    defer s.current += 2;
    return s.nodeList[s.current].ff50node.id;
}

fn parse_cOwnedEntity(s: *status) !sm.cOwnedEntity {
    std.debug.print("\nBEGIN cOwnedEntity\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    s.current += 1;
    defer s.current += 1;

    const component = try parse_Component(s);

    const blueprintID = parse_iBlueprintLibrary_cAbsoluteBlueprintID(s);
    const reskinBlueprintID = parse_iBlueprintLibrary_cAbsoluteBlueprintID(s);
    const name = parseNode(s)._cDeltaString;
    const entityID = parse_cGUID(s);

    return sm.cOwnedEntity{
        .Component = component,
        .BlueprintID = blueprintID,
        .ReskinBlueprintID = reskinBlueprintID,
        .Name = name,
        .EntityID = entityID,
    };
}

fn parse_cConsist(s: *status) !sm.cConsist {
    std.debug.print("\nBEGIN cConsist\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    var railVehiclesArray = std.ArrayList(sm.cOwnedEntity).init(allocator);
    const railVehiclesArrayLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < railVehiclesArrayLen) : (i += 1) {
        try railVehiclesArray.append(try parse_cOwnedEntity(s));
    }
    const railVehicles = railVehiclesArray.items;
    s.current += 1;

    const frontFollower = parse_Network_cTrackFollower(s);
    const rearFollower = parse_Network_cTrackFollower(s);
    const driver = try parse_cDriver(s);
    const inPortalName = parseNode(s)._cDeltaString;
    const driverEngineIndex = parseNode(s)._sInt32;
    const platformRibbonGUID = parse_cGUID(s);
    const platformTimeRemaining = parseNode(s)._sFloat32;
    const maxPermissableSpeed = parseNode(s)._sFloat32;
    const currentDirection = parse_Network_cDirection(s);
    const ignorePhysicsFrames = parseNode(s)._sInt32;
    const ignoreProximity = parseNode(s)._bool;

    return sm.cConsist{
        .Id = id,
        .RailVehicles = railVehicles,
        .FrontFollower = frontFollower,
        .RearFollower = rearFollower,
        .Driver = driver,
        .InPortalName = inPortalName,
        .DriverEngineIndex = driverEngineIndex,
        .PlatformRibbonGUID = platformRibbonGUID,
        .PlatformTimeRemaining = platformTimeRemaining,
        .MaxPermissableSpeed = maxPermissableSpeed,
        .CurrentDirection = currentDirection,
        .IgnorePhysicsFrames = ignorePhysicsFrames,
        .IgnoreProximity = ignoreProximity,
    };
}

fn parse_Record(s: *status) !sm.Record {
    std.debug.print("\nBEGIN Record\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    var consistsArray = std.ArrayList(sm.cConsist).init(allocator);
    const consistsArrayLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < consistsArrayLen) : (i += 1) {
        try consistsArray.append(try parse_cConsist(s));
    }
    const consists = consistsArray.items;
    s.current += 1;

    return sm.Record{
        .cConsists = consists,
    };
}

fn parse_cRecordSet(s: *status) !sm.cRecordSet {
    std.debug.print("\nBEGIN cRecordSet\n", .{});
    std.debug.print("NODE NAME: {s}\n", .{s.nodeList[s.current].ff50node.name});
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const record = try parse_Record(s);
    return sm.cRecordSet{
        .Id = id,
        .Record = record,
    };
}

////////////////////////////////////////////////////////////
/////////////////// Test Area //////////////////////////////
////////////////////////////////////////////////////////////

test "Parse Time of Day" {
    // Arrange
    const parentNode = n.node{ .ff50node = n.ff50node{
        .name = "sTimeOfDay",
        .id = 0,
        .children = 3,
    } };
    const hourNode = n.node{ .ff56node = n.ff56node{
        .name = "_iHour",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 1 },
    } };
    const minuteNode = n.node{ .ff56node = n.ff56node{
        .name = "_iMinute",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 3 },
    } };
    const secondNode = n.node{ .ff56node = n.ff56node{
        .name = "_iSeconds",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 5 },
    } };
    const nodeList = &[_]n.node{ parentNode, hourNode, minuteNode, secondNode };
    var s = status.init(nodeList);

    // Act
    const result = parse_sTimeOfDay(&s);

    // Assert
    try expectEqual(result._iHour, 1);
    try expectEqual(result._iMinute, 3);
    try expectEqual(result._iSeconds, 5);
    try expectEqual(s.current, 5);
}

test "Parse Localization_cUserLocalizedString" {
    // Arrange
    const parentNode = n.node{ .ff50node = n.ff50node{
        .name = "cUserLocalizedString",
        .id = 0,
        .children = 10,
    } };
    const english = n.node{ .ff56node = n.ff56node{
        .name = "English",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "English String" },
    } };
    const french = n.node{ .ff56node = n.ff56node{
        .name = "French",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const italian = n.node{ .ff56node = n.ff56node{
        .name = "Italian",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const german = n.node{ .ff56node = n.ff56node{
        .name = "German",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const spanish = n.node{ .ff56node = n.ff56node{
        .name = "Spanish",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const dutch = n.node{ .ff56node = n.ff56node{
        .name = "Dutch",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const polish = n.node{ .ff56node = n.ff56node{
        .name = "Polish",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const russian = n.node{ .ff56node = n.ff56node{
        .name = "Russian",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const other = n.node{ .ff50node = n.ff50node{
        .name = "Other",
        .id = 0,
        .children = 1,
    } };
    const chinese = n.node{ .ff56node = n.ff56node{
        .name = "Chinese",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "How" },
    } };
    const key = n.node{ .ff56node = n.ff56node{
        .name = "English",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "KEY VAL" },
    } };
    const nodeList = &[_]n.node{ parentNode, english, french, italian, german, spanish, dutch, polish, russian, other, chinese, key };
    var s = status.init(nodeList);

    // Act
    const result = try parse_parseLocalisation_cUserLocalisedString(&s);

    // Assert
    try expectEqualStrings(result.English, "English String");
    try expectEqualStrings(result.Italian, "");
    try expectEqualStrings(result.Key, "KEY VAL");
    try expectEqualStrings(result.Other[0].Value, "How");
    try expectEqual(s.current, 13);
}
