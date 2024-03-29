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
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2 or args.len > 4) {
        std.debug.print("Usage: zigSerz input_filename [output_filename] [-s]\n", .{});
        std.os.exit(1);
    }
    const simpleOutput = std.mem.eql(u8, args[args.len - 1], "-s");
    const customOutputName = (args.len == 3 and !simpleOutput) or (args.len == 4 and simpleOutput);

    var inFile = try std.fs.cwd().openFile(args[1], .{});
    defer inFile.close();

    var inputFileNameArray = std.mem.tokenize(u8, args[1], ".\\/");

    var filePathArray = std.ArrayList([]const u8).init(allocator);
    while (true) {
        const tempSlice = inputFileNameArray.next();
        if (tempSlice != null) {
            try filePathArray.append(tempSlice.?);
        } else {
            break;
        }
    }
    inputFileNameArray.reset();
    const fileExtension = filePathArray.items[filePathArray.items.len - 1];
    const fileName = filePathArray.items[filePathArray.items.len - 2];

    var outFileArray = std.ArrayList(u8).init(allocator);
    try outFileArray.appendSlice(fileName);

    if (std.mem.eql(u8, fileExtension, "bin")) {
        try outFileArray.appendSlice(".xml");
    } else if (std.mem.eql(u8, fileExtension, "xml")) {
        try outFileArray.appendSlice(".bin");
    } else unreachable;
    var outFileName = if (customOutputName) args[2] else outFileArray.items;
    const outFile = try std.fs.cwd().createFile(
        outFileName,
        .{ .read = true },
    );
    defer outFile.close();

    var inputBytes = try inFile.readToEndAlloc(allocator, size_limit);
    if (std.mem.eql(u8, fileExtension, "bin")) {
        const nodes = (try binParser.parse(inputBytes));
        // const xmlResult = try objParser.parseSimple(nodes);
        const xmlResult = if (simpleOutput) 
            try objParser.parseSimple(nodes) 
            else try objParser.parseComplete(nodes);
        try outFile.writeAll(xmlResult);
    } else if (std.mem.eql(u8, fileExtension, "xml")) {
        const binResult = try xmlParser.parse(inputBytes);
        try outFile.writeAll(binResult);
    } else {
        unreachable;
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
