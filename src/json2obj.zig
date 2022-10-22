const std = @import("std");
const parser = @import("binParser.zig");
const sorter = @import("sort.zig");
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

pub const status = struct {
    current: usize,
    source: n.textNode,
    stringMap: strMapType,
    lineMap: lineMapType,
    parentStack: ?std.ArrayList(*n.node),
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
};

fn convertTnode(s: *status, node: n.textNode) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    switch (node) {
        .ff56NodeT => |ff56node| {
            try result.appendSlice(ff56);
            try result.appendSlice(try s.checkStringMap(ff56node.name));
            try result.appendSlice(try s.checkStringMap(ff56node.dType));
            try result.appendSlice(try convertDataUnion(s, ff56node.value));
        },
        .ff41NodeT => |ff41node| {
            try result.appendSlice(ff41);
            try result.appendSlice(try s.checkStringMap(ff41node.name));
            try result.appendSlice(try s.checkStringMap(ff41node.dType));
            try result.append(ff41node.numElements);
            for (ff41node.values) |val| {
                try result.appendSlice(try convertDataUnion(s, val));
            }
        },
        .ff4eNodeT => {
            try result.appendSlice(ff4e);
        },
        else => {
            unreachable;
        },
    }
    return result.items;
}

fn convertDataUnion(s: *status, data: n.dataUnion) ![]const u8 {
    var returnSlice = std.ArrayList(u8).init(allocator);
    switch (data) {
        ._bool => |val| {
            try returnSlice.appendSlice(&std.mem.toBytes(val));
        },
        ._sUInt8 => |val| {
            try returnSlice.appendSlice(&std.mem.toBytes(val));
        },
        ._sInt32 => |val| {
            try returnSlice.appendSlice(&std.mem.toBytes(val));
        },
        ._sFloat32 => |val| {
            try returnSlice.appendSlice(&std.mem.toBytes(val));
        },
        ._sUInt64 => |val| {
            try returnSlice.appendSlice(&std.mem.toBytes(val));
        },
        ._cDeltaString => |val| {
            //try returnSlice.appendSlice(&std.mem.toBytes(val));
            try returnSlice.appendSlice(try s.checkStringMap(val));
        },
    }
    return returnSlice.items;
}

pub fn main() !void {
    const testNode = n.textNode{ .ff56NodeT = n.ff56NodeT{ .name = "Node1", .dType = "sInt32", .value = n.dataUnion{ ._sInt32 = 123 } } };
    var s = status.init(testNode);
    std.debug.print("{any}\n", .{try convertTnode(&s, testNode)});

    //var inFile = try std.fs.cwd().openFile("testFiles/test.bin", .{});
    //defer inFile.close();

    //const outFile = try std.fs.cwd().createFile(
    //    "results.txt",
    //    .{ .read = true },
    //);
    //defer outFile.close();
    //const inputBytes = try inFile.readToEndAlloc(allocator, size_limit);
    //var testStatus = parser.status.init(inputBytes);

    //const nodes = (try parser.parse(&testStatus)).items;
    //const textNodesList = try sorter.sort(nodes);

    //var string = std.ArrayList(u8).init(allocator);
    //try std.json.stringify(textNodesList, .{}, string.writer());

    //var jparser = std.json.Parser.init(allocator, false);
    //defer jparser.deinit();

    //var stream = std.json.TokenStream.init(string.items);
    //const parsedData = try std.json.parse(n.textNode, &stream, .{ .allocator = allocator });
    //std.debug.print("{any}\n", .{parsedData});

    //try outFile.writeAll(string.items);
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
