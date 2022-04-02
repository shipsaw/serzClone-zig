const std = @import("std");
const size_limit = std.math.maxInt(u32);

const fileError = error{
    InvalidFile,
    AccessDenied,
    FileNotFound,
};

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();
var wordList = std.ArrayList([]const u8).init(allocator);

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
fn verifyPrelude(preludeBytes: []u8) fileError![]const u8 {
    const correctPrelude = "SERZ";
    for (correctPrelude) |char, i| {
        if (char != preludeBytes[i]) return fileError.InvalidFile;
    }
    return preludeBytes[4..];
}

// Base parsing function, calls all others for node types
fn parse(fileBytes: []const u8) ![]const u8 {
    if (fileBytes.len == 0) return fileError.InvalidFile;
    const retval = switch (fileBytes[1]) {
        0x50 => print50(fileBytes),
        0x56 => print56(fileBytes),
        else => fileError.InvalidFile,
    };
    return retval;
}

fn print50(fileBytes: []const u8) ![]const u8 {
    var bytePos: usize = 2;
    if (fileBytes[bytePos] == 0xFF) {
        bytePos += 2;
        const wordLen = std.mem.readIntSlice(u32, fileBytes[bytePos..], std.builtin.Endian.Little);
        bytePos += 4;
        const wordBegin = bytePos;
        const wordEnd = wordBegin + wordLen;
        bytePos += wordLen;

        try wordList.append(fileBytes[wordBegin..wordEnd]);
        std.debug.print("<{s}>\n", .{fileBytes[wordBegin..wordEnd]});
        return fileBytes[bytePos + 4 ..];
    } else {
        const wordIndex = std.mem.readIntSlice(u16, fileBytes[2..], std.builtin.Endian.Little);
        const word = wordList.items[wordIndex];
        const wordLen = word.len;
        std.debug.print("<{s}>\n", .{word});
        bytePos += wordLen;
        bytePos += 4;
    }
    return fileBytes[bytePos..];
}

fn print56(fileBytes: []const u8) []const u8 {
    //var i: u8 = 0;
    //while (i < tabs) : (i += 1) {
    //    std.debug.print("\t", .{});
    //}
    //std.debug.print("<", .{});
    //var nodeName: []const u8 = "";
    //if (fileBytes[3] == 0xFF) {
    //    const wordOffset = 8;
    //    var wordLen = std.mem.readIntSlice(u32, fileBytes[4..], std.builtin.Endian.Little);
    //    nodeName = fileBytes[wordOffset .. wordOffset + wordLen];
    //    var attrOffset: usize = wordOffset + wordLen;
    //    var attrName: []const u8 = undefined;
    //    var attrLen: usize = 2;
    //    if (fileBytes[attrOffset] == 0xFF) {
    //        attrLen = std.mem.readIntSlice(u32, fileBytes[attrOffset + 2 ..], std.builtin.Endian.Little);
    //        attrName = fileBytes[attrOffset + 6 .. attrOffset + 6 + attrLen];
    //        attrLen += 4 + 2;
    //    }
    //    std.debug.print("{s} type={s}, val={d}>\n", .{ nodeName, attrName, getAttrValueLen(fileBytes[attrOffset + attrLen ..]) });
    //    parse(fileBytes[attrOffset + attrLen + 4 ..], tabs);
    //}
    std.debug.print("HIT A 56\n", .{});
    return fileBytes;
}

// Attempt this first by only sending attribute length
fn getAttrValueLen(attrVal: []const u8) u8 {
    switch (attrVal[0]) {
        'b' => return 1,
        's' => return 4,
        else => return 0,
    }
}
