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
fn parse(fileBytes: []const u8) fileError![]const u8 {
    if (fileBytes.len == 0) return fileError.InvalidFile;
    const retval = switch (fileBytes[1]) {
        0x50 => print50(fileBytes),
        0x56 => print56(fileBytes),
        0x70 => std.debug.print("HIT A 70\n", .{}),
        else => fileError.InvalidFile,
    };
    return retval;
}

fn print50(fileBytes: []const u8) []const u8 {
    var bytePos: []const u8 = fileBytes[2..];
    if (bytePos == 0xFF) {
        bytePos = bytePos[2..];
        const wordLen = std.mem.readIntSlice(u32, bytePos, std.builtin.Endian.Little);
        bytePos += 4;
        const wordEnd = wordOffset + wordLen;

        try wordList.append(fileBytes[wordOffset..wordEnd]);
        std.debug.print("<{s}>\n", .{fileBytes[wordOffset..wordEnd]});
        return fileBytes[wordOffset + wordLen + 1 ..];
    } else {
        const wordLen = std.mem.readIntSlice(u16, fileBytes[2], std.builtin.Endian.Little);
    }
    return fileBytes[1..];
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
