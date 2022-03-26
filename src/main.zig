const std = @import("std");
const size_limit = std.math.maxInt(u32);

pub fn main() anyerror!void {
    const stdout = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var file = try std.fs.cwd().openFile("testFiles/test.bin", .{});
    const fileResult = try file.readToEndAlloc(allocator, size_limit);
    const result = if (verifyPrelude(fileResult[0..]) == true) "OK" else "INVALID FILE";
    parse(fileResult[8..], 0);
    try stdout.print("File status: {s}", .{result});
}

// Verify File begins with the prelude "SERZ"
fn verifyPrelude(preludeBytes: []u8) bool {
    const correctPrelude = "SERZ";
    for (correctPrelude) |char, i| {
        if (char != preludeBytes[i]) return false;
    }
    return true;
}

fn parse(fileBytes: []const u8, tabs: u8) void {
    if (fileBytes.len == 0) return;
    switch (fileBytes[1]) {
        0x50 => {
            print50(fileBytes, tabs);
        },
        else => std.debug.print("Not Parsable: {x}\n", .{fileBytes[1]}),
    }
}

fn print50(fileBytes: []const u8, tabs: u8) void {
    var i: u8 = 0;
    while (i < tabs) : (i += 1) {
        std.debug.print("\t", .{});
    }
    std.debug.print("<", .{});
    var nodeName: []const u8 = "";
    if (fileBytes[3] == 0xFF) {
        const wordOffset = 8;
        var wordLen = std.mem.readIntSlice(u32, fileBytes[4..], std.builtin.Endian.Little);
        nodeName = fileBytes[wordOffset .. wordOffset + wordLen];
        std.debug.print("{s}>\n", .{nodeName});
        parse(fileBytes[wordOffset + wordLen + 8 ..], tabs + 1);
    }
    i = 0;
    while (i < tabs) : (i += 1) {
        std.debug.print("\t", .{});
    }
    std.debug.print("</{s}>\n", .{nodeName});
    return;
}
