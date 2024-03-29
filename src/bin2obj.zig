const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const n = @import("node.zig");

const node = n.node;
const ff41node = n.ff41node;
const ff43node = n.ff43node;
const ff4enode = n.ff4enode;
const ff50node = n.ff50node;
const ff52node = n.ff52node;
const ff56node = n.ff56node;
const ff70node = n.ff70node;
const dataType = n.dataType;
const dataUnion = n.dataUnion;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();

const stringContext = enum {
    NAME,
    DTYPE,
    VALUE,
};

const status = struct {
    start: usize,
    current: usize,
    line: usize,
    source: []const u8,
    stringMap: std.ArrayList([]const u8),
    savedTokenList: [255]node, // one less than 0xFF to avoid this important byte pattern
    savedTokenListIdx: usize,
    result: std.ArrayList(node),

    fn init(src: []const u8) status {
        return status{
            .start = 0,
            .current = 0,
            .line = 0,
            .source = src,
            .stringMap = std.ArrayList([]const u8).init(allocator),
            .savedTokenList = undefined,
            .savedTokenListIdx = 0,
            .result = std.ArrayList(node).init(allocator),
        };
    }

    fn advance(self: *status) u8 {
        defer self.current += 1;
        return self.source[self.current];
    }

    fn peek(self: *status) u8 {
        return if (self.isAtEnd()) 0 else self.source[self.current];
    }

    fn peekNext(self: *status) u8 {
        return if (self.current + 1 >= self.source.len) 0 else self.source[self.current + 1];
    }

    fn isAtEnd(self: *status) bool {
        return self.current >= self.source.len;
    }
};

const errors = error{
    InvalidNodeType,
    TooManyChildren,
};

pub fn parse(inputBytes: []const u8) ![]const node {
    var stat = status.init(inputBytes);
    var s = &stat;
    errdefer {
        errorInfo(s);
    }

    try expectEqualStrings("SERZ", s.source[0..4]);
    s.current += 4;
    _ = processU32(s);

    while (!s.isAtEnd()) {
        if (s.source[s.current] == 0xff) {
            s.current += 1;
            switch (s.source[s.current]) {
                0x41 => {
                    s.current += 1;
                    const tok = try processFF41(s);
                    try s.result.append(node{ .ff41node = tok });
                    s.savedTokenList[s.savedTokenListIdx] = node{ .ff41node = tok };
                },
                0x43 => {
                    s.current += 6;
                    if (s.result.items.len > 0) {
                        s.result.items[s.result.items.len - 1].ff50node.children = 1;
                    }
                },
                0x4e => {
                    s.current += 1;
                    try s.result.append(node{ .ff4enode = ff4enode{} });
                    s.savedTokenList[s.savedTokenListIdx] = node{ .ff4enode = ff4enode{} };
                },
                0x50 => {
                    s.current += 1;
                    const tok = try processFF50(s);
                    try s.result.append(node{ .ff50node = tok });
                    s.savedTokenList[s.savedTokenListIdx] = node{ .ff50node = tok };
                },
                0x52 => {
                    s.current += 1;
                    const tok = try processFF52(s);
                    try s.result.append(node{ .ff52node = tok });
                    s.savedTokenList[s.savedTokenListIdx] = node{ .ff52node = tok };
                },
                0x56 => {
                    s.current += 1;
                    const tok = try processFF56(s);
                    try s.result.append(node{ .ff56node = tok });
                    s.savedTokenList[s.savedTokenListIdx] = node{ .ff56node = tok };
                },
                0x70 => {
                    s.current += 1;
                    const tok = try processFF70(s);
                    try s.result.append(node{ .ff70node = tok });
                    s.savedTokenList[s.savedTokenListIdx] = node{ .ff70node = tok };
                },
                else => return errors.InvalidNodeType,
            }
            s.savedTokenListIdx = (s.savedTokenListIdx + 1) % 255;
        } else {
            try s.result.append(try processSavedLine(s));
        }
        s.line += 1;
    }
    return s.result.items;
}

fn identifier(s: *status, ctx: stringContext) ![]const u8 {
    var retArray = std.ArrayList(u8).init(allocator);
    if (s.source[s.current] == 0xFF and s.source[s.current + 1] == 0xFF) // New string
    {
        s.current += 2;

        const strLen = std.mem.readIntSlice(u32, s.source[s.current..], std.builtin.Endian.Little);

        s.current += 4;

        var str = s.source[s.current..(s.current + strLen)];
        if (ctx == stringContext.NAME) { // Replace '-' with '::' in names only
            for (str) |_, i| {
                if (str[i] == ':' and str[i+1] == ':') {
                    try retArray.appendSlice("-");
                    i += 1;
                } else {
                    try retArray.append(str[i]);
                }
            }
        } else {
            try retArray.appendSlice(str);
        }

        try s.stringMap.append(retArray.items);
        defer s.current += strLen;

        return if (ctx == stringContext.NAME and retArray.items.len == 0) "e" else retArray.items;
    }
    const strIdx = std.mem.readIntSlice(u16, s.source[s.current..], std.builtin.Endian.Little);
    s.current += 2;

    const savedName = s.stringMap.items[strIdx];

    return if (ctx == stringContext.NAME and savedName.len == 0) "e" else savedName;
}

fn processData(s: *status, dType: dataType) !dataUnion {
    return switch (dType) {
        dataType._bool => try processBool(s),
        dataType._sUInt8 => processSUInt8(s),
        dataType._sInt16 => processSInt16(s),
        dataType._sInt32 => processSInt32(s),
        dataType._sUInt32 => processSUInt32(s),
        dataType._sUInt64 => processU64(s),
        dataType._sFloat32 => try processSFloat32(s),
        dataType._cDeltaString => processCDeltaString(s),
    };
}

fn processBool(s: *status) !dataUnion {
    defer s.current += 1;
    return switch (s.source[s.current]) {
        0 => dataUnion{ ._bool = false },
        else => dataUnion{ ._bool = true },
        // else => errors.InvalidNodeType,
    };
}

fn processSUInt8(s: *status) dataUnion {
    defer s.current += 1;
    const val = s.source[s.current];
    return dataUnion{ ._sUInt8 = val };
}

// TODO: test
fn processSInt16(s: *status) dataUnion {
    defer s.current += 2;
    const val = std.mem.readIntSlice(i16, s.source[s.current..], std.builtin.Endian.Little);
    return dataUnion{ ._sInt16 = val };
}

fn processSInt32(s: *status) dataUnion {
    defer s.current += 4;
    const val = std.mem.readIntSlice(i32, s.source[s.current..], std.builtin.Endian.Little);
    return dataUnion{ ._sInt32 = val };
}

// TODO: test
fn processSUInt32(s: *status) dataUnion {
    defer s.current += 4;
    const val = std.mem.readIntSlice(u32, s.source[s.current..], std.builtin.Endian.Little);
    return dataUnion{ ._sUInt32 = val };
}

fn processU64(s: *status) dataUnion {
    defer s.current += 8;
    const val = std.mem.readIntSlice(u64, s.source[s.current..], std.builtin.Endian.Little);
    return dataUnion{ ._sUInt64 = val };
}

fn processSFloat32(s: *status) !dataUnion {
    defer s.current += 4;
    const val = @bitCast(f32, std.mem.readIntSlice(u32, s.source[s.current..], std.builtin.Endian.Little));
    return dataUnion{ ._sFloat32 = val };
}

fn processCDeltaString(s: *status) !dataUnion {
    var result = std.ArrayList(u8).init(allocator);
    const str = try identifier(s, stringContext.VALUE);
    try result.appendSlice(str);
    return dataUnion{ ._cDeltaString = result.items };
}

fn processFF41(s: *status) !ff41node {
    const nodeName = try identifier(s, stringContext.NAME);
    const elemType = n.dataTypeMap.get(try identifier(s, stringContext.DTYPE)).?;
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
    const nodeName = try identifier(s, stringContext.NAME);
    const id = processU32(s);
    const children = processU32(s);

    return ff50node{
        .name = nodeName,
        .id = id,
        .children = children,
    };
}

// TODO: Add Test
fn processFF52(s: *status) !ff52node {
    const nodeName = try identifier(s, stringContext.NAME);
    const value = processU32(s);

    return ff52node{
        .name = nodeName,
        .value = value,
    };
}

fn processFF56(s: *status) !ff56node {
    const nodeName = try identifier(s, stringContext.NAME);
    const dTypeString = try identifier(s, stringContext.DTYPE);
    const dType = n.dataTypeMap.get(dTypeString);
    const data = try processData(s, dType.?);

    return ff56node{
        .name = nodeName,
        .dType = dType.?,
        .value = data,
    };
}

fn processFF70(s: *status) !ff70node {
    // const nodeStr = processU16(s);
    const nodeName = try identifier(s, stringContext.NAME);
    // const nodeName = s.stringMap.items[nodeStr];
    return ff70node{
        .name = nodeName,
    };
}

fn processSavedLine(s: *status) !node {
    if (s.source[s.current] > s.savedTokenList.len) {
        return error.InvalidFileError;
    }
    const savedLine = s.savedTokenList[s.source[s.current]];
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
            const id = processU32(s);
            const children = processU32(s);
            if (children > 100) {
                s.current -= 8;
                return errors.TooManyChildren;
            }
            return node{ .ff50node = ff50node{
                .name = savedLine.ff50node.name,
                .id = id,
                .children = children,
            } };
        },
        .ff52node => {
            const value = processU32(s);
            return node{ .ff52node = ff52node{
                .name = savedLine.ff52node.name,
                .value = value,
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
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////  Test Area ////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

test "status struct advance works correctly" {
    // Arrange
    var testStatus = status.init("Hello");

    // Act
    const actualChar = testStatus.advance();

    // Assert
    try expect(testStatus.current == 1);
    try expect(actualChar == 'H');
}

test "identifier test, not in map" {
    // Arrange
    var statusStruct = status.init(&[_]u8{ 255, 255, 5, 0, 0, 0, 72, 101, 108, 108, 111 });

    // Act
    const actual = try identifier(&statusStruct, stringContext.NAME);

    // Assert
    try expectEqualStrings(actual, "Hello");
    try expectEqualStrings(statusStruct.stringMap.items[0], "Hello");
    try expect(statusStruct.peek() == 0);
}

test "identifier test, in map" {
    // Arrange
    var statusStruct = status.init(&[_]u8{ 0, 0 });
    try statusStruct.stringMap.append("Hello");

    // Act
    const actual = try identifier(&statusStruct, stringContext.NAME);

    // Assert
    try expectEqualStrings(actual, "Hello");
    try expect(statusStruct.peek() == 0); // current is left at correct position
}

test "bool data" {
    // Arrange
    var statusStructTrue = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 });
    var statusStructFalse = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 0 });

    // Act
    const dTypeT = n.dataTypeMap.get(try identifier(&statusStructTrue, stringContext.NAME)).?;
    const dataTrue = try processData(&statusStructTrue, dTypeT);

    const dTypeF = n.dataTypeMap.get(try identifier(&statusStructFalse, stringContext.NAME)).?;
    const dataFalse = try processData(&statusStructFalse, dTypeF);

    // Assert
    try expect(@as(dataType, dataTrue) == dataType._bool);

    try expect(dataTrue._bool == true);
    try expect(dataFalse._bool == false);

    try expect(statusStructTrue.peek() == 0); // current is left at correct position
}

test "sUInt8 data" {
    // Arrange
    var statusStruct11 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'U', 'I', 'n', 't', '8', 11 });
    var statusStruct0 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'U', 'I', 'n', 't', '8', 0 });

    // Act
    const dType11 = n.dataTypeMap.get(try identifier(&statusStruct11, stringContext.NAME)).?;
    const data11 = try processData(&statusStruct11, dType11);

    const dType0 = n.dataTypeMap.get(try identifier(&statusStruct0, stringContext.NAME)).?;
    const data0 = try processData(&statusStruct0, dType0);

    // Assert
    try expect(@as(dataType, data11) == dataType._sUInt8);

    try expect(data11._sUInt8 == 11);
    try expect(data0._sUInt8 == 0);

    try expect(statusStruct11.peek() == 0); // current is left at correct position
}

test "sInt32 data" {
    // Arrange
    var statusStruct_3200 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'I', 'n', 't', '3', '2', 0x80, 0xf3, 0xff, 0xff }); // -3200
    var statusStruct3210 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'I', 'n', 't', '3', '2', 0x8a, 0x0c, 0x00, 0x00 }); // 3210

    // Act
    const dType_3200 = n.dataTypeMap.get(try identifier(&statusStruct_3200, stringContext.NAME)).?;
    const data_3200 = try processData(&statusStruct_3200, dType_3200);

    const dType3210 = n.dataTypeMap.get(try identifier(&statusStruct3210, stringContext.NAME)).?;
    const data3210 = try processData(&statusStruct3210, dType3210);

    // Assert
    try expect(@as(dataType, data_3200) == dataType._sInt32);

    try expect(data_3200._sInt32 == -3200);
    try expect(data3210._sInt32 == 3210);

    try expect(statusStruct_3200.peek() == 0); // current is left at correct position
}

test "sFloat32 data" {
    // Arrange
    var statusStruct12345 = status.init(&[_]u8{ 255, 255, 8, 0, 0, 0, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0x66, 0xe6, 0xf6, 0x42 }); // 123.45
    var statusStruct_1234 = status.init(&[_]u8{ 255, 255, 8, 0, 0, 0, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0xa4, 0x70, 0x45, 0xc1 }); // -1234
    var statusStruct_s1 = status.init(&[_]u8{ 255, 255, 8, 0, 0, 0, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0x4c, 0xc3, 0xc6, 0xc0 }); // -1234
    var statusStruct_s2 = status.init(&[_]u8{ 255, 255, 8, 0, 0, 0, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0xe4, 0x65, 0xfd, 0x3e }); // -1234

    // Act
    const dType12345 = n.dataTypeMap.get(try identifier(&statusStruct12345, stringContext.NAME)).?;
    const data12345 = try processData(&statusStruct12345, dType12345);

    const dType_1234 = n.dataTypeMap.get(try identifier(&statusStruct_1234, stringContext.NAME)).?;
    const data_1234 = try processData(&statusStruct_1234, dType_1234);

    const dType_s1 = n.dataTypeMap.get(try identifier(&statusStruct_s1, stringContext.NAME)).?;
    const data_s1 = try processData(&statusStruct_s1, dType_s1);

    const dType_s2 = n.dataTypeMap.get(try identifier(&statusStruct_s2, stringContext.NAME)).?;
    const data_s2 = try processData(&statusStruct_s2, dType_s2);

    // Assert
    try std.testing.expect(@as(dataType, data12345) == dataType._sFloat32);

    try expect(data12345._sFloat32 == 123.45);
    try expect(data_1234._sFloat32 == -12.34);
    try expect(data_s1._sFloat32 == -6.21134);
    try expect(data_s2._sFloat32 == 0.4949180);

    try expect(statusStruct12345.peek() == 0); // current is left at correct position
}

test "sUInt64 data" {
    // Arrange
    const u64Name = &[_]u8{ 0xff, 0xff, 7, 0, 0, 0, 's', 'U', 'I', 'n', 't', '6', '4' };
    const u64Value = &[_]u8{ 0x8d, 0x9d, 0x04, 0x65, 0x35, 0xcf, 0x73, 0x4a };
    var statusStruct = status.init(u64Name ++ u64Value);

    // Act
    const dType = n.dataTypeMap.get(try identifier(&statusStruct, stringContext.DTYPE)).?;
    const data = try processData(&statusStruct, dType);

    // Assert
    try std.testing.expect(@as(dataType, data) == dataType._sUInt64);

    try expect(data._sUInt64 == 5364859409363410317);

    try expect(statusStruct.peek() == 0); // current is left at correct position
}

test "cDeltaString data" {
    // Arrange
    var statusStructHello = status.init(&[_]u8{ 255, 255, 12, 0, 0, 0, 'c', 'D', 'e', 'l', 't', 'a', 'S', 't', 'r', 'i', 'n', 'g', 255, 255, 5, 0, 0, 0, 'H', 'e', 'l', 'l', 'o' });
    var statusStructExisting = status.init(&[_]u8{ 255, 255, 12, 0, 0, 0, 'c', 'D', 'e', 'l', 't', 'a', 'S', 't', 'r', 'i', 'n', 'g', 0, 0 });
    try statusStructExisting.stringMap.append("iExist");

    // Act
    const dTypeHello = n.dataTypeMap.get(try identifier(&statusStructHello, stringContext.DTYPE)).?;
    const dataHello = try processData(&statusStructHello, dTypeHello);

    const dTypeExisting = n.dataTypeMap.get(try identifier(&statusStructExisting, stringContext.DTYPE)).?;
    const dataExisting = try processData(&statusStructExisting, dTypeExisting);

    // Assert
    try expect(@as(dataType, dataHello) == dataType._cDeltaString);

    try expectEqualStrings(dataHello._cDeltaString, "Hello");
    try expectEqualStrings(dataExisting._cDeltaString, "iExist");

    try expect(statusStructHello.peek() == 0); // current is left at correct position
}

test "ff41 parsing" {
    // Arrange
    const ff41bytes = &[_]u8{ 0xff, 0xff, 0x06, 0x00, 0x00, 0x00, 0x52, 0x58, 0x41, 0x78, 0x69, 0x73, 0x00, 0x00, 0x04, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0 };
    var statusStruct = status.init(ff41bytes);
    try statusStruct.stringMap.append("sInt32");

    var expectedValues = std.ArrayList(dataUnion).init(allocator);
    try expectedValues.append(dataUnion{ ._sInt32 = 1 });
    try expectedValues.append(dataUnion{ ._sInt32 = 2 });
    try expectedValues.append(dataUnion{ ._sInt32 = 3 });
    try expectedValues.append(dataUnion{ ._sInt32 = 4 });

    const expected = ff41node{ .name = "RXAxis", .numElements = 4, .dType = dataType._sInt32, .values = expectedValues };

    // Act
    const result = try processFF41(&statusStruct);

    // Assert
    try expectEqualStrings(result.name, expected.name);
    try expect(result.numElements == expected.numElements);
    for (result.values.items) |value, i| {
        try expect(value._sInt32 == expected.values.items[i]._sInt32);
    }
}

test "ff50 parsing" {
    // Arrange
    var statusStruct = status.init(&[_]u8{ 0xff, 0xff, 4, 0, 0, 0, 'f', 'o', 'o', 'd', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 });
    const expected = ff50node{ .name = "food", .id = 375192228, .children = 1 };

    // Act
    const ff50 = try processFF50(&statusStruct);

    // Assert
    try expect(ff50.id == expected.id);
    try expectEqualStrings(ff50.name, expected.name);
    try expect(ff50.children == expected.children);
}

test "ff56 parsing" {
    // Arrange
    var statusStruct = status.init(&[_]u8{ 0xff, 0xff, 4, 0, 0, 0, 'f', 'o', 'o', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 });
    const expected = ff56node{ .name = "food", .dType = dataType._bool, .value = dataUnion{ ._bool = true } };

    // Act
    const ff56 = try processFF56(&statusStruct);

    // Assert
    try expectEqualStrings(ff56.name, expected.name);
    try expect(ff56.value._bool == expected.value._bool);
}

test "ff56 parsing, empty name" {
    // Arrange
    var statusStruct = status.init(&[_]u8{ 0xff, 0xff, 0, 0, 0, 0, 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 });
    const expected = ff56node{ .name = "e", .dType = dataType._bool, .value = dataUnion{ ._bool = true } };

    // Act
    const ff56 = try processFF56(&statusStruct);

    // Assert
    try expectEqualStrings(ff56.name, expected.name);
    try expect(statusStruct.stringMap.items[0].len == 0); // 'e' is substituted for empty name but not added to saved string list
    try expect(ff56.value._bool == expected.value._bool);
}

test "ff70 parsing" {
    // Arrange
    const SERZ = &[_]u8{ 'S', 'E', 'R', 'Z' };
    const unknownU32 = &[_]u8{ 0, 0, 1, 0 };
    const ff50bytes = &[_]u8{ 0xff, 0x50, 0xff, 0xff, 5, 0, 0, 0, 'f', 'i', 'r', 's', 't', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 };
    const ff56bytes = &[_]u8{ 0xff, 0x56, 0xff, 0xff, 3, 0, 0, 0, 's', 'n', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 };
    const ff70bytes = &[_]u8{ 0xff, 0x70, 0, 0 };
    var testBytes = SERZ ++ unknownU32 ++ ff50bytes ++ ff56bytes ++ ff70bytes;

    const expected = &[_]node{
        node{ .ff50node = ff50node{ .name = "first", .id = 375192228, .children = 1 } },
        node{ .ff56node = ff56node{ .name = "snd", .dType = dataType._bool, .value = dataUnion{ ._bool = true } } },
        node{ .ff70node = ff70node{ .name = "first" } },
    };

    // Act
    const result = try parse(testBytes);

    // Assert
    try expectEqualStrings(result[2].ff70node.name, expected[2].ff70node.name);
}

test "parse function" {
    // Arrange
    const SERZ = &[_]u8{ 'S', 'E', 'R', 'Z' };
    const unknownU32 = &[_]u8{ 0, 0, 1, 0 };
    const ff50bytes = &[_]u8{ 0xff, 0x50, 0xff, 0xff, 5, 0, 0, 0, 'f', 'i', 'r', 's', 't', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 };
    const ff56bytes = &[_]u8{ 0xff, 0x56, 0xff, 0xff, 3, 0, 0, 0, 's', 'n', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 };
    var testBytes = SERZ ++ unknownU32 ++ ff50bytes ++ ff56bytes;

    const expected = &[_]node{
        node{ .ff50node = ff50node{ .name = "first", .id = 375192228, .children = 1 } },
        node{ .ff56node = ff56node{ .name = "snd", .dType = dataType._bool, .value = dataUnion{ ._bool = true } } },
    };

    // Act
    const result = try parse(testBytes);

    // Assert
    try expectEqualStrings(result[0].ff50node.name, expected[0].ff50node.name);
    try expect(result[0].ff50node.id == expected[0].ff50node.id);
    try expect(result[0].ff50node.children == expected[0].ff50node.children);

    try expectEqualStrings(result[1].ff56node.name, expected[1].ff56node.name);
    try expect(result[1].ff56node.value._bool == expected[1].ff56node.value._bool);
}