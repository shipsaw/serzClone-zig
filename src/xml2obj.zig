const std = @import("std");
const n = @import("node.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

const serz = &[_]u8{ 'S', 'E', 'R', 'Z' };
const unknown = &[_]u8{ 0x00, 0x00, 0x01, 0x00 };
const ff41 = &[_]u8{ 0xFF, 0x41 };
const ff4e = &[_]u8{ 0xFF, 0x4e };
const ff50 = &[_]u8{ 0xFF, 0x50 };
const ff52 = &[_]u8{ 0xFF, 0x52 };
const ff56 = &[_]u8{ 0xFF, 0x56 };
const ff70 = &[_]u8{ 0xFF, 0x70 };
const newStr = &[_]u8{ 0xFF, 0xFF };

const stringContext = enum {
    NAME,
    DTYPE,
    VALUE,
};

const strMapType = struct {
    map: std.StringHashMap(u16),
    currentPos: u16,
};

const lineMapType = struct {
    map: std.StringHashMap(u8),
    posMap: std.AutoHashMap(u8, []const u8),
    currentPos: u8,
};

const status = struct {
    current: usize,
    source: std.mem.TokenIterator(u8),
    stringMap: strMapType,
    lineMap: lineMapType,
    resultWriter: std.ArrayList(u8).Writer,

    fn init(src: std.mem.TokenIterator(u8)) status {
        var resultList = std.ArrayList(u8).init(allocator);
        return status{
            .current = 1,
            .source = src,
            .stringMap = strMapType{ .map = std.StringHashMap(u16).init(allocator), .currentPos = 0 },
            .lineMap = lineMapType{
                .map = std.StringHashMap(u8).init(allocator),
                .posMap = std.AutoHashMap(u8, []const u8).init(allocator),
                .currentPos = 0,
            },
            .resultWriter = resultList.writer(),
        };
    }

    fn checkStringMap(self: *status, str: []const u8, ctx: stringContext) ![]const u8 {
        const correctedStr = if (str.len > 0 and str[0] == '_' and ctx == stringContext.VALUE) str[1..] else str;
        var resultArray = std.ArrayList(u8).init(allocator);
        const result: ?u16 = self.stringMap.map.get(correctedStr);
        if (result == null) {
            try self.stringMap.map.put(correctedStr, self.stringMap.currentPos);
            self.stringMap.currentPos += 1;

            const strLen: u32 = @truncate(u32, @bitCast(u64, correctedStr.len));
            try resultArray.appendSlice(&[_]u8{ 0xFF, 0xFF });
            try resultArray.appendSlice(&std.mem.toBytes(strLen));
            try resultArray.appendSlice(correctedStr);
            return resultArray.items;
        } else {
            try resultArray.appendSlice(&std.mem.toBytes(result.?));
            return resultArray.items;
        }
    }

    fn checkLineMap(self: *status, node: n.textNode) !?u8 {
        var nodeAsStr = std.ArrayList(u8).init(allocator);
        switch (node) {
            .ff41NodeT => |nde| {
                try nodeAsStr.appendSlice(ff41);
                try nodeAsStr.appendSlice(nde.name);
                try nodeAsStr.appendSlice(nde.dType);
            },
            .ff50NodeT => |nde| {
                try nodeAsStr.appendSlice(ff50);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff52NodeT => |nde| {
                try nodeAsStr.appendSlice(ff52);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff56NodeT => |nde| {
                try nodeAsStr.appendSlice(ff56);
                try nodeAsStr.appendSlice(nde.name);
                try nodeAsStr.appendSlice(nde.dType);
            },
            .ff70NodeT => |nde| {
                try nodeAsStr.appendSlice(ff70);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff4eNodeT => {
                try nodeAsStr.appendSlice(ff4e);
            },
        }

        const result: ?u8 = self.lineMap.map.get(nodeAsStr.items);
        if (result == null) {
            // Remove the existing entry in the "buffer"
            const lineToRemove = self.lineMap.posMap.get(self.lineMap.currentPos);
            if (lineToRemove != null) {
                _ = self.lineMap.map.remove(lineToRemove.?);
            }

            // Add the new line to the buffer
            try self.lineMap.map.put(nodeAsStr.items, self.lineMap.currentPos);
            try self.lineMap.posMap.put(self.lineMap.currentPos, nodeAsStr.items);
            self.lineMap.currentPos = (self.lineMap.currentPos + 1) % 255;
            return null;
        }
        return result;
    }
};

pub fn parse(inputString: []const u8) ![]const u8 {
    const inputNodes = std.mem.tokenize(u8, inputString, "\n"); // Ignore descriptor line
    var parserStatus = status.init(inputNodes);
    try addPrelude(&parserStatus);
    return "";
}

fn addPrelude(s: *status) !void {
    try s.resultWriter.writeAll(serz);
    try s.resultWriter.writeAll(unknown);
}

fn convert2node(line: []const u8) !n.node {
    const nodeSections = std.mem.tokenize(u8, line, "<>");
    if (nodeSections.buffer.len == 1) { // Can be ff4e, ff50, ff70
        return n.ff4enode{};
    }
}

fn node2string(s: *status, node: n.node) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    var isSavedLine = false;

    const savedLine = try s.checkLineMap(node);
    if (savedLine != null) {
        try s.result.append(savedLine.?);
        isSavedLine = true;
    }

    switch (node) {
        .ff56NodeT => |ff56node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff56);
                try result.appendSlice(try s.checkStringMap(ff56node.name, stringContext.NAME));
                try result.appendSlice(try s.checkStringMap(ff56node.dType, stringContext.VALUE));
            }
            try result.appendSlice(try convertDataUnion(s, ff56node.value, ff56node.dType));
        },
        .ff52NodeT => |ff52node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff52);
                try result.appendSlice(try s.checkStringMap(ff52node.name, stringContext.NAME));
            }
            try result.appendSlice(&std.mem.toBytes(ff52node.value));
        },
        .ff41NodeT => |ff41node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff41);
                try result.appendSlice(try s.checkStringMap(ff41node.name, stringContext.NAME));
                try result.appendSlice(try s.checkStringMap(ff41node.dType, stringContext.DTYPE));
            }
            try result.append(ff41node.numElements);
            for (ff41node.values) |val| {
                try result.appendSlice(try convertDataUnion(s, val, ff41node.dType));
            }
        },
        .ff4eNodeT => {
            if (isSavedLine == false) {
                try result.appendSlice(ff4e);
            }
        },
        .ff50NodeT => |ff50node| {
            const numChildren = @truncate(u32, @bitCast(u64, ff50node.children.len));
            if (isSavedLine == false) {
                try result.appendSlice(ff50);
                try result.appendSlice(try s.checkStringMap(ff50node.name, stringContext.NAME));
            }
            try result.appendSlice(&std.mem.toBytes(ff50node.id));
            try result.appendSlice(&std.mem.toBytes(numChildren));
        },
        .ff70NodeT => |ff70node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff70);
                try result.appendSlice(try s.checkStringMap(ff70node.name, stringContext.NAME));
            }
        },
    }
    return result.items;
}

fn convertDataUnion(s: *status, data: n.dataUnion, expectedType: []const u8) ![]const u8 {
    var returnSlice = std.ArrayList(u8).init(allocator);
    switch (data) {
        ._bool => |bVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(bVal));
        },
        ._sUInt8 => |u8Val| {
            try returnSlice.appendSlice(&std.mem.toBytes(u8Val));
        },
        ._sInt16 => |i16Val| {
            try returnSlice.appendSlice(&std.mem.toBytes(i16Val));
        },
        ._sInt32 => |iVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(iVal));
        },
        ._sUInt32 => |uVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(uVal));
        },
        ._sFloat32 => |fVal| {
            try returnSlice.appendSlice(&std.mem.toBytes(fVal));
        },
        ._sUInt64 => |u64Val| {
            try returnSlice.appendSlice(&std.mem.toBytes(u64Val));
        },
        ._cDeltaString => |sVal| {
            if (std.mem.eql(u8, expectedType, "sFloat32")) { // If "Negative zero" case
                try returnSlice.appendSlice(&[_]u8{ 0x00, 0x00, 0x00, 0x80 });
            } else {
                try returnSlice.appendSlice(try s.checkStringMap(sVal, stringContext.VALUE));
            }
        },
    }
    return returnSlice.items;
}
