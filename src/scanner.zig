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
    _sUInt8: u8,
    _sInt32: i32,
    _sFloat32: f32,
    _cDeltaString: []const u8,
};

const token = struct {
    tokenType: tokenType,
    value: dataUnion,
};

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

fn processSFloat32(s: *status) dataUnion {
    defer s.current += 4;
    const val = @bitCast(f32, std.mem.readIntSlice(i32, s.source[s.current..], std.builtin.Endian.Little));
    return dataUnion{ ._sFloat32 = val };
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
    try std.testing.expect(statusStruct.peek() == 0); // current is left at correct position
}

test "bool data" {
    // Arrange
    var statusStructTrue = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 1 });
    var statusStructFalse = status.init(&[_]u8{ 255, 255, 4, 0, 0, 0, 'b', 'o', 'o', 'l', 0 });

    // Act
    const dataTrue = try processData(&statusStructTrue);
    const dataFalse = try processData(&statusStructFalse);

    // Assert
    try std.testing.expect(@as(dataType, dataTrue) == dataType._bool);

    try std.testing.expect(dataTrue._bool == true);
    try std.testing.expect(dataFalse._bool == false);

    try std.testing.expect(statusStructTrue.peek() == 0); // current is left at correct position
}

test "sUInt8 data" {
    // Arrange
    var statusStruct11 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'U', 'I', 'n', 't', '8', 11 });
    var statusStruct0 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'U', 'I', 'n', 't', '8', 0 });

    // Act
    const data11 = try processData(&statusStruct11);
    const data0 = try processData(&statusStruct0);

    // Assert
    try std.testing.expect(@as(dataType, data11) == dataType._sUInt8);

    try std.testing.expect(data11._sUInt8 == 11);
    try std.testing.expect(data0._sUInt8 == 0);

    try std.testing.expect(statusStruct11.peek() == 0); // current is left at correct position
}

test "sInt32 data" {
    // Arrange
    var statusStruct_3200 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'I', 'n', 't', '3', '2', 0x80, 0xf3, 0xff, 0xff }); // -3200
    var statusStruct3210 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'I', 'n', 't', '3', '2', 0x8a, 0x0c, 0x00, 0x00 }); // 3210

    // Act
    const data_3200 = try processData(&statusStruct_3200);
    const data3210 = try processData(&statusStruct3210);

    // Assert
    try std.testing.expect(@as(dataType, data_3200) == dataType._sInt32);

    try std.testing.expect(data_3200._sInt32 == -3200);
    try std.testing.expect(data3210._sInt32 == 3210);

    try std.testing.expect(statusStruct_3200.peek() == 0); // current is left at correct position
}

test "sInt32 data" {
    // Arrange
    var statusStruct12345 = status.init(&[_]u8{ 255, 255, 8, 0, 0, 0, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0x66, 0xe6, 0xf6, 0x42 }); // 123.45
    var statusStruct_1234 = status.init(&[_]u8{ 255, 255, 8, 0, 0, 0, 's', 'F', 'l', 'o', 'a', 't', '3', '2', 0xa4, 0x70, 0x45, 0xc1 }); // -1234

    // Act
    const data12345 = try processData(&statusStruct12345);
    const data_1234 = try processData(&statusStruct_1234);

    // Assert
    try std.testing.expect(@as(dataType, data12345) == dataType._sFloat32);

    try std.testing.expect(data12345._sFloat32 == 123.45);
    try std.testing.expect(data_1234._sFloat32 == -12.34);

    try std.testing.expect(statusStruct12345.peek() == 0); // current is left at correct position
}

pub fn main() !void {
    // Arrange
    var statusStruct_3200 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'I', 'n', 't', '3', '2', 0x80, 0xf3, 255, 255 }); // -3200
    var statusStruct3210 = status.init(&[_]u8{ 255, 255, 6, 0, 0, 0, 's', 'I', 'n', 't', '3', '2', 0x8a, 0x0c, 0, 0 }); // 3210

    // Act
    const data_3200 = try processData(&statusStruct_3200);
    const data3210 = try processData(&statusStruct3210);

    // Assert
    std.debug.print("{any}\n", .{data_3200._sInt32});
    std.debug.print("{any}\n", .{data3210._sInt32});
}
