const std = @import("std");
const n = @import("node.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);
const dataTypeMap = std.AutoHashMap(n.dataType, []const u8);

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
    result: std.ArrayList(u8),

    fn init(src: std.mem.TokenIterator(u8)) status {

        return status{
            .current = 1,
            .source = src,
            .stringMap = strMapType{ .map = std.StringHashMap(u16).init(allocator), .currentPos = 0 },
            .lineMap = lineMapType{
                .map = std.StringHashMap(u8).init(allocator),
                .posMap = std.AutoHashMap(u8, []const u8).init(allocator),
                .currentPos = 0,
            },
            .result = std.ArrayList(u8).init(allocator),
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

    fn checkLineMap(self: *status, node: n.node, dtm: *dataTypeMap) !?u8 {
        var nodeAsStr = std.ArrayList(u8).init(allocator);
        switch (node) {
            .ff41node => |nde| {
                try nodeAsStr.appendSlice(ff41);
                try nodeAsStr.appendSlice(nde.name);
                try nodeAsStr.appendSlice(dtm.get(nde.dType).?);
            },
            .ff50node => |nde| {
                try nodeAsStr.appendSlice(ff50);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff52node => |nde| {
                std.debug.print("{s}\n", .{nde.name});
                try nodeAsStr.appendSlice(ff52);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff56node => |nde| {
                try nodeAsStr.appendSlice(ff56);
                try nodeAsStr.appendSlice(nde.name);
                try nodeAsStr.appendSlice(dtm.get(nde.dType).?);
            },
            .ff70node => |nde| {
                try nodeAsStr.appendSlice(ff70);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff4enode => {
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
    var inputNodes = std.mem.tokenize(u8, inputString, "\n\t");
    _ = inputNodes.next().?; // Ignore descriptor line
    var parserStatus = status.init(inputNodes);

    var dTypeMap = dataTypeMap.init(allocator);
    try initDtypeMap(&dTypeMap);

    try parseNodes(&parserStatus, &dTypeMap);
    return parserStatus.result.items;
}

fn parseNodes(s: *status, dtm: *dataTypeMap) !void {
    var rw = s.result.writer();
    var currentNode = s.source.next();
    try addPrelude(s);
    
    while (currentNode != null) : (currentNode = s.source.next()) {
        const tempNode = try convert2node(currentNode.?);
        const tempString = try node2string(s, tempNode, dtm);
        try rw.writeAll(tempString);
    }
}

fn addPrelude(s: *status) !void {
    var rw = s.result.writer();
    try rw.writeAll(serz);
    try rw.writeAll(unknown);
}

fn convert2node(line: []const u8) !n.node {
    var nodeSections = std.mem.tokenize(u8, line, "<>");
    if (nodeSections.peek().?[0] == '/') {
        return n.node{ .ff70node = n.ff70node{ .name = try removeDash(nodeSections.next().?[1..])} };
    } else if (std.mem.eql(u8, nodeSections.peek().?, "nil/")) {
        return n.node{ .ff4enode = n.ff4enode{}};
    } else {
        var attrsAndVals = std.mem.tokenize(u8, nodeSections.next().?, " =\"");
        const name = try removeDash(attrsAndVals.next().?);
        if (attrsAndVals.peek() == null) {
            const value = try std.fmt.parseInt(u32, nodeSections.peek().?, 0);
            const newNode = n.ff52node{ .name = name, .value = value };
            return n.node{ .ff52node = newNode};
        } else if (std.mem.eql(u8, attrsAndVals.peek().?, "id")) {
            _ = attrsAndVals.next();
            const id = try std.fmt.parseInt(u32, attrsAndVals.next().?, 0);
            _ = attrsAndVals.next();
            const children = try std.fmt.parseInt(u32, attrsAndVals.next().?, 0);
            const newNode = n.ff50node{ .name = name, .id = id, .children = children};
            return n.node{ .ff50node = newNode};
        } else if (std.mem.eql(u8, attrsAndVals.peek().?, "type")) {
            _ = attrsAndVals.next();
            const dType = n.dataTypeMap.get(attrsAndVals.next().?).?;
            const value = if (nodeSections.peek() == null)
                try convertToDataUnion(dType, "")
                else try convertToDataUnion(dType, nodeSections.next().?);
            const newNode = n.ff56node{ .name = name, .dType = dType, .value = value};
            return n.node{ .ff56node = newNode};
        } else if (std.mem.eql(u8, attrsAndVals.peek().?, "numElements")) {
            var valuesList = std.ArrayList(n.dataUnion).init(allocator);
            _ = attrsAndVals.next();
            const numElements = try std.fmt.parseInt(u8, attrsAndVals.next().?, 0);
            _ = attrsAndVals.next();
            const dType = n.dataTypeMap.get(attrsAndVals.next().?).?;
            
            var values = std.mem.tokenize(u8, nodeSections.next().?, " ");
            var i: usize = 0;
            while (i < numElements) : (i += 1) {
                try valuesList.append(try convertToDataUnion(dType, values.next().?));
            }

            const newNode = n.ff41node{ .name = name, .numElements = numElements, .dType = dType, .values = valuesList};
            return n.node{ .ff41node = newNode};
        }
        return n.node{ .ff4enode = n.ff4enode{}};
    }
}

fn removeDash(name: []const u8) ![]const u8 {
    return (try std.mem.replaceOwned(u8, allocator, name, "-", "::"));
}

fn node2string(s: *status, node: n.node, dtm: *dataTypeMap) ![]const u8 {
    var rw = s.result.writer();
    var result = std.ArrayList(u8).init(allocator);
    var isSavedLine = false;

    const savedLine = try s.checkLineMap(node, dtm);
    if (savedLine != null) {
        try rw.writeByte(savedLine.?);
        isSavedLine = true;
    }

    switch (node) {
        .ff56node => |nde| {
            const dTypeString = dtm.get(nde.dType).?;
            if (isSavedLine == false) {
                try result.appendSlice(ff56);
                try result.appendSlice(try s.checkStringMap(nde.name, stringContext.NAME));
                try result.appendSlice(try s.checkStringMap(dTypeString, stringContext.VALUE));
            }
            try result.appendSlice(try convertDataUnion(s, nde.value, dTypeString));
        },
        .ff52node => |nde| {
            if (isSavedLine == false) {
                try result.appendSlice(ff52);
                try result.appendSlice(try s.checkStringMap(nde.name, stringContext.NAME));
            }
            try result.appendSlice(&std.mem.toBytes(nde.value));
        },
        .ff41node => |nde| {
            const dTypeString = dtm.get(nde.dType).?;
            if (isSavedLine == false) {
                try result.appendSlice(ff41);
                try result.appendSlice(try s.checkStringMap(nde.name, stringContext.NAME));
                try result.appendSlice(try s.checkStringMap(dTypeString, stringContext.DTYPE));
            }
            try result.append(nde.numElements);
            for (nde.values.items) |val| {
                try result.appendSlice(try convertDataUnion(s, val, dTypeString));
            }
        },
        .ff4enode => {
            if (isSavedLine == false) {
                try result.appendSlice(ff4e);
            }
        },
        .ff50node => |nde| {
            if (isSavedLine == false) {
                try result.appendSlice(ff50);
                try result.appendSlice(try s.checkStringMap(nde.name, stringContext.NAME));
            }
            try result.appendSlice(&std.mem.toBytes(nde.id));
            try result.appendSlice(&std.mem.toBytes(nde.children));
        },
        .ff70node => |nde| {
            if (isSavedLine == false) {
                try result.appendSlice(ff70);
                try result.appendSlice(try s.checkStringMap(nde.name, stringContext.NAME));
            }
        },
    }
    return result.items;
}

fn convertToDataUnion(dType: n.dataType, val: []const u8) !n.dataUnion {
    switch (dType) {
        ._bool => {
            const convBool = if (val[0] == '1') true else false;
            return n.dataUnion{ ._bool = convBool };
        },
        ._sUInt8 => {
            const convVal = try std.fmt.parseInt(u8, val, 0);
            return n.dataUnion{ ._sUInt8 = convVal };
        },
        ._sInt16 => {
            const convVal = try std.fmt.parseInt(i16, val, 0);
            return n.dataUnion{ ._sInt16 = convVal };
        },
        ._sInt32 => {
            const convVal = try std.fmt.parseInt(i32, val, 0);
            return n.dataUnion{ ._sInt32 = convVal };
        },
        ._sUInt32 => {
            const convVal = try std.fmt.parseInt(u32, val, 0);
            return n.dataUnion{ ._sUInt32 = convVal };
        },
        ._sFloat32 => {
            const convVal = try std.fmt.parseFloat(f32, val);
            return n.dataUnion{ ._sFloat32 = convVal };
        },
        ._sUInt64 => {
            const convVal = try std.fmt.parseInt(u64, val, 0);
            return n.dataUnion{ ._sUInt64 = convVal };
        },
        ._cDeltaString => {
            return n.dataUnion{ ._cDeltaString = val };
        },
    }
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

fn initDtypeMap(dTypeMap: *dataTypeMap) !void {
    try dTypeMap.put(n.dataType._bool, "bool");
    try dTypeMap.put(n.dataType._sUInt8, "sUInt8");
    try dTypeMap.put(n.dataType._sInt16, "sInt16");
    try dTypeMap.put(n.dataType._sInt32, "sInt32");
    try dTypeMap.put(n.dataType._sUInt32, "sUInt32");
    try dTypeMap.put(n.dataType._sUInt64, "sUInt64");
    try dTypeMap.put(n.dataType._sFloat32, "sFloat32");
    try dTypeMap.put(n.dataType._cDeltaString, "cDeltaString");
}

test "Convert to node, ff41" {
    // Arrange
    const inputLine = "<Scale numElements=\"4\" elementType=\"sFloat32\">1.0000000 2.0000000 3.0000000 4.0000000</Scale>";
    var valuesArray = std.ArrayList(n.dataUnion).init(allocator);
    try valuesArray.append(n.dataUnion{ ._sFloat32 = 1 });
    try valuesArray.append(n.dataUnion{ ._sFloat32 = 2 });
    try valuesArray.append(n.dataUnion{ ._sFloat32 = 3 });
    try valuesArray.append(n.dataUnion{ ._sFloat32 = 4 });
    const expectedNode = n.node{ .ff41node = n.ff41node{ 
        .name = "Scale", 
        .numElements = 4, 
        .dType = n.dataType._sFloat32,
        .values = valuesArray } };

    // Act
    const actual = try convert2node(inputLine);
    // Assert
    try expectEqualSlices(u8, expectedNode.ff41node.name, actual.ff41node.name);
    try expectEqual(expectedNode.ff41node.numElements, actual.ff41node.numElements);
    try expectEqual(expectedNode.ff41node.dType, actual.ff41node.dType);
    try expectEqual(expectedNode.ff41node.values.items[0], actual.ff41node.values.items[0]);
    try expectEqual(expectedNode.ff41node.values.items[1], actual.ff41node.values.items[1]);
    try expectEqual(expectedNode.ff41node.values.items[2], actual.ff41node.values.items[2]);
    try expectEqual(expectedNode.ff41node.values.items[3], actual.ff41node.values.items[3]);
}

test "Convert to node, ff4e" {
    // Arrange
    const inputLine = "<nil/>";
    const expectedNode = n.node{ .ff4enode = n.ff4enode{} };

    // Act
    const actual = try convert2node(inputLine);
    // Assert

    try expectEqual(expectedNode, actual);
}

test "Convert to node, ff50" {
    // Arrange
	const inputLine = "<cConsist id=\"514373264\" children=\"12\">";
    const expectedNode = n.node{ .ff50node = n.ff50node{ 
        .name = "cConsist", 
        .id = 514373264,
        .children = 12,
    } };

    // Act
    const actual = try convert2node(inputLine);
    // Assert
    try expectEqualSlices(u8, expectedNode.ff50node.name, actual.ff50node.name);
    try expectEqual(expectedNode.ff50node.id, actual.ff50node.id);
    try expectEqual(expectedNode.ff50node.children, actual.ff50node.children);
}

test "Convert to node, ff52" {
    // Arrange
	const inputLine = "<cOwnedEntity>526466256</cOwnedEntity>";
    const expectedNode = n.node{ .ff52node = n.ff52node{ 
        .name = "cOwnedEntity", 
        .value = 526466256,
    } };

    // Act
    const actual = try convert2node(inputLine);
    // Assert
    try expectEqualSlices(u8, expectedNode.ff52node.name, actual.ff52node.name);
    try expectEqual(expectedNode.ff52node.value, actual.ff52node.value);
}

test "Convert to node, ff56" {
    // Arrange
	const inputLine = "<Palette2Index type=\"sUInt8\">252</Palette2Index>";
    const expectedNode = n.node{ .ff56node = n.ff56node{ 
        .name = "Palette2Index", 
        .dType = n.dataType._sUInt8,
        .value = n.dataUnion{ ._sUInt8 = 252 } } };

    // Act
    const actual = try convert2node(inputLine);
    // Assert
    try expectEqualSlices(u8, expectedNode.ff56node.name, actual.ff56node.name);
    try expectEqual(expectedNode.ff56node.dType, actual.ff56node.dType);
    try expectEqual(expectedNode.ff56node.value._sUInt8, actual.ff56node.value._sUInt8);
}

test "Convert to node, ff56 with empty string" {
    // Arrange
	const inputLine = "<Palette1Index type=\"cDeltaString\"/>";
    const expectedNode = n.node{ .ff56node = n.ff56node{ 
        .name = "Palette1Index", 
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" } } };

    // Act
    const actual = try convert2node(inputLine);
    // Assert
    try expectEqualSlices(u8, expectedNode.ff56node.name, actual.ff56node.name);
    try expectEqual(expectedNode.ff56node.dType, actual.ff56node.dType);
    try expectEqual(expectedNode.ff56node.value._cDeltaString.len, actual.ff56node.value._cDeltaString.len);
}

test "Convert to node, ff70" {
    // Arrange
	const inputLine = "</Property>";
    const expectedNode = n.node{ .ff70node = n.ff70node{ 
        .name = "Property",
    } };

    // Act
    const actual = try convert2node(inputLine);
    // Assert
    try expectEqualSlices(u8, expectedNode.ff70node.name, actual.ff70node.name);
}

test "Convert to node, ff50 with -" {
    // Arrange
	const inputLine = "<cCon-sist id=\"514373264\" children=\"12\">";
    const expectedNode = n.node{ .ff50node = n.ff50node{ 
        .name = "cCon::sist", 
        .id = 514373264,
        .children = 12,
    } };

    // Act
    const actual = try convert2node(inputLine);
    // Assert
    try expectEqualSlices(u8, expectedNode.ff50node.name, actual.ff50node.name);
    try expectEqual(expectedNode.ff50node.id, actual.ff50node.id);
    try expectEqual(expectedNode.ff50node.children, actual.ff50node.children);
}