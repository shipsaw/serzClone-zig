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
        std.debug.print("Usage: zigSerz input_filename [output_filename]\n", .{});
        std.os.exit(1);
    }

    var inFile = try std.fs.cwd().openFile(args[1], .{});
    defer inFile.close();

    var inputFileNameArray = std.mem.split(u8, args[1], ".");
    var outFileArray = std.ArrayList(u8).init(allocator);
    try outFileArray.appendSlice(inputFileNameArray.first());

    if (std.mem.eql(u8, inputFileNameArray.rest(), "bin")) {
        try outFileArray.appendSlice(".json");
    } else if (std.mem.eql(u8, inputFileNameArray.rest(), "json")) {
        try outFileArray.appendSlice(".bin");
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

test "bin -> json -> bin test: InitalSave.bin" {
    // Original Scenario with ff43 node
    var inFile43 = try std.fs.cwd().openFile("testFiles/InitialSave.bin", .{});
    defer inFile43.close();
    var inputBytes43 = try inFile43.readToEndAlloc(allocator, size_limit);

    // Scenario parsed by serz
    var inFile = try std.fs.cwd().openFile("testFiles/InitialSaveAfterSerz.bin", .{});
    defer inFile.close();
    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);

    const nodes = (try binParser.parse(inputBytes43));
    const jsonResult = try objParser.parse(nodes);
    const binResult = try jsonParser.parse(jsonResult);

    try compareResults(inputBytes, binResult);
}

test "bin -> json -> bin test: Scenario.bin" {
    // Original Scenario with ff43 node
    var inFile43 = try std.fs.cwd().openFile("testFiles/ScenarioWff43.bin", .{});
    defer inFile43.close();
    var inputBytes43 = try inFile43.readToEndAlloc(allocator, size_limit);

    // Scenario parsed by serz
    var inFile = try std.fs.cwd().openFile("testFiles/ScenarioAfterSerz.bin", .{});
    defer inFile.close();
    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);

    const nodes = (try binParser.parse(inputBytes43));
    const jsonResult = try objParser.parse(nodes);
    const binResult = try jsonParser.parse(jsonResult);

    try compareResults(inputBytes, binResult);
}

test "bin -> json -> bin test: ScenarioNetworkProperties.bin" {
    // Original Scenario with ff43 node
    //var inFile43 = try std.fs.cwd().openFile("testFiles/ScenarioNetworkProperties.bin", .{});
    var inFile43 = try std.fs.cwd().openFile("testFiles/ScenarioNetworkPropertiesAfterSerz.bin", .{});
    defer inFile43.close();
    var inputBytes43 = try inFile43.readToEndAlloc(allocator, size_limit);

    // Scenario parsed by serz
    var inFile = try std.fs.cwd().openFile("testFiles/ScenarioNetworkPropertiesAfterSerz.bin", .{});
    defer inFile.close();
    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);

    const nodes = (try binParser.parse(inputBytes43));
    const jsonResult = try objParser.parse(nodes);
    const binResult = try jsonParser.parse(jsonResult);

    try compareResults(inputBytes, binResult);
}

fn compareResults(expectedBytes: []const u8, actualBytes: []const u8) !void {
    for (expectedBytes) |inputByte, i| {
        if (actualBytes[i] != inputByte) {
            const expectedVal = @bitCast(f32, std.mem.readIntSlice(i32, expectedBytes[i..], std.builtin.Endian.Little));
            const actualVal = @bitCast(f32, std.mem.readIntSlice(i32, actualBytes[i..], std.builtin.Endian.Little));
            if (@fabs(expectedVal - actualVal) / expectedVal > 0.00001) {
                std.debug.print("ERROR, MISMATCH AT INDEX {any}\nEXPECTED: {any}\nACTUAL: {any}\n", .{ i, inputByte, actualBytes[i] });
                std.debug.print("EXPECTED: {s},\n", .{try formatFloat(expectedVal)});
                std.debug.print("ACTUAL:   {s},\n", .{try formatFloat(actualVal)});

                std.debug.print("EXPECTED(full): {d},\n", .{expectedVal});
                std.debug.print("ACTUAL(full):   {d},\n", .{actualVal});

                std.debug.print("EXPECTED:\n", .{});
                var j = if (i < 25) i else 25;
                while (j > 0) : (j -= 1) {
                    std.debug.print("{X} ", .{expectedBytes[i - j]});
                }

                std.debug.print("({X}) ", .{expectedBytes[i]});

                var k: u8 = 1;
                while (k < 26) : (k += 1) {
                    std.debug.print("{X} ", .{expectedBytes[i + k]});
                }

                std.debug.print("\nACTUAL:\n", .{});
                j = if (i < 25) i else 25;
                while (j > 0) : (j -= 1) {
                    std.debug.print("{X} ", .{actualBytes[i - j]});
                }

                std.debug.print("({X}) ", .{actualBytes[i]});

                k = 1;
                while (k < 26) : (k += 1) {
                    std.debug.print("{X} ", .{actualBytes[i + k]});
                }
                std.debug.print("\n", .{});
                std.os.exit(1);
            }
            i += 3;
        }
    }
}

fn formatFloat(val: f32) ![]const u8 {
    if (val < 1) {
        return try std.fmt.allocPrint(allocator, "{d:.7}", .{val});
    } else if (val < 10) {
        return try std.fmt.allocPrint(allocator, "{d:.5}", .{val});
    } else if (val < 100) {
        return try std.fmt.allocPrint(allocator, "{d:.4}", .{val});
    } else if (val < 1000) {
        return try std.fmt.allocPrint(allocator, "{d:.3}", .{val});
    } else if (val < 10_000) {
        return try std.fmt.allocPrint(allocator, "{d:.2}", .{val});
    } else if (val < 100_000) {
        return try std.fmt.allocPrint(allocator, "{d:.1}", .{val});
    } else if (val < 1_000_000) {
        return try std.fmt.allocPrint(allocator, "{d:.0}", .{val});
    } else {
        return try std.fmt.allocPrint(allocator, "{e:.6}", .{val});
    }
}
