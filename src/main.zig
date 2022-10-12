const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();

const status = struct {
    start: usize,
    current: usize,
    line: usize,
    source: []const u8,
    stringMap: std.ArrayList([]const u8),
    result: std.ArrayList(token),

    pub fn init(src: []const u8) status {
        return status{
            .start = 0,
            .current = 0,
            .line = 0,
            .source = src,
            .stringMap = std.ArrayList([]const u8).init(allocator),
            .result = std.ArrayList(token).init(allocator),
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
    InvalidFileError,
};

const keywords = std.StringHashMap(dataType).init(allocator);
const dataTypeMap = std.ComptimeStringMap(dataType, .{
    .{ "bool", ._bool },
    .{ "sUInt8", ._sUInt8 },
    .{ "sInt32", ._sInt32 },
    .{ "sUInt64", ._sUInt64 },
    .{ "sFloat32", ._sFloat32 },
    .{ "cDeltaString", ._cDeltaString },
});

const dataType = enum {
    _bool,
    _sUInt8,
    _sInt32,
    _sUInt64,
    _sFloat32,
    _cDeltaString,
};

const dataUnion = union(dataType) {
    _bool: bool,
    _sUInt8: u8,
    _sInt32: i32,
    _sUInt64: u64,
    _sFloat32: f32,
    _cDeltaString: []const u8,
};

const ff41token = struct {
    name: []const u8,
    numElements: u8,
    elementType: dataType,
    values: std.ArrayList(dataUnion),
};

const ff50token = struct {
    name: []const u8,
    id: u32,
    children: u32,
};

const ff56token = struct {
    name: []const u8,
    value: dataUnion,
};

const ff70token = struct {
    name: []const u8,
};

const token = union(enum) {
    ff41token: ff41token,
    ff50token: ff50token,
    ff56token: ff56token,
    ff70token: ff70token,
};

pub fn parse(s: *status) !std.ArrayList(token) {
    errdefer {
        std.debug.print("ERROR ON LINE: {any}, CHARACTER: {any}\n", .{ s.line, s.current });

        std.debug.print("Error at: \n", .{});
        var i: u8 = 20;
        while (i > 0) : (i -= 1) {
            std.debug.print("{x}, ", .{s.source[s.current - i]});
        }
        std.debug.print("|{x}|", .{s.source[s.current]});
        i = 1;
        while (i < 20) : (i += 1) {
            std.debug.print(", {x}", .{s.source[s.current - i]});
        }
        std.debug.print("\n", .{});
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
                    try s.result.append(token{ .ff41token = try processFF41(s) });
                },
                0x50 => {
                    s.current += 1;
                    try s.result.append(token{ .ff50token = try processFF50(s) });
                },
                0x56 => {
                    s.current += 1;
                    try s.result.append(token{ .ff56token = try processFF56(s) });
                },
                0x70 => {
                    s.current += 1;
                    try s.result.append(token{ .ff70token = try processFF70(s) });
                },
                else => return errors.InvalidFileError,
            }
        } else {
            try s.result.append(try processSavedLine(s));
            return s.result;
        }
        if (s.line < 255) s.line += 1;
    }
    return s.result;
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

fn processData(s: *status, dataTypeStr: []const u8) !dataUnion {
    return switch (dataTypeMap.get(dataTypeStr).?) {
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
    const val = std.mem.readIntSlice(u8, s.source[s.current..], std.builtin.Endian.Little);
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

fn processFF41(s: *status) !ff41token {
    const tokenName = try identifier(s);
    const elemTypeStr = try identifier(s);
    const elemType = dataTypeMap.get(elemTypeStr).?;
    const numElements = s.source[s.current];
    s.current += 1;

    var elemValues = std.ArrayList(dataUnion).init(allocator);
    var i: u8 = 0;
    while (i < numElements) : (i += 1) {
        try elemValues.append(try processData(s, elemTypeStr));
    }

    return ff41token{
        .name = tokenName,
        .elementType = elemType,
        .numElements = numElements,
        .values = elemValues,
    };
}

fn processFF50(s: *status) !ff50token {
    const tokenName = try identifier(s);
    const id = processU32(s);
    const children = processU32(s);

    return ff50token{
        .name = tokenName,
        .id = id,
        .children = children,
    };
}

fn processFF56(s: *status) !ff56token {
    const tokenName = try identifier(s);
    const dataTypeStr = try identifier(s);
    const data = try processData(s, dataTypeStr);

    return ff56token{
        .name = tokenName,
        .value = data,
    };
}

fn processFF70(s: *status) !ff70token {
    const tokenStr = processU16(s);
    const tokenName = s.stringMap.items[tokenStr];
    return ff70token{
        .name = tokenName,
    };
}

fn processSavedLine(s: *status) !token {
    const savedLine = s.result.items[s.source[s.current]];
    return savedLine;
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
    const actual = try identifier(&statusStruct);

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
    const actual = try identifier(&statusStruct);

    // Assert
    try expectEqualStrings(actual, "Hello");
    try expect(statusStruct.peek() == 0); // current is left at correct position
}

test "bool data" {
    // Arrange
    var statusStructTrue = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 });
    var statusStructFalse = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 0 });

    // Act
    const dTypeT = try identifier(&statusStructTrue);
    const dataTrue = try processData(&statusStructTrue, dTypeT);

    const dTypeF = try identifier(&statusStructFalse);
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
    const dType11 = try identifier(&statusStruct11);
    const data11 = try processData(&statusStruct11, dType11);

    const dType0 = try identifier(&statusStruct0);
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
    const dType_3200 = try identifier(&statusStruct_3200);
    const data_3200 = try processData(&statusStruct_3200, dType_3200);

    const dType3210 = try identifier(&statusStruct3210);
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

    // Act
    const dType12345 = try identifier(&statusStruct12345);
    const data12345 = try processData(&statusStruct12345, dType12345);

    const dType_1234 = try identifier(&statusStruct_1234);
    const data_1234 = try processData(&statusStruct_1234, dType_1234);

    // Assert
    try std.testing.expect(@as(dataType, data12345) == dataType._sFloat32);

    try expect(data12345._sFloat32 == 123.45);
    try expect(data_1234._sFloat32 == -12.34);

    try expect(statusStruct12345.peek() == 0); // current is left at correct position
}

test "sUInt64 data" {
    // Arrange
    const u64Name = &[_]u8{ 0xff, 0xff, 7, 0, 0, 0, 's', 'U', 'I', 'n', 't', '6', '4' };
    const u64Value = &[_]u8{ 0x8d, 0x9d, 0x04, 0x65, 0x35, 0xcf, 0x73, 0x4a };
    var statusStruct = status.init(u64Name ++ u64Value);

    // Act
    const dType = try identifier(&statusStruct);
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
    const dTypeHello = try identifier(&statusStructHello);
    const dataHello = try processData(&statusStructHello, dTypeHello);

    const dTypeExisting = try identifier(&statusStructExisting);
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

    const expected = ff41token{ .name = "RXAxis", .numElements = 4, .elementType = dataType._sInt32, .values = expectedValues };

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
    const expected = ff50token{ .name = "food", .id = 375192228, .children = 1 };

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
    const expected = ff56token{ .name = "food", .value = dataUnion{ ._bool = true } };

    // Act
    const ff56 = try processFF56(&statusStruct);

    // Assert
    try expectEqualStrings(ff56.name, expected.name);
    try expect(ff56.value._bool == expected.value._bool);
}

test "ff70 parsing" {
    // Arrange
    const SERZ = &[_]u8{ 'S', 'E', 'R', 'Z' };
    const unknownU32 = &[_]u8{ 0, 0, 1, 0 };
    const ff50bytes = &[_]u8{ 0xff, 0x50, 0xff, 0xff, 5, 0, 0, 0, 'f', 'i', 'r', 's', 't', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 };
    const ff56bytes = &[_]u8{ 0xff, 0x56, 0xff, 0xff, 3, 0, 0, 0, 's', 'n', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 };
    const ff70bytes = &[_]u8{ 0xff, 0x70, 0, 0 };
    var testBytes = status.init(SERZ ++ unknownU32 ++ ff50bytes ++ ff56bytes ++ ff70bytes);

    const expected = &[_]token{
        token{ .ff50token = ff50token{ .name = "first", .id = 375192228, .children = 1 } },
        token{ .ff56token = ff56token{ .name = "snd", .value = dataUnion{ ._bool = true } } },
        token{ .ff70token = ff70token{ .name = "first" } },
    };

    // Act
    const result = try parse(&testBytes);

    // Assert
    try expectEqualStrings(result.items[2].ff70token.name, expected[2].ff70token.name);
}

test "parse function" {
    // Arrange
    const SERZ = &[_]u8{ 'S', 'E', 'R', 'Z' };
    const unknownU32 = &[_]u8{ 0, 0, 1, 0 };
    const ff50bytes = &[_]u8{ 0xff, 0x50, 0xff, 0xff, 5, 0, 0, 0, 'f', 'i', 'r', 's', 't', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 };
    const ff56bytes = &[_]u8{ 0xff, 0x56, 0xff, 0xff, 3, 0, 0, 0, 's', 'n', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 };
    var testBytes = status.init(SERZ ++ unknownU32 ++ ff50bytes ++ ff56bytes);

    const expected = &[_]token{
        token{ .ff50token = ff50token{ .name = "first", .id = 375192228, .children = 1 } },
        token{ .ff56token = ff56token{ .name = "snd", .value = dataUnion{ ._bool = true } } },
    };

    // Act
    const result = try parse(&testBytes);

    // Assert
    try expectEqualStrings(result.items[0].ff50token.name, expected[0].ff50token.name);
    try expect(result.items[0].ff50token.id == expected[0].ff50token.id);
    try expect(result.items[0].ff50token.children == expected[0].ff50token.children);

    try expectEqualStrings(result.items[1].ff56token.name, expected[1].ff56token.name);
    try expect(result.items[1].ff56token.value._bool == expected[1].ff56token.value._bool);
}

test "saved line retrieval" {
    // Arrange
    const SERZ = &[_]u8{ 'S', 'E', 'R', 'Z' };
    const unknownU32 = &[_]u8{ 0, 0, 1, 0 };
    const ff50bytes = &[_]u8{ 0xff, 0x50, 0xff, 0xff, 5, 0, 0, 0, 'f', 'i', 'r', 's', 't', 0xa4, 0xfa, 0x5c, 0x16, 1, 0, 0, 0 };
    const ff56bytes = &[_]u8{ 0xff, 0x56, 0xff, 0xff, 3, 0, 0, 0, 's', 'n', 'd', 0xff, 0xff, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 };
    const savedBytes = &[_]u8{0x01};
    var testBytes = status.init(SERZ ++ unknownU32 ++ ff50bytes ++ ff56bytes ++ savedBytes);

    const expected = token{ .ff56token = ff56token{ .name = "snd", .value = dataUnion{ ._bool = true } } };

    // Act
    const result = try parse(&testBytes);

    // Assert
    try expectEqualStrings(result.items[2].ff56token.name, expected.ff56token.name);
}

pub fn main() !void {
    const size_limit = std.math.maxInt(u32);
    var file = try std.fs.cwd().openFile("testFiles/Scenario.bin", .{});

    const testBytes = try file.readToEndAlloc(allocator, size_limit);
    var testStatus = status.init(testBytes);
    for ((try parse(&testStatus)).items) |node| {
        std.debug.print("{any}\n", .{node});
    }
}
