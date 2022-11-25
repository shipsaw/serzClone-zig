const std = @import("std");
const binParser = @import("bin2obj.zig");
const xmlParser = @import("xml2obj.zig");
const objParser = @import("obj2xml.zig");
const n = @import("node.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

pub fn main() !void {
    var stdIn = std.io.getStdIn().reader();
    var stdOut = std.io.getStdOut().writer();

    var inputBytes = try stdIn.readAllAlloc(allocator, 10485760);
    for (inputBytes[0..30]) |byte| {
        std.debug.print("{x} ", .{byte});
    }
        std.debug.print("\n", .{});
    if (std.mem.eql(u8, inputBytes[0..4], "SERZ")) {
        const nodes = (try binParser.parse(inputBytes));
        const xmlResult = try objParser.parseComplete(nodes);
        try stdOut.writeAll(xmlResult);
    } else {
        const binResult = try xmlParser.parse(inputBytes);
        try stdOut.writeAll(binResult);
    }
}

test "bin -> xml -> bin test: InitalSave.bin" {
    // Original Scenario with ff43 node
    var inFile43 = try std.fs.cwd().openFile("testFiles/InitialSaveBeforeSerz.bin", .{});
    defer inFile43.close();
    var inputBytes43 = try inFile43.readToEndAlloc(allocator, size_limit);

    // Scenario parsed by serz
    var inFile = try std.fs.cwd().openFile("testFiles/InitialSaveAfterSerz.bin", .{});
    defer inFile.close();
    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);

    const nodes = (try binParser.parse(inputBytes43));
    const xmlResult = try objParser.parseSimple(nodes);
    const binResult = try xmlParser.parse(xmlResult);

    try compareResults(inputBytes, binResult);
}

test "bin -> xml -> bin test: Scenario.bin" {
    // Original Scenario with ff43 node
    var inFile43 = try std.fs.cwd().openFile("testFiles/ScenarioBeforeSerz.bin", .{});
    defer inFile43.close();
    var inputBytes43 = try inFile43.readToEndAlloc(allocator, size_limit);

    // Scenario parsed by serz
    var inFile = try std.fs.cwd().openFile("testFiles/ScenarioAfterSerz.bin", .{});
    defer inFile.close();
    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);

    const nodes = (try binParser.parse(inputBytes43));
    const xmlResult = try objParser.parseSimple(nodes);
    const binResult = try xmlParser.parse(xmlResult);

    try compareResults(inputBytes, binResult);
}

test "bin -> xml -> bin test: ScenarioNetworkProperties.bin" {
    // Original Scenario with ff43 node
    var inFile43 = try std.fs.cwd().openFile("testFiles/ScenarioNetworkPropertiesBeforeSerz.bin", .{});
    defer inFile43.close();
    var inputBytes43 = try inFile43.readToEndAlloc(allocator, size_limit);

    // Scenario parsed by serz
    var inFile = try std.fs.cwd().openFile("testFiles/ScenarioNetworkPropertiesAfterSerz.bin", .{});
    defer inFile.close();
    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);

    const nodes = (try binParser.parse(inputBytes43));
    const xmlResult = try objParser.parseSimple(nodes);
    const binResult = try xmlParser.parse(xmlResult);

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
                var j = if (i < 60) i else 60;
                while (j > 0) : (j -= 1) {
                    std.debug.print("{X} ", .{expectedBytes[i - j]});
                }

                std.debug.print("({X}) ", .{expectedBytes[i]});

                var k: u8 = 1;
                while (k < 60) : (k += 1) {
                    std.debug.print("{X} ", .{expectedBytes[i + k]});
                }

                std.debug.print("\nACTUAL:\n", .{});
                j = if (i < 60) i else 60;
                while (j > 0) : (j -= 1) {
                    std.debug.print("{X} ", .{actualBytes[i - j]});
                }

                std.debug.print("({X}) ", .{actualBytes[i]});

                k = 1;
                while (k < 60) : (k += 1) {
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
