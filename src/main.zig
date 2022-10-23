const std = @import("std");
const binParser = @import("bin2obj.zig");
const objParser = @import("obj2json.zig");
const jsonParser = @import("json2bin.zig");
const n = @import("node.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
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

    var inputFileNameArray = std.mem.split(u8, args[1], ".");
    var outFileArray = std.ArrayList(u8).init(allocator);
    try outFileArray.appendSlice(inputFileNameArray.first());

    if (std.mem.eql(u8, inputFileNameArray.rest(), "bin")) {
        try outFileArray.appendSlice("2.json");
    } else if (std.mem.eql(u8, inputFileNameArray.rest(), "json")) {
        try outFileArray.appendSlice("2.bin");
    } else unreachable;
    var outFileName = if (args.len > 2) args[2] else outFileArray.items;
    const outFile = try std.fs.cwd().createFile(
        outFileName,
        .{ .read = true },
    );
    defer outFile.close();

    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);
    if (std.mem.eql(u8, inputFileNameArray.rest(), "bin")) {
        const nodes = (try binParser.parse(inputBytes));
        const jsonResult = try objParser.parse(nodes);
        try outFile.writeAll(jsonResult);
    } else if (std.mem.eql(u8, inputFileNameArray.rest(), "json")) {
        const binResult = try jsonParser.parse(inputBytes);
        try outFile.writeAll(binResult);
    } else {
        unreachable;
    }
}

test "bin -> json -> bin test" {
    std.debug.print("BEGIN TEST:\n", .{});
    var inFile = try std.fs.cwd().openFile("testFiles/Scenario.bin", .{});
    defer inFile.close();

    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);
    const nodes = (try binParser.parse(inputBytes));
    const jsonResult = try objParser.parse(nodes);

    const binResult = try jsonParser.parse(jsonResult);

    for (inputBytes) |inputByte, i| {
        if (binResult[i] != inputByte) {
            std.debug.print("ERROR, MISMATCH AT INDEX {any}\nEXPECTED: {any}\nACTUAL: {any}\n", .{ i, inputByte, binResult[i] });

            std.debug.print("EXPECTED:\n", .{});
            var j: u8 = 25;
            while (j > 0) : (j -= 1) {
                std.debug.print("{X} ", .{inputBytes[i - j]});
            }

            std.debug.print("({X}) ", .{inputBytes[i]});

            var k: u8 = 1;
            while (k < 26) : (k += 1) {
                std.debug.print("{X} ", .{inputBytes[i + k]});
            }

            std.debug.print("\n\nACTUAL:\n", .{});
            j = 25;
            while (j > 0) : (j -= 1) {
                std.debug.print("{X} ", .{binResult[i - j]});
            }

            std.debug.print("({X}) ", .{binResult[i]});

            k = 1;
            while (k < 26) : (k += 1) {
                std.debug.print("{X} ", .{binResult[i + k]});
            }
            std.debug.print("\n", .{});
            std.os.exit(1);
        }
    }

    try expectEqualSlices(u8, inputBytes, binResult);
}
