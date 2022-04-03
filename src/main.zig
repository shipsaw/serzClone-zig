const std = @import("std");
const size_limit = std.math.maxInt(u32);

const fileError = error{InvalidFile};
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();
var wordList = std.ArrayList([]const u8).init(allocator);
var tabs: u8 = 0;

// const attrInfo = union(attrInfoEnum) {
//     _bool: u8,
//     _sUInt8: u8,
//     _sInt32: i32,
// };

const attrTypes = [_]u8{ "bool", "sUInt8", "sInt32" };

pub fn main() anyerror!void {
    defer arena.deinit();
    defer wordList.deinit();
    var file = try std.fs.cwd().openFile("testFiles/test.bin", .{});
    const fileResult = try file.readToEndAlloc(allocator, size_limit);
    const fileBegin = try verifyPrelude(fileResult[0..]);
    _ = try parse(fileBegin[4..]);
    std.debug.print("List of saved words = ", .{});
    for (wordList.items) |word, idx| {
        std.debug.print(" {d}:{s},", .{ idx, word });
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
    std.debug.print("fileBytes size: {d}\n", .{fileBytes.len});
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
    std.debug.print("<", .{});
    var bytePos: usize = 2;
    bytePos += if (fileBytes[bytePos] == 0xFF)
        try printNewWord(fileBytes[bytePos..])
    else
        std.debug.print("{s}, .{printSavedWord(fileBytes[bytePos..])});
    const idVal = std.mem.readIntSlice(u32, fileBytes[bytePos..], std.builtin.Endian.Little);
    if (idVal != 0) {
        std.debug.print(" id=\"{d}\"", .{idVal});
    }

    std.debug.print(">\n", .{});
    bytePos += 8;
    tabs += 1;
    return bytePos;
}

fn print56(fileBytes: []const u8) !usize {
    printTabs();
    var bytePos: usize = 2;
    bytePos += if (fileBytes[bytePos] == 0xFF)
        try printNewWord(fileBytes[bytePos..])
    else
        std.debug.print("{s}", .{printSavedWord(fileBytes[bytePos..])});

    std.debug.print(" type=\"", .{});
    bytePos += if (fileBytes[bytePos] == 0xFF)
        try printNewWord(fileBytes[bytePos..])
    else
        std.debug.print("{s}", .{printSavedWord(fileBytes[bytePos..])});
    std.debug.print("\"", .{});

    // TEMP HACK
    while (fileBytes[bytePos] != 0xFF) : (bytePos += 1) {}
    std.debug.print(">\n", .{});
    return bytePos;
}

fn print70(fileBytes: []const u8) usize {
    tabs -= 1;
    printTabs();
    var bytePos: usize = 2;
    std.debug.print("</", .{});
    bytePos = printSavedWord(fileBytes[bytePos..]);
    std.debug.print(">\n", .{});
    return bytePos;
}

// Attempt this first by only sending attribute length
fn getAttrValueLen(attrVal: []const u8) u8 {
    switch (attrVal[0]) {
        'b' => return 1,
        's' => if (attrVal[4] == '3') 4 else 1,
        else => return 0,
    }
}

fn getSavedWord(fileBytes: []const u8) []const u8 {
    const wordIndex = std.mem.readIntSlice(u16, fileBytes, std.builtin.Endian.Little);
    return wordList.items[wordIndex];
}

fn printNewWord(fileBytes: []const u8) !usize {
    var bytePos: usize = 2;
    const wordLen = std.mem.readIntSlice(u32, fileBytes[bytePos..], std.builtin.Endian.Little);
    bytePos += 4;
    const wordBegin = bytePos;
    const wordEnd = wordBegin + wordLen;
    bytePos += wordLen;

    try wordList.append(fileBytes[wordBegin..wordEnd]);
    std.debug.print("{s}", .{fileBytes[wordBegin..wordEnd]});
    return bytePos;
}

fn debugPrinter(fileBytes: []const u8) !void {
    std.debug.print("\n", .{});
    for (fileBytes[0..20]) |ch| {
        std.debug.print("{x} ", .{ch});
    }
    std.debug.print("\n", .{});
}

fn printTabs() void {
    var i: u8 = 0;
    while (i < tabs) : (i += 1) {
        std.debug.print("\t", .{});
    }
    return;
}
