const std = @import("std");
const size_limit = std.math.maxInt(u32);

pub fn main() anyerror!void {
    const stdout = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var file = try std.fs.cwd().openFile("testFiles/test.bin", .{});

    const fileResult = try file.readToEndAlloc(allocator, size_limit);
    const fileResultHex = std.fmt.fmtSliceHexUpper(fileResult);
    try stdout.print("{x} ", .{fileResultHex});
}
