const std = @import("std");
const parser = @import("bin2obj.zig");
const nde = @import("node.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);
const dataTypeMap = std.AutoHashMap(nde.dataType, []const u8);

pub fn parse(nodes: []const nde.node) ![]const u8 {
    var outputString = std.ArrayList(u8).init(allocator);
    var sw = outputString.writer();
    var dTypeMap = dataTypeMap.init(allocator);
    try initDtypeMap(&dTypeMap);
    var tabs: usize = 0;
    for (nodes) |node| {
        switch (node) {
            .ff41node => |n| {
                try printTabs(tabs, sw);
                try std.fmt.format(sw, "<{s}", .{n.name});
                try std.fmt.format(sw, " numElements:\"{d}\">", .{n.numElements});
                try std.fmt.format(sw, " elementType:\"{s}\">", .{dTypeMap.get(n.dType).?});

                var i:u32 = 0;
                while (i < n.numElements) : (i += 1) {
                    try printValue(n.values.items[i], sw);
                    if (i < n.numElements - 1) {
                        try sw.writeByte(' ');
                    }
                }

                try std.fmt.format(sw, "</{s}>\n", .{n.name});
            },
            .ff4enode => {
                try printTabs(tabs, sw);
                try std.fmt.format(sw, "<nil/>", .{});
            },
            .ff50node => |n| {
                try printTabs(tabs, sw);
                try std.fmt.format(sw, "<{s}", .{n.name});
                try std.fmt.format(sw, " id:\"{d}\">\n", .{n.id});
                tabs += 1;
            },
            .ff52node => |n| {
                try printTabs(tabs, sw);
                try sw.writeByte('<');
                try sw.writeAll(n.name);
                try sw.writeAll(">\n");
            },
            .ff56node => |n| {
                try printTabs(tabs, sw);
                try std.fmt.format(sw, "<{s}", .{n.name});
                try std.fmt.format(sw, " type:\"{s}\">", .{dTypeMap.get(n.dType).?});
                try printValue(n.value, sw);
                try std.fmt.format(sw, "</{s}>\n", .{n.name});
            },
            .ff70node => |n| {
                tabs -= 1;
                try printTabs(tabs, sw);
                try std.fmt.format(sw, "</{s}>\n", .{n.name});
            },
        }
    }
    return outputString.items;
}

fn printValue(value: nde.dataUnion, sw: anytype) !void {
    switch (value) {
        ._bool => |val| {
                const result:u8 = if (val == true) 1 else 0;
                try std.fmt.format(sw, "{d}", .{result});
        },
        ._sUInt8 => |val| {
                try std.fmt.format(sw, "{d}", .{val});
        },
        ._sInt16 => |val| {
                try std.fmt.format(sw, "{d}", .{val});
        },
        ._sInt32 => |val| {
                try std.fmt.format(sw, "{d}", .{val});
        },
        ._sUInt32 => |val| {
                try std.fmt.format(sw, "{d}", .{val});
        },
        ._sUInt64 => |val| {
                try std.fmt.format(sw, "{d}", .{val});
        },
        ._cDeltaString => |val| {
                try std.fmt.format(sw, "{s}", .{val});
        },
        ._sFloat32 => |val| {
                try formatFloat(val, sw);
        },
    }
}

fn formatFloat(val: f32, writer: anytype) !void {
    if (@fabs(val) <= 1) {
        try std.fmt.format(writer, "{d:.7}", .{val});
    } else if (@fabs(val) < 10) {
        try std.fmt.format(writer, "{d:.5}", .{val});
    } else if (@fabs(val) < 100) {
        try std.fmt.format(writer, "{d:.4}", .{val});
    } else if (@fabs(val) < 1000) {
        try std.fmt.format(writer, "{d:.3}", .{val});
    } else if (@fabs(val) < 10_000) {
        try std.fmt.format(writer, "{d:.2}", .{val});
    } else if (@fabs(val) < 100_000) {
        try std.fmt.format(writer, "{d:.1}", .{val});
    } else if (@fabs(val) < 10_000_000) {
        try std.fmt.format(writer, "{d:.0}", .{val});
    } else {
        try std.fmt.format(writer, "{e:.5}", .{val});
    }
}

fn printTabs (tabs: usize, sw: anytype) !void {
    var i: usize = 0;
    while (i < tabs) : (i += 1) {
        try sw.writeByte('\t');
    }
}

fn initDtypeMap(dTypeMap: *dataTypeMap) !void {
    try dTypeMap.put(nde.dataType._bool, "bool");
    try dTypeMap.put(nde.dataType._sUInt8, "sUInt8");
    try dTypeMap.put(nde.dataType._sInt16, "sInt16");
    try dTypeMap.put(nde.dataType._sInt32, "sInt32");
    try dTypeMap.put(nde.dataType._sUInt32, "sUInt32");
    try dTypeMap.put(nde.dataType._sUInt64, "sUInt64");
    try dTypeMap.put(nde.dataType._sFloat32, "sFloat32");
    try dTypeMap.put(nde.dataType._cDeltaString, "cDeltaString");
}