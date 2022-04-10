const std = @import("std");
const size_limit = std.math.maxInt(u32);
const print = std.debug.print;

const fileError = error{InvalidFile};
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();
var wordList = std.ArrayList([]const u8).init(allocator);
var savedLines = std.ArrayList([]const u8).init(allocator);
var tabs: u8 = 0;

const attrTypeStrings = [_][]const u8{ "bool", "sUInt8", "sInt32", "cDeltaString", "sUInt64" };

const attrType = enum { _bool, _sUInt8, _sInt32, _cDeltaString, _sFloat32, _sUInt64 };
const attrTypePairs = .{ .{ "bool", attrType._bool }, .{ "sUInt8", attrType._sUInt8 }, .{ "sInt32", attrType._sInt32 }, .{ "cDeltaString", attrType._cDeltaString }, .{ "sFloat32", attrType._sFloat32 }, .{ "sUInt64", attrType._sUInt64 } };
const stringMap = std.ComptimeStringMap(attrType, attrTypePairs);

pub fn main() anyerror!void {
    defer arena.deinit();
    defer wordList.deinit();
    var file = try std.fs.cwd().openFile("testFiles/scenario.bin", .{});
    // var file = try std.fs.cwd().openFile("testFiles/test.bin", .{});
    const fileResult = try file.readToEndAlloc(allocator, size_limit);
    const fileBegin = try verifyPrelude(fileResult[0..]);
    _ = try parse(fileBegin[4..]);
    errdefer {
        print("\nList of saved words = ", .{});
        for (wordList.items) |word, idx| {
            print(" {d}:{s},", .{ idx, word });
        }
    }
}

// Verify File begins with the prelude "SERZ"
fn verifyPrelude(preludeBytes: []u8) ![]const u8 {
    const correctPrelude = "SERZ";
    for (correctPrelude) |char, i| {
        if (char != preludeBytes[i]) return fileError.InvalidFile;
    }
    return preludeBytes[4..];
}

// Base parsing function, calls all others for node types
fn parse(fileBytes: []const u8) ![]const u8 {
    var loopPos: usize = 0;
    while (fileBytes.len > loopPos) {
        // print("LoopPos char: {x}", .{fileBytes[loopPos]});
        if (fileBytes[loopPos] == 0xFF) {
            loopPos = switch (fileBytes[1 + loopPos]) {
                0x50 => loopPos + (try print50(fileBytes[loopPos..], true)),
                0x56 => loopPos + (try print56(fileBytes[loopPos..], true)),
                0x70 => loopPos + (try print70(fileBytes[loopPos..], true)),
                // NEXT: 0x41
                else => unreachable,
            };
        } else {
            // print("Using line {d}: ", .{fileBytes[loopPos]});
            loopPos = loopPos + (try parseSaved(fileBytes[loopPos..]));
        }
    }
    return "";
}

fn parseSaved(fileBytes: []const u8) !usize {
    var splicedBytes = std.ArrayList(u8).init(allocator);
    try splicedBytes.appendSlice(savedLines.items[fileBytes[0]]);
    const splicedBytesLength = splicedBytes.items.len;
    try splicedBytes.appendSlice(fileBytes[1..]);
    var bytePos = switch (splicedBytes.items[1]) {
        0x50 => try print50(splicedBytes.items, false),
        0x56 => try print56(splicedBytes.items, false),
        0x70 => try print70(splicedBytes.items, false),
        else => unreachable,
    };
    // try debugPrinter(fileBytes[0..4]);
    return bytePos - splicedBytesLength + 1;
}

fn print50(fileBytes: []const u8, newLine: bool) !usize {
    printTabs();
    print("<", .{});

    var bytePos: usize = 2;
    bytePos += if (fileBytes[bytePos] == 0xFF) blk: {
        const newWord = try printNewWord(fileBytes[bytePos..], newLine);
        print("{s}", .{newWord});
        break :blk newWord.len + 6;
    } else blk: {
        const savedWord = getSavedWord(fileBytes[bytePos..]);
        print("{s}", .{savedWord});
        break :blk 2;
    };
    const idVal = std.mem.readIntSlice(u32, fileBytes[bytePos..], std.builtin.Endian.Little);
    if (idVal != 0) {
        print(" id=\"{d}\"", .{idVal});
    }
    if (newLine) {
        try savedLines.append(fileBytes[0..bytePos]);
    }

    print(">\n", .{});
    bytePos += 8;
    tabs += 1;
    return bytePos;
}

fn print56(fileBytes: []const u8, newLine: bool) !usize {
    var nodeName: []const u8 = undefined;
    printTabs();
    print("<", .{});
    var bytePos: usize = 2;
    bytePos += if (fileBytes[bytePos] == 0xFF) blk: {
        nodeName = try printNewWord(fileBytes[bytePos..], newLine);
        print("{s}", .{nodeName});
        break :blk nodeName.len + 6;
    } else blk: {
        nodeName = getSavedWord(fileBytes[bytePos..]);
        print("{s}", .{nodeName});
        break :blk 2;
    };

    print(" type=\"", .{});
    bytePos += if (fileBytes[bytePos] == 0xFF) blk: {
        const newWord = try printNewWord(fileBytes[bytePos..], newLine);
        print("{s}", .{newWord});
        const dataSize = try getAttrValueType(newWord, fileBytes[bytePos + newWord.len + 6 ..]);
        // try debugPrinter(fileBytes[0 .. bytePos + newWord.len + 6]);
        if (newLine) {
            try savedLines.append(fileBytes[0 .. bytePos + newWord.len + 6]);
        }
        break :blk newWord.len + dataSize + 6;
    } else blk: {
        const savedWord = getSavedWord(fileBytes[bytePos..]);
        print("{s}", .{savedWord});
        // try debugPrinter(fileBytes[0 .. bytePos + 2]);
        if (newLine) {
            try savedLines.append(fileBytes[0 .. bytePos + 2]);
        }
        break :blk 2 + try getAttrValueType(savedWord, fileBytes[bytePos + 2 ..]);
    };
    print("</{s}>\n", .{nodeName});
    return bytePos;
}

fn print70(fileBytes: []const u8, newLine: bool) !usize {
    tabs -= 1;
    printTabs();
    var bytePos: usize = 2;
    print("</", .{});
    const savedWord = getSavedWord(fileBytes[bytePos..]);
    print("{s}", .{savedWord});
    bytePos += 2;
    print(">\n", .{});
    if (newLine) {
        try savedLines.append(fileBytes[0..bytePos]);
    }
    return bytePos;
}

// Attempt this first by only sending attribute length
fn getAttrValueType(attrTypeParam: []const u8, attrVal: []const u8) !usize {
    const tpe = stringMap.get(attrTypeParam).?;
    switch (tpe) {
        attrType._bool => {
            print("\">{d}", .{std.mem.readIntSlice(u8, attrVal, std.builtin.Endian.Little)});
            return 1;
        },
        attrType._sUInt8 => {
            print("\">{d}", .{std.mem.readIntSlice(u8, attrVal, std.builtin.Endian.Little)});
            return 1;
        },
        attrType._sInt32 => {
            print("\">{d}", .{std.mem.readIntSlice(i32, attrVal, std.builtin.Endian.Little)});
            return 4;
        },
        attrType._sFloat32 => {
            const fVal = @bitCast(f32, std.mem.readIntSlice(i32, attrVal, std.builtin.Endian.Little));

            const text: f64 = fVal;
            const text2: [8]u8 = @bitCast([8]u8, text);
            print("\" alt_encoding=\"", .{});
            for (text2) |c| {
                print("{X:0>2}", .{c});
            }
            print("\">", .{});
            try printStringPrecision(fVal);
            return 4;
        },
        attrType._sUInt64 => {
            print("\">{d}", .{std.mem.readIntSlice(u64, attrVal, std.builtin.Endian.Little)});
            return 8;
        },
        attrType._cDeltaString => {
            return if (attrVal[0] == 0xFF) blk: {
                const attrValString = try printNewWord(attrVal, true);
                print("\">{s}", .{attrValString});
                break :blk attrValString.len + 6;
            } else blk: {
                const attrValString = getSavedWord(attrVal);
                print("\">{s}", .{attrValString});
                break :blk 2;
            };
        },
    }
}

fn printStringPrecision(fVal: f32) !void {
    var buf: [20]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.fmt.formatFloatDecimal(fVal, std.fmt.FormatOptions{}, fbs.writer());
    var prec: u8 = 6;
    for (buf) |c| {
        if (c >= '0' and c <= '9' and prec > 0) {
            print("{c}", .{c});
            prec -= 1;
        } else if (c == '.') {
            print(".", .{});
            continue;
        } else if (c == '-') {
            print("-", .{});
            continue;
        } else {
            break;
        }
    }
    return;
}

fn getSavedWord(fileBytes: []const u8) []const u8 {
    const wordIndex = std.mem.readIntSlice(u16, fileBytes, std.builtin.Endian.Little);
    // print("Getting word: {d}, arrray len: {d}\n", .{ wordIndex, wordList.items.len });
    return wordList.items[wordIndex];
}

fn printNewWord(fileBytes: []const u8, newLine: bool) ![]const u8 {
    var bytePos: usize = 2;
    const wordLen = std.mem.readIntSlice(u32, fileBytes[bytePos..], std.builtin.Endian.Little);
    bytePos += 4;
    const wordBegin = bytePos;
    const wordEnd = wordBegin + wordLen;
    bytePos += wordLen;

    if (newLine) {
        try wordList.append(fileBytes[wordBegin..wordEnd]);
    }
    return fileBytes[wordBegin..wordEnd];
}

fn debugPrinter(fileBytes: []const u8) !void {
    print("\nDEBUG PRINT\n", .{});
    for (fileBytes) |ch| {
        print("{X:0>2} ", .{ch});
    }
    print("\n", .{});
}

fn printTabs() void {
    var i: u8 = 0;
    while (i < tabs) : (i += 1) {
        print("\t", .{});
    }
    return;
}
