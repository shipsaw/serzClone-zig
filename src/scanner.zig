const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();

const status = struct {
    start: usize,
    current: usize,
    line: usize,
    source: []const u8,
    tokens: []tokenType,
    stringMap: std.ArrayList([]const u8),

    pub fn init(src: []const u8) status {
        return status{ .start = 0, .current = 0, .line = 1, .source = src, .tokens = undefined, .stringMap = std.ArrayList([]const u8).init(allocator) };
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

const keywords = std.StringHashMap(dataType).init(allocator);
const dataTypeMap = std.ComptimeStringMap(dataType, .{
    .{ "bool", ._bool },
    .{ "sUInt8", ._sUInt8 },
    .{ "sInt32", ._sInt32 },
    .{ "sFloat32", ._sFloat32 },
    .{ "cDeltaString", ._cDeltaString },
});

const tokenType = enum {
    SERZ,
    FF40,
    FF56,
    FF70,
    NEW_STRING,
};

const dataType = enum {
    _bool,
    _sUInt8,
    _sInt32,
    _sFloat32,
    _cDeltaString,
};

const dataUnion = union(dataType) {
    _bool: bool,
    _sUInt8: i8,
    _sInt32: i32,
    _sFloat32: f32,
    _cDeltaString: []const u8,
};

const token = struct {
    tokenType: tokenType,
    value: dataUnion,
};

//pub fn parse(source: []const u8) void {
//    const dictionary = std.StringHashMap(tokenType).init(allocator);
//    defer dictionary.deinit();
//}

fn identifier(s: *status) ![]const u8 {
    if (s.source[s.current] == 255) // New string
    {
        s.current += 2;

        const strLen = std.mem.readIntSlice(u32, s.source[s.current..], std.builtin.Endian.Little);
        s.current += 4;
        // std.debug.print("String Length: {d}", .{strLen});

        var str = s.source[s.current..(s.current + strLen)];
        try s.stringMap.append(str);
        defer s.current += strLen;

        return str;
    }
    // std.debug.print("EXISTING WORD", .{});
    const strIdx = std.mem.readIntSlice(u16, s.source[s.current..], std.builtin.Endian.Little);
    s.current += 2;

    return s.stringMap.items[strIdx];
}

fn processData(s: *status) !dataUnion {
    const nodeName = try identifier(s);

    return switch (dataTypeMap.get(nodeName).?) {
        dataType._bool => processBool(s),
        dataType._sUInt8 => processSUInt8(s),
        dataType._sInt32 => processSInt32(s),
        dataType._sFloat32 => processSFloat32(s),
        dataType._cDeltaString => processCDeltaString(s),
    };
}

fn processBool(s: *status) dataUnion {
    _ = s;
    return dataUnion{ ._bool = true };
}

fn processSUInt8(s: *status) dataUnion {
    _ = s;
    return dataUnion{ ._sUInt8 = 1 };
}

fn processSInt32(s: *status) dataUnion {
    _ = s;
    return dataUnion{ ._sInt32 = 1 };
}

fn processSFloat32(s: *status) dataUnion {
    _ = s;
    return dataUnion{ ._sFloat32 = 1.0 };
}

fn processCDeltaString(s: *status) dataUnion {
    _ = s;
    return dataUnion{ ._cDeltaString = "" };
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

test "status struct advance works correctly" {
    // Arrange
    var testStatus = status{ .start = 0, .current = 0, .line = 1, .source = "Hello", .tokens = undefined, .stringMap = std.ArrayList([]const u8).init(allocator) };

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
    try std.testing.expectEqualStrings(actual, "Hello");
    try std.testing.expectEqualStrings(statusStruct.stringMap.items[0], "Hello");
    try std.testing.expect(statusStruct.peek() == 0);
}

test "identifier test, in map" {
    // Arrange
    var statusStruct = status.init(&[_]u8{ 0, 0 });
    try statusStruct.stringMap.append("Hello");

    // Act
    const actual = try identifier(&statusStruct);

    // Assert
    try std.testing.expectEqualStrings(actual, "Hello");
    try std.testing.expect(statusStruct.peek() == 0);
}

test "process data, keyword" {
    // Arrange
    var statusStruct = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l' });

    // Act
    const data = try processData(&statusStruct);

    // Assert
    try std.testing.expect(@as(dataType, data) == dataType._bool);
    try std.testing.expect(data._bool == true);
}

pub fn main() !void {
    // Arrange
    var statusStruct = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l' });

    // Act
    std.debug.print("Returned data union: {any}", .{try processData(&statusStruct)});

    // Assert
    return;
}
