const std = @import("std");
const size_limit = std.math.maxInt(u32);

pub fn main() anyerror!void {
    const stdout = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var file = try std.fs.cwd().openFile("testFiles/test.bin", .{});
    const fileResult = try file.readToEndAlloc(allocator, size_limit);
    try beginParse(fileResult);
    const result = if (verifyPrelude(fileResult[0..]) == true) "OK" else "INVALID FILE";
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

fn beginParse(fileBytes: []const u8) !void {
    var i: usize = 0;
    while (i < fileBytes.len) : (i += 1) {
        if (fileBytes[i] == 0xFF and fileBytes[i + 1] == 0xFF) {
            var ffNum = std.mem.readIntSlice(u32, fileBytes[i + 2 ..], std.builtin.Endian.Little);
            std.debug.print("WORD: {s}\n", .{fileBytes[i + 6 .. i + 6 + ffNum]});
        }
        i += 1;
    }
}
