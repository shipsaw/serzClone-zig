const std = @import("std");
const size_limit = std.math.maxInt(u32);
const print = std.debug.print;

const fileError = error{InvalidFile};
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();
var wordList = std.ArrayList([]const u8).init(allocator);
var tabs: u8 = 0;

const attrTypeStrings = [_][]const u8{ "bool", "sUInt8", "sInt32", "cDeltaString" };

const attrType = enum { _bool, _sUInt8, _sInt32, _cDeltaString, _sFloat32 };
const attrTypePairs = .{ .{ "bool", attrType._bool }, .{ "sUInt8", attrType._sUInt8 }, .{ "sInt32", attrType._sInt32 }, .{ "cDeltaString", attrType._cDeltaString }, .{ "sFloat32", attrType._sFloat32 } };
const stringMap = std.ComptimeStringMap(attrType, attrTypePairs);

pub fn main() anyerror!void {
    defer arena.deinit();
    defer wordList.deinit();
    var file = try std.fs.cwd().openFile("testFiles/scenario.bin", .{});
    // var file = try std.fs.cwd().openFile("testFiles/test.bin", .{});
    const fileResult = try file.readToEndAlloc(allocator, size_limit);
    const fileBegin = try verifyPrelude(fileResult[0..]);
    _ = try parse(fileBegin[4..]);
    print("\nList of saved words = ", .{});
    for (wordList.items) |word, idx| {
        print(" {d}:{s},", .{ idx, word });
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
    print("fileBytes size: {d}\n\n", .{fileBytes.len});
    while (fileBytes.len > loopPos) {
        if (fileBytes[loopPos] == 0xFF) {
            loopPos = switch (fileBytes[1 + loopPos]) {
                0x50 => loopPos + (try print50(fileBytes[loopPos..])),
                0x56 => loopPos + (try print56(fileBytes[loopPos..])),
                0x70 => loopPos + print70(fileBytes[loopPos..]),
                else => loopPos + 1,
            };
            continue;
        }
        loopPos += 1;
    }
    return "";
}

fn print50(fileBytes: []const u8) !usize {
    printTabs();
    print("<", .{});
    var bytePos: usize = 2;
    bytePos += if (fileBytes[bytePos] == 0xFF) blk: {
        const newWord = try printNewWord(fileBytes[bytePos..]);
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

    print(">\n", .{});
    bytePos += 8;
    tabs += 1;
    return bytePos;
}

fn print56(fileBytes: []const u8) !usize {
    var nodeName: []const u8 = undefined;
    printTabs();
    print("<", .{});
    var bytePos: usize = 2;
    bytePos += if (fileBytes[bytePos] == 0xFF) blk: {
        nodeName = try printNewWord(fileBytes[bytePos..]);
        print("{s}", .{nodeName});
        break :blk nodeName.len + 6;
    } else blk: {
        nodeName = getSavedWord(fileBytes[bytePos..]);
        print("{s}", .{nodeName});
        break :blk 2;
    };

    print(" type=\"", .{});
    bytePos += if (fileBytes[bytePos] == 0xFF) blk: {
        const newWord = try printNewWord(fileBytes[bytePos..]);
        print("{s}", .{newWord});
        print("\">", .{});
        const dataSize = try getAttrValueType(newWord, fileBytes[bytePos + newWord.len + 6 ..]);
        break :blk newWord.len + dataSize + 2;
    } else blk: {
        const savedWord = getSavedWord(fileBytes[bytePos..]);
        print("{s}", .{savedWord});
        print("\">", .{});
        break :blk 2 + try getAttrValueType(savedWord, fileBytes[bytePos + 2 ..]);
    };
    print("</{s}>\n", .{nodeName});
    return bytePos;
}

fn print70(fileBytes: []const u8) usize {
    tabs -= 1;
    printTabs();
    var bytePos: usize = 2;
    print("</", .{});
    const savedWord = getSavedWord(fileBytes[bytePos..]);
    print("{s}", .{savedWord});
    bytePos += 2;
    print(">\n", .{});
    return bytePos;
}

// Attempt this first by only sending attribute length
fn getAttrValueType(attrTypeParam: []const u8, attrVal: []const u8) !usize {
    const tpe = stringMap.get(attrTypeParam).?;
    switch (tpe) {
        attrType._bool => {
            print("{d}", .{std.mem.readIntSlice(u8, attrVal, std.builtin.Endian.Little)});
            return 1;
        },
        attrType._sUInt8 => {
            print("{d}", .{std.mem.readIntSlice(u8, attrVal, std.builtin.Endian.Little)});
            return 1;
        },
        attrType._sInt32 => {
            print("{d}", .{std.mem.readIntSlice(i32, attrVal, std.builtin.Endian.Little)});
            return 4;
        },
        attrType._sFloat32 => {
            const fVal = @bitCast(f32, std.mem.readIntSlice(i32, attrVal, std.builtin.Endian.Little));
            print("{d:.3}", .{fVal});
            return 4;
        },
        attrType._cDeltaString => {
            return if (attrVal[0] == 0xFF) blk: {
                const attrValString = try printNewWord(attrVal);
                print("{s}", .{attrValString});
                break :blk attrValString.len + 6;
            } else blk: {
                const attrValString = getSavedWord(attrVal);
                print("{s}", .{attrValString});
                break :blk 2;
            };
        },
    }
}

fn getSavedWord(fileBytes: []const u8) []const u8 {
    const wordIndex = std.mem.readIntSlice(u16, fileBytes, std.builtin.Endian.Little);
    return wordList.items[wordIndex];
}

fn printNewWord(fileBytes: []const u8) ![]const u8 {
    var bytePos: usize = 2;
    const wordLen = std.mem.readIntSlice(u32, fileBytes[bytePos..], std.builtin.Endian.Little);
    bytePos += 4;
    const wordBegin = bytePos;
    const wordEnd = wordBegin + wordLen;
    bytePos += wordLen;

    try wordList.append(fileBytes[wordBegin..wordEnd]);
    return fileBytes[wordBegin..wordEnd];
}

fn debugPrinter(fileBytes: []const u8) !void {
    print("\n", .{});
    for (fileBytes[0..20]) |ch| {
        print("{x} ", .{ch});
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
