const std = @import("std");
const parser = @import("binParser.zig");
const sorter = @import("sort.zig");
const n = @import("node.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2 or args.len > 3) {
        std.debug.print("Usage: zigSerz [filename]\n", .{});
        std.os.exit(1);
    }

    var inFile = try std.fs.cwd().openFile(args[1], .{});
    defer inFile.close();

    var iterator = std.mem.split(u8, args[1], ".");
    var outFileArray = std.ArrayList(u8).init(allocator);
    try outFileArray.appendSlice(iterator.first());
    try outFileArray.appendSlice(".json");
    var outFileName = if (args.len > 2) args[2] else outFileArray.items;
    const outFile = try std.fs.cwd().createFile(
        outFileName,
        .{ .read = true },
    );
    defer outFile.close();
    const inputBytes = try inFile.readToEndAlloc(allocator, size_limit);
    var testStatus = parser.status.init(inputBytes);

    const nodes = (try parser.parse(&testStatus)).items;
    const textNodesList = try sorter.sort(nodes);

    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(textNodesList, .{}, string.writer());
    try outFile.writeAll(string.items);
}
