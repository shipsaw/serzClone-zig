const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const n = @import("node.zig");

const node = n.node;
const ff41node = n.ff41node;
const ff4enode = n.ff4enode;
const ff50node = n.ff50node;
const ff56node = n.ff56node;
const ff70node = n.ff70node;
const dataType = n.dataType;
const dataUnion = n.dataUnion;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();

pub const status = struct {
    start: usize,
    current: usize,
    line: usize,
    source: []const u8,
    currentParentNode: ?*node,
    stringMap: std.ArrayList([]const u8),
    savedTokenList: std.ArrayList(node),
    resultRoot: ?node,

    pub fn init(src: []const u8) status {
        return status{
            .start = 0,
            .current = 0,
            .line = 0,
            .source = src,
            .currentParentNode = null,
            .stringMap = std.ArrayList([]const u8).init(allocator),
            .savedTokenList = std.ArrayList(node).init(allocator),
            .resultRoot = null,
        };
    }

    pub fn advance(self: *status) u8 {
        defer self.current += 1;
        return self.source[self.current];
    }

    pub fn peek(self: *status) u8 {
        return if (self.isAtEnd()) 0 else self.source[self.current];
    }

    pub fn peekNext(self: *status) u8 {
        return if (self.current + 1 >= self.source.len) 0 else self.source[self.current + 1];
    }

    pub fn isAtEnd(self: *status) bool {
        return self.current >= self.source.len;
    }
};

const errors = error{
    InvalidNodeType,
    TooManyChildren,
};

const dataTypeMap = std.ComptimeStringMap(dataType, .{
    .{ "bool", ._bool },
    .{ "sUInt8", ._sUInt8 },
    .{ "sInt32", ._sInt32 },
    .{ "sUInt64", ._sUInt64 },
    .{ "sFloat32", ._sFloat32 },
    .{ "cDeltaString", ._cDeltaString },
});
pub fn parse(s: *status) !node {
    errdefer {
        errorInfo(s);
    }

    try expectEqualStrings("SERZ", s.source[0..4]);
    s.current += 4;
    _ = processU32(s);

    // Process first node seperate, to initialize children list for root
    if (s.source[s.current] == 0xff) {
        s.current += 2;
        const rootNode = try processFF50(s);
        s.currentParentNode = &node{ .ff50node = rootNode };
        try s.savedTokenList.append(node{ .ff50node = rootNode });
        s.line += 1;
        s.resultRoot = node{ .ff50node = rootNode };
    } else unreachable;

    while (!s.isAtEnd()) {
        if (s.source[s.current] == 0xff) {
            s.current += 1;
            switch (s.source[s.current]) {
                0x41 => {
                    s.current += 1;
                    const tok = try processFF41(s);
                    try (s.currentParentNode.?.*).ff50node.children.append(node{ .ff41node = tok });
                    try s.savedTokenList.append(node{ .ff41node = tok });
                },
                0x4e => {
                    s.current += 1;
                    try (s.currentParentNode.?.*).ff50node.children.append(node{ .ff4enode = ff4enode{} });
                    try s.savedTokenList.append(node{ .ff4enode = ff4enode{} });
                },
                0x50 => {
                    s.current += 1;
                    const tok = try processFF50(s);
                    try (s.currentParentNode.?.*).ff50node.children.append(node{ .ff50node = tok });
                    try s.savedTokenList.append(node{ .ff50node = tok });
                    s.currentParentNode = &node{ .ff50node = tok };
                },
                0x56 => {
                    s.current += 1;
                    const tok = try processFF56(s);
                    try (s.currentParentNode.?.*).ff50node.children.append(node{ .ff56node = tok });
                    try s.savedTokenList.append(node{ .ff56node = tok });
                },
                0x70 => {
                    s.current += 1;
                    const tok = try processFF70(s);
                    try (s.currentParentNode.?.*).ff50node.children.append(node{ .ff70node = tok });
                    try s.savedTokenList.append(node{ .ff70node = tok });
                },
                else => return errors.InvalidNodeType,
            }
        } else {
            const tok = try processSavedLine(s);
            try (s.currentParentNode.?.*).ff50node.children.append(tok);
            switch (tok) {
                .ff50node => |n| s.currentParentNode = &node{ .ff50node = n },
                else => continue,
            }
        }
        if (s.line < 255) s.line += 1;
    }
    return s.resultRoot.?;
}

fn identifier(s: *status) ![]const u8 {
    if (s.source[s.current] == 255) // New string
    {
        s.current += 2;

        const strLen = std.mem.readIntSlice(u32, s.source[s.current..], std.builtin.Endian.Little);
        s.current += 4;

        var str = s.source[s.current..(s.current + strLen)];
        try s.stringMap.append(str);
        defer s.current += strLen;

        return str;
    }
    const strIdx = std.mem.readIntSlice(u16, s.source[s.current..], std.builtin.Endian.Little);
    s.current += 2;

    return s.stringMap.items[strIdx];
}

fn processData(s: *status, dType: dataType) !dataUnion {
    return switch (dType) {
        dataType._bool => processBool(s),
        dataType._sUInt8 => processSUInt8(s),
        dataType._sInt32 => processSInt32(s),
        dataType._sUInt64 => processU64(s),
        dataType._sFloat32 => processSFloat32(s),
        dataType._cDeltaString => processCDeltaString(s),
    };
}

fn processBool(s: *status) dataUnion {
    defer s.current += 1;
    return switch (s.source[s.current]) {
        1 => dataUnion{ ._bool = true },
        0 => dataUnion{ ._bool = false },
        else => unreachable,
    };
}

fn processSUInt8(s: *status) dataUnion {
    defer s.current += 1;
    // const val = std.mem.readIntSlice(u8, s.source[s.current..], std.builtin.Endian.Little);
    const val = s.source[s.current];
    return dataUnion{ ._sUInt8 = val };
}

fn processSInt32(s: *status) dataUnion {
    defer s.current += 4;
    const val = std.mem.readIntSlice(i32, s.source[s.current..], std.builtin.Endian.Little);
    return dataUnion{ ._sInt32 = val };
}

fn processU64(s: *status) dataUnion {
    defer s.current += 8;
    const val = std.mem.readIntSlice(u64, s.source[s.current..], std.builtin.Endian.Little);
    return dataUnion{ ._sUInt64 = val };
}

fn processSFloat32(s: *status) dataUnion {
    defer s.current += 4;
    const val = @bitCast(f32, std.mem.readIntSlice(i32, s.source[s.current..], std.builtin.Endian.Little));
    return dataUnion{ ._sFloat32 = val };
}

fn processCDeltaString(s: *status) !dataUnion {
    const str = try identifier(s);
    return dataUnion{ ._cDeltaString = str };
}

fn processFF41(s: *status) !ff41node {
    const nodeName = try identifier(s);
    const elemType = dataTypeMap.get(try identifier(s)).?;
    const numElements = s.source[s.current];
    s.current += 1;

    var elemValues = std.ArrayList(dataUnion).init(allocator);
    var i: u8 = 0;
    while (i < numElements) : (i += 1) {
        try elemValues.append(try processData(s, elemType));
    }

    return ff41node{
        .name = nodeName,
        .dType = elemType,
        .numElements = numElements,
        .values = elemValues,
    };
}

fn processFF50(s: *status) !ff50node {
    const nodeName = try identifier(s);
    const id = processU32(s);
    const numChildren = processU32(s);

    return ff50node{
        .name = nodeName,
        .id = id,
        .numChildren = numChildren,
        .children = std.ArrayList(node).init(allocator),
    };
}

fn processFF56(s: *status) !ff56node {
    const nodeName = try identifier(s);
    const dType = dataTypeMap.get(try identifier(s)).?;
    const data = try processData(s, dType);

    return ff56node{
        .name = nodeName,
        .dType = dType,
        .value = data,
    };
}

fn processFF70(s: *status) !ff70node {
    const nodeStr = processU16(s);
    const nodeName = s.stringMap.items[nodeStr];
    return ff70node{
        .name = nodeName,
    };
}

fn processSavedLine(s: *status) !node {
    if (s.source[s.current] > s.savedTokenList.items.len) {
        return error.InvalidFileError;
    }
    const savedLine = s.savedTokenList.items[s.source[s.current]];
    s.current += 1;
    switch (savedLine) {
        .ff56node => {
            const data = try processData(s, savedLine.ff56node.dType);
            return node{ .ff56node = ff56node{
                .name = savedLine.ff56node.name,
                .dType = savedLine.ff56node.dType,
                .value = data,
            } };
        },
        .ff41node => {
            var newNode = ff41node{
                .name = savedLine.ff41node.name,
                .dType = savedLine.ff41node.dType,
                .numElements = s.source[s.current],
                .values = std.ArrayList(dataUnion).init(allocator),
            };
            s.current += 1;
            var i: u8 = 0;
            while (i < savedLine.ff41node.numElements) : (i += 1) {
                try newNode.values.append(try processData(s, savedLine.ff41node.dType));
            }
            return node{ .ff41node = newNode };
        },
        .ff50node => {
            // return errors.InvalidNodeType;
            const id = processU32(s);
            const numChildren = processU32(s);
            if (numChildren > 100) {
                s.current -= 8;
                return errors.TooManyChildren;
            }
            return node{ .ff50node = ff50node{
                .name = savedLine.ff50node.name,
                .id = id,
                .numChildren = numChildren,
                .children = std.ArrayList(node).init(allocator),
            } };
        },
        .ff70node => {
            return node{ .ff70node = ff70node{ .name = savedLine.ff70node.name } };
        },
        .ff4enode => {
            return node{ .ff4enode = ff4enode{} };
        },
    }
}

fn processU16(s: *status) u16 {
    defer s.current += 2;
    return std.mem.readIntSlice(u16, s.source[s.current..], std.builtin.Endian.Little);
}

fn processU32(s: *status) u32 {
    defer s.current += 4;
    return std.mem.readIntSlice(u32, s.source[s.current..], std.builtin.Endian.Little);
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isDecimal(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlphaNumeric(c: u8) bool {
    return isAlpha(c) or isDecimal(c);
}

fn errorInfo(s: *status) void {
    const dumpLine: usize = s.current / 16;
    std.debug.print("ERROR ON LINE: {any} (0x{x}), CHARACTER: {any}\n", .{ s.line, dumpLine, s.current });

    std.debug.print("Error at: \n", .{});
    var i: u8 = 20;
    while (i > 0) : (i -= 1) {
        std.debug.print("{x}, ", .{s.source[s.current - i]});
    }
    std.debug.print("|{x}|", .{s.source[s.current]});
    i = 1;
    while (i < 20) : (i += 1) {
        std.debug.print(", {x}", .{s.source[s.current + i]});
    }
    std.debug.print("\n", .{});
    std.debug.print("ELEMENT STACK:\n", .{});
    // for (s.result.items) |item| {
    //     std.debug.print("{any}\n", .{item});
    // }
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////  Test Area ////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// test "status struct advance works correctly" {
//     // Arrange
//     var testStatus = status.init("Hello");
//
//     // Act
//     const actualChar = testStatus.advance();
//
//     // Assert
//     try expect(testStatus.current == 1);
//     try expect(actualChar == 'H');
// }
//
// test "identifier test, not in map" {
//     // Arrange
//     var statusStruct = status.init(&[_]u8{ 255, 255, 5, 0, 0, 0, 72, 101, 108, 108, 111 });
//
//     // Act
//     const actual = try identifier(&statusStruct);
//
//     // Assert
//     try expectEqualStrings(actual, "Hello");
//     try expectEqualStrings(statusStruct.stringMap.items[0], "Hello");
//     try expect(statusStruct.peek() == 0);
// }
//
// test "identifier test, in map" {
//     // Arrange
//     var statusStruct = status.init(&[_]u8{ 0, 0 });
//     try statusStruct.stringMap.append("Hello");
//
//     // Act
//     const actual = try identifier(&statusStruct);
//
//     // Assert
//     try expectEqualStrings(actual, "Hello");
//     try expect(statusStruct.peek() == 0); // current is left at correct position
// }
//
// test "bool data" {
//     // Arrange
//     var statusStructTrue = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 });
//     var statusStructFalse = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 0 });
//
//     // Act
//     const dTypeT = dataTypeMap.get(try identifier(&statusStructTrue)).?;
//     const dataTrue = try processData(&statusStructTrue, dTypeT);
//
//     const dTypeF = dataTypeMap.get(try identifier(&statusStructFalse)).?;
//     const dataFalse = try processData(&statusStructFalse, dTypeF);
//
//     // Assert
//     try expect(@as(dataType, dataTrue) == dataType._bool);
//
//     try expect(dataTrue._bool == true);
//     try expect(dataFalse._bool == false);
//
//     try expect(statusStructTrue.peek() == 0); // current is left at correct position
// }
//
// test "sUInt8 data" {
//     // Arrange
//     var statusStruct11 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'U', 'I', 'n', 't', '8', 11 });
//     var statusStruct0 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'U', 'I', 'n', 't', '8', 0 });
//
//     // Act
//     const dType11 = dataTypeMap.get(try identifier(&statusStruct11)).?;
//     const data11 = try processData(&statusStruct11, dType11);
//
//     const dType0 = dataTypeMap.get(try identifier(&statusStruct0)).?;
//     const data0 = try processData(&statusStruct0, dType0);
//
//     // Assert
//     try expect(@as(dataType, data11) == dataType._sUInt8);
//
//     try expect(data11._sUInt8 == 11);
//     try expect(data0._sUInt8 == 0);
//
//     try expect(statusStruct11.peek() == 0); // current is left at correct position
// }
//
// test "sInt32 data" {
//     // Arrange
//     var statusStruct_3200 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'I', 'n', 't', '3', '2', 0x80, 0xf3, 0xff, 0xff }); // -3200
//     var statusStruct3210 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'I', 'n', 't', '3', '2', 0x8a, 0x0c, 0x00, 0x00 }); // 3210
//
//     // Act
//     const dType_3200 = dataTypeMap.get(try identifier(&statusStruct_3200)).?;
//     const data_3200 = try processData(&statusStruct_3200, dType_3200);
//
//     const dType3210 = dataTypeMap.get(try identifier(&statusStruct3210)).?;
//     const data3210 = try processData(&statusStruct3210, dType3210);
//
//     // Assert
//     try expect(@as(dataType, data_3200) == dataType._sInt32);
//
//     try expect(data_3200._sInt32 == -3200);
//     try expect(data3210._sInt32 == 3210);
//
//     try expect(statusStruct_3200.peek() == 0); // current is left at correct position
// }
//
// test "sFloat32 data" {
//     // Arrange
//     var statusStruct12345 = status.init(&[_]u8{ 255, 255, 8, 0, 0, 0, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0x66, 0xe6, 0xf6, 0x42 }); // 123.45
//     var statusStruct_1234 = status.init(&[_]u8{ 255, 255, 8, 0, 0, 0, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0xa4, 0x70, 0x45, 0xc1 }); // -1234
//
//     // Act
//     const dType12345 = dataTypeMap.get(try identifier(&statusStruct12345)).?;
//     const data12345 = try processData(&statusStruct12345, dType12345);
//
//     const dType_1234 = dataTypeMap.get(try identifier(&statusStruct_1234)).?;
//     const data_1234 = try processData(&statusStruct_1234, dType_1234);
//
//     // Assert
//     try std.testing.expect(@as(dataType, data12345) == dataType._sFloat32);
//
//     try expect(data12345._sFloat32 == 123.45);
//     try expect(data_1234._sFloat32 == -12.34);
//
//     try expect(statusStruct12345.peek() == 0); // current is left at correct position
// }
//
// test "sUInt64 data" {
//     // Arrange
//     const u64Name = &[_]u8{ 0xff, 0xff, 7, 0, 0, 0, 's', 'U', 'I', 'n', 't', '6', '4' };
//     const u64Value = &[_]u8{ 0x8d, 0x9d, 0x04, 0x65, 0x35, 0xcf, 0x73, 0x4a };
//     var statusStruct = status.init(u64Name ++ u64Value);
//
//     // Act
//     const dType = dataTypeMap.get(try identifier(&statusStruct)).?;
//     const data = try processData(&statusStruct, dType);
//
//     // Assert
//     try std.testing.expect(@as(dataType, data) == dataType._sUInt64);
//
//     try expect(data._sUInt64 == 5364859409363410317);
//
//     try expect(statusStruct.peek() == 0); // current is left at correct position
// }
//
// test "cDeltaString data" {
//     // Arrange
//     var statusStructHello = status.init(&[_]u8{ 255, 255, 12, 0, 0, 0, 'c', 'D', 'e', 'l', 't', 'a', 'S', 't', 'r', 'i', 'n', 'g', 255, 255, 5, 0, 0, 0, 'H', 'e', 'l', 'l', 'o' });
//     var statusStructExisting = status.init(&[_]u8{ 255, 255, 12, 0, 0, 0, 'c', 'D', 'e', 'l', 't', 'a', 'S', 't', 'r', 'i', 'n', 'g', 0, 0 });
//     try statusStructExisting.stringMap.append("iExist");
//
//     // Act
//     const dTypeHello = dataTypeMap.get(try identifier(&statusStructHello)).?;
//     const dataHello = try processData(&statusStructHello, dTypeHello);
//
//     const dTypeExisting = dataTypeMap.get(try identifier(&statusStructExisting)).?;
//     const dataExisting = try processData(&statusStructExisting, dTypeExisting);
//
//     // Assert
//     try expect(@as(dataType, dataHello) == dataType._cDeltaString);
//
//     try expectEqualStrings(dataHello._cDeltaString, "Hello");
//     try expectEqualStrings(dataExisting._cDeltaString, "iExist");
//
//     try expect(statusStructHello.peek() == 0); // current is left at correct position
// }
//
// test "ff41 parsing" {
//     // Arrange
//     const ff41bytes = &[_]u8{ 0xff, 0xff, 0x06, 0x00, 0x00, 0x00, 0x52, 0x58, 0x41, 0x78, 0x69, 0x73, 0x00, 0x00, 0x04, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0 };
//     var statusStruct = status.init(ff41bytes);
//     try statusStruct.stringMap.append("sInt32");
//
//     var expectedValues = std.ArrayList(dataUnion).init(allocator);
//     try expectedValues.append(dataUnion{ ._sInt32 = 1 });
//     try expectedValues.append(dataUnion{ ._sInt32 = 2 });
//     try expectedValues.append(dataUnion{ ._sInt32 = 3 });
//     try expectedValues.append(dataUnion{ ._sInt32 = 4 });
//
//     const expected = ff41node{ .name = "RXAxis", .numElements = 4, .dType = dataType._sInt32, .values = expectedValues };
//
//     // Act
//     const result = try processFF41(&statusStruct);
//
//     // Assert
//     try expectEqualStrings(result.name, expected.name);
//     try expect(result.numElements == expected.numElements);
//     // for (result.values.items) |value, i| {
//     //     try expect(value._sInt32 == expected.values.items[i]._sInt32);
//     // }
// }
//
// test "ff50 parsing" {
//     // Arrange
//     var statusStruct = status.init(&[_]u8{ 0xff, 0xff, 4, 0, 0, 0, 'f', 'o', 'o', 'd', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 });
//     const expected = ff50node{ .name = "food", .id = 375192228, .numChildren = 1 };
//
//     // Act
//     const ff50 = try processFF50(&statusStruct);
//
//     // Assert
//     try expect(ff50.id == expected.id);
//     try expectEqualStrings(ff50.name, expected.name);
//     try expect(ff50.numChildren == expected.numChildren);
// }
//
// test "ff56 parsing" {
//     // Arrange
//     var statusStruct = status.init(&[_]u8{ 0xff, 0xff, 4, 0, 0, 0, 'f', 'o', 'o', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 });
//     const expected = ff56node{ .name = "food", .dType = dataType._bool, .value = dataUnion{ ._bool = true } };
//
//     // Act
//     const ff56 = try processFF56(&statusStruct);
//
//     // Assert
//     try expectEqualStrings(ff56.name, expected.name);
//     try expect(ff56.value._bool == expected.value._bool);
// }
//
// test "ff70 parsing" {
//     // Arrange
//     const SERZ = &[_]u8{ 'S', 'E', 'R', 'Z' };
//     const unknownU32 = &[_]u8{ 0, 0, 1, 0 };
//     const ff50bytes = &[_]u8{ 0xff, 0x50, 0xff, 0xff, 5, 0, 0, 0, 'f', 'i', 'r', 's', 't', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 };
//     const ff56bytes = &[_]u8{ 0xff, 0x56, 0xff, 0xff, 3, 0, 0, 0, 's', 'n', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 };
//     const ff70bytes = &[_]u8{ 0xff, 0x70, 0, 0 };
//     var testBytes = status.init(SERZ ++ unknownU32 ++ ff50bytes ++ ff56bytes ++ ff70bytes);
//
//     const expected = &[_]node{
//         node{ .ff50node = ff50node{ .name = "first", .id = 375192228, .numChildren = 1 } },
//         node{ .ff56node = ff56node{ .name = "snd", .dType = dataType._bool, .value = dataUnion{ ._bool = true } } },
//         node{ .ff70node = ff70node{ .name = "first" } },
//     };
//
//     // Act
//     // const result = try parse(&testBytes);
//
//     // Assert
//     try expectEqualStrings(result.items[2].ff70node.name, expected[2].ff70node.name);
// }
//
// test "parse function" {
//     // Arrange
//     const SERZ = &[_]u8{ 'S', 'E', 'R', 'Z' };
//     const unknownU32 = &[_]u8{ 0, 0, 1, 0 };
//     const ff50bytes = &[_]u8{ 0xff, 0x50, 0xff, 0xff, 5, 0, 0, 0, 'f', 'i', 'r', 's', 't', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 };
//     const ff56bytes = &[_]u8{ 0xff, 0x56, 0xff, 0xff, 3, 0, 0, 0, 's', 'n', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 };
//     var testBytes = status.init(SERZ ++ unknownU32 ++ ff50bytes ++ ff56bytes);
//
//     const expected = &[_]node{
//         node{ .ff50node = ff50node{ .name = "first", .id = 375192228, .numChildren = 1 } },
//         node{ .ff56node = ff56node{ .name = "snd", .dType = dataType._bool, .value = dataUnion{ ._bool = true } } },
//     };
//
//     // Act
//     const result = try parse(&testBytes);
//
//     // Assert
//     try expectEqualStrings(result.items[0].ff50node.name, expected[0].ff50node.name);
//     try expect(result.items[0].ff50node.id == expected[0].ff50node.id);
//     try expect(result.items[0].ff50node.numChildren == expected[0].ff50node.numChildren);
//
//     try expectEqualStrings(result.items[1].ff56node.name, expected[1].ff56node.name);
//     try expect(result.items[1].ff56node.value._bool == expected[1].ff56node.value._bool);
// }

pub fn main() !void {
    const size_limit = std.math.maxInt(u32);
    var file = try std.fs.cwd().openFile("testFiles/Scenario.bin", .{});

    const testBytes = try file.readToEndAlloc(allocator, size_limit);
    var testStatus = status.init(testBytes);
    //std.debug.print("Total Nodes: {any}\n", .{(try parse(&testStatus)).items.len});
    const nde = try parse(&testStatus);
    std.debug.print("{any}\n\n", .{nde});
    std.debug.print("{any}\n\n", .{nde.ff50node.children.items});
}
