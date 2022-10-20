const std = @import("std");
const parser = @import("binParser.zig");
const n = @import("node.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

const textNode = n.textNode;
const ff41NodeT = n.ff41NodeT;
const ff4eNodeT = n.ff4eNodeT;
const ff50NodeT = n.ff50NodeT;
const ff56NodeT = n.ff56NodeT;
const ff70NodeT = n.ff70NodeT;
const dataTypeMap = std.AutoHashMap(n.dataType, []const u8);
const parentStatus = struct {
    childPos: u8,
    parentPointer: *ff50NodeT,
};
const parentStatusStackType = std.ArrayList(parentStatus);

fn sort(nodes: []n.node) !textNode {
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);
    var parentStatusStack = std.ArrayList(parentStatus).init(allocator);

    var rootNode = try convertNode(nodes[0], &dTypeMap);
    try parentStatusStack.append(parentStatus{ .childPos = 0, .parentPointer = &rootNode.ff50NodeT });

    for (nodes[1..]) |node| {
        const parentStackTop = parentStatusStack.items[parentStatusStack.items.len - 1];
        const currentChildPos = parentStackTop.childPos;
        const currentParent = parentStackTop.parentPointer;

        const convertedNode = try convertNode(node, &dTypeMap);
        switch (convertedNode) {
            .ff70NodeT => {
                _ = parentStatusStack.pop();
                continue;
            },
            else => {
                currentParent.children[currentChildPos] = convertedNode;
                try updateParentStack(&parentStatusStack, &currentParent.children[currentChildPos]);
            },
        }
    }
    return rootNode;
}

pub fn main() !void {
    errdefer {
        std.debug.print("OH NO\n", .{});
    }
    var inFile = try std.fs.cwd().openFile("testFiles/Scenario.bin", .{});
    defer inFile.close();
    const outFile = try std.fs.cwd().createFile(
        "results.json",
        .{ .read = true },
    );
    defer outFile.close();
    const testBytes = try inFile.readToEndAlloc(allocator, size_limit);
    var testStatus = parser.status.init(testBytes);

    const nodes = (try parser.parse(&testStatus)).items;

    const textNodesList = try sort(nodes);

    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(textNodesList, .{}, string.writer());
    try outFile.writeAll(string.items);
}

// pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
//     std.debug.print("PANIC\n", .{});
//     std.os.exit(1);
// }

fn convertNode(node: n.node, dTypeMap: *dataTypeMap) !textNode {
    return switch (node) {
        .ff41node => |ff41| textNode{ .ff41NodeT = ff41NodeT{
            .name = ff41.name,
            .dType = dTypeMap.get(ff41.dType).?,
            .numElements = ff41.numElements,
            .values = ff41.values.items,
        } },
        .ff4enode => textNode{ .ff4eNodeT = ff4eNodeT{} },
        .ff50node => |ff50| textNode{ .ff50NodeT = ff50NodeT{
            .name = node.ff50node.name,
            .id = ff50.id,
            .children = (try std.ArrayList(textNode).initCapacity(allocator, ff50.children)).allocatedSlice(),
        } },
        .ff56node => |ff56| textNode{ .ff56NodeT = ff56NodeT{
            .name = ff56.name,
            .dType = dTypeMap.get(ff56.dType).?,
            .value = ff56.value,
        } },
        .ff70node => textNode{ .ff70NodeT = ff70NodeT{ .name = node.ff70node.name } },
    };
}

fn initDtypeMap(dTypeMap: *dataTypeMap) !void {
    try dTypeMap.put(n.dataType._bool, "bool");
    try dTypeMap.put(n.dataType._sUInt8, "sUInt8");
    try dTypeMap.put(n.dataType._sInt32, "sInt32");
    try dTypeMap.put(n.dataType._sUInt64, "sUInt64");
    try dTypeMap.put(n.dataType._sFloat32, "sFloat32");
    try dTypeMap.put(n.dataType._cDeltaString, "cDeltaString");
}

fn updateParentStack(stack: *parentStatusStackType, node: *textNode) !void {
    var currentTop = &stack.items[stack.items.len - 1];
    //std.debug.print("LEN: {any}\n", .{stack.items.len});
    switch (node.*) {
        .ff41NodeT => currentTop.childPos += 1,
        .ff4eNodeT => currentTop.childPos += 1,
        .ff50NodeT => {
            currentTop.childPos += 1;
            try stack.append(parentStatus{ .childPos = 0, .parentPointer = &node.ff50NodeT });
            //std.debug.print("PUSH\n", .{});
        },
        .ff56NodeT => currentTop.childPos += 1,
        .ff70NodeT => unreachable,
    }
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////  Test Area ////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

test "Convert ff41 node" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    var testValues = std.ArrayList(n.dataUnion).init(allocator);
    try testValues.append(n.dataUnion{ ._sInt32 = 1001 });
    try testValues.append(n.dataUnion{ ._sInt32 = 1003 });
    const testNode = n.ff41node{
        .name = "Node1",
        .numElements = 2,
        .dType = n.dataType._sInt32,
        .values = testValues,
    };

    var expectedValues = std.ArrayList(n.dataUnion).init(allocator);
    try expectedValues.append(n.dataUnion{ ._sInt32 = 1001 });
    try expectedValues.append(n.dataUnion{ ._sInt32 = 1003 });

    var expected = ff41NodeT{
        .name = "Node1",
        .numElements = 2,
        .dType = "sInt32",
        .values = expectedValues.items,
    };

    // Act
    var actual = (try convertNode(n.node{ .ff41node = testNode }, &dTypeMap)).ff41NodeT;

    // Assert
    try expectEqualStrings(actual.name, expected.name);
    try expect(actual.numElements == expected.numElements);
    try expectEqualStrings(actual.dType, expected.dType);
    try expect(actual.values[0]._sInt32 == expected.values[0]._sInt32);
    try expect(actual.values[1]._sInt32 == expected.values[1]._sInt32);

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actual, .{}, string.writer());
}

test "Convert ff50 node" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);
    const numChildren = 4;

    const testNode = n.ff50node{
        .name = "Node1",
        .id = 12345,
        .children = numChildren,
    };

    const expectedName = "Node1";
    const expectedId: u32 = 12345;
    const expectedChildrenSlice = 4;

    // Act
    var actual = (try convertNode(n.node{ .ff50node = testNode }, &dTypeMap)).ff50NodeT;

    // Assert
    try expectEqualStrings(actual.name, expectedName);
    try expect(actual.id == expectedId);
    try expect(actual.children.len == expectedChildrenSlice);
}

test "Convert ff50 node with children" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);
    const numChildren = 4;

    const testNode = n.ff50node{
        .name = "Node1",
        .id = 12345,
        .children = numChildren,
    };

    const expectedName = "Node1";
    const expectedId: u32 = 12345;
    const expectedChildrenSlice = 4;

    // Act
    var actual = (try convertNode(n.node{ .ff50node = testNode }, &dTypeMap)).ff50NodeT;
    var i: u8 = 0;
    while (i < numChildren) : (i += 1) {
        actual.children[i] = textNode{ .ff56NodeT = ff56NodeT{ .name = "ChildNode", .dType = "bool", .value = n.dataUnion{ ._bool = true } } };
    }

    // Assert
    try expectEqualStrings(actual.name, expectedName);
    try expect(actual.id == expectedId);
    try expect(actual.children.len == expectedChildrenSlice);
    try expectEqualStrings(actual.children[0].ff56NodeT.name, "ChildNode");

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actual, .{}, string.writer());
}

test "Convert ff4e node" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    const testNode = n.ff4enode{};

    const expectedNode = ff4eNodeT{};

    // Act
    var actual = (try convertNode(n.node{ .ff4enode = testNode }, &dTypeMap)).ff4eNodeT;

    // Assert
    try expect(@TypeOf(actual) == @TypeOf(expectedNode));

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actual, .{}, string.writer());
}

test "Convert ff56 node" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    const testNode = n.ff56node{
        .name = "Node1",
        .dType = n.dataType._sUInt8,
        .value = n.dataUnion{ ._sUInt8 = 15 },
    };

    const expectedName = "Node1";
    const expectedDtype = "sUInt8";
    const expectedValue = 15;

    // Act
    var actual = (try convertNode(n.node{ .ff56node = testNode }, &dTypeMap)).ff56NodeT;

    // Assert
    try expectEqualStrings(actual.name, expectedName);
    try expectEqualStrings(actual.dType, expectedDtype);
    try expect(actual.value._sUInt8 == expectedValue);

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actual, .{}, string.writer());
}

test "Convert ff70 node" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    const testNode = n.ff70node{
        .name = "Node1",
    };

    const expectedName = "Node1";

    // Act
    var actual = (try convertNode(n.node{ .ff70node = testNode }, &dTypeMap)).ff70NodeT;

    // Assert
    try expectEqualStrings(actual.name, expectedName);

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actual, .{}, string.writer());
}

test "sort with one child" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    var testInput = [_]n.node{
        n.node{ .ff50node = n.ff50node{
            .name = "Node1",
            .id = 12345,
            .children = 1,
        } },
        n.node{ .ff56node = n.ff56node{
            .name = "Node2",
            .dType = n.dataType._bool,
            .value = n.dataUnion{ ._bool = false },
        } },
    };

    const rootExpectedName = "Node1";
    const rootExpectedId: u32 = 12345;
    const rootExpectedChildrenSlice = 1;

    const childExpectedName = "Node2";
    const childExpectedType = "bool";
    const childExpectedValue = false;

    // Act
    var actualRootNode = (try sort(testInput[0..])).ff50NodeT;

    // Assert
    try expectEqualStrings(actualRootNode.name, rootExpectedName);
    try expect(actualRootNode.id == rootExpectedId);
    try expect(actualRootNode.children.len == rootExpectedChildrenSlice);

    const actualChildNode = actualRootNode.children[0].ff56NodeT;
    try expectEqualStrings(actualChildNode.name, childExpectedName);
    try expectEqualStrings(actualChildNode.dType, childExpectedType);
    try expect(actualChildNode.value._bool == childExpectedValue);

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actualRootNode, .{}, string.writer());
}

test "sort with two children" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    var testInput = [_]n.node{
        n.node{ .ff50node = n.ff50node{
            .name = "Node1",
            .id = 12345,
            .children = 2,
        } },
        n.node{ .ff56node = n.ff56node{
            .name = "Node2",
            .dType = n.dataType._bool,
            .value = n.dataUnion{ ._bool = false },
        } },
        n.node{ .ff56node = n.ff56node{
            .name = "Node3",
            .dType = n.dataType._bool,
            .value = n.dataUnion{ ._bool = true },
        } },
    };

    const rootExpectedName = "Node1";
    const rootExpectedId: u32 = 12345;
    const rootExpectedChildrenSlice = 2;

    const child1ExpectedName = "Node2";
    const child1ExpectedType = "bool";
    const child1ExpectedValue = false;

    const child2ExpectedName = "Node3";
    const child2ExpectedType = "bool";
    const child2ExpectedValue = true;

    // Act
    var actualRootNode = (try sort(testInput[0..])).ff50NodeT;

    // Assert
    try expectEqualStrings(actualRootNode.name, rootExpectedName);
    try expect(actualRootNode.id == rootExpectedId);
    try expect(actualRootNode.children.len == rootExpectedChildrenSlice);

    const actualChildNode1 = actualRootNode.children[0].ff56NodeT;
    try expectEqualStrings(actualChildNode1.name, child1ExpectedName);
    try expectEqualStrings(actualChildNode1.dType, child1ExpectedType);
    try expect(actualChildNode1.value._bool == child1ExpectedValue);

    const actualChildNode2 = actualRootNode.children[1].ff56NodeT;
    try expectEqualStrings(actualChildNode2.name, child2ExpectedName);
    try expectEqualStrings(actualChildNode2.dType, child2ExpectedType);
    try expect(actualChildNode2.value._bool == child2ExpectedValue);

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actualRootNode, .{}, string.writer());
}

test "sort 3 nesting layers" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    var testInput = [_]n.node{
        n.node{ .ff50node = n.ff50node{
            .name = "Node1",
            .id = 12345,
            .children = 1,
        } },
        n.node{ .ff50node = n.ff50node{
            .name = "Node2",
            .id = 99999,
            .children = 1,
        } },
        n.node{ .ff56node = n.ff56node{
            .name = "Node3",
            .dType = n.dataType._bool,
            .value = n.dataUnion{ ._bool = true },
        } },
    };

    const rootExpectedName = "Node1";
    const rootExpectedId: u32 = 12345;
    const rootExpectedChildrenSlice = 1;

    const child1ExpectedName = "Node2";
    const child1ExpectedId: u32 = 99999;
    const child1ExpectedChildrenSlice = 1;

    const child2ExpectedName = "Node3";
    const child2ExpectedType = "bool";
    const child2ExpectedValue = true;

    // Act
    var actualRootNode = (try sort(testInput[0..])).ff50NodeT;

    // Assert
    try expectEqualStrings(actualRootNode.name, rootExpectedName);
    try expect(actualRootNode.id == rootExpectedId);
    try expect(actualRootNode.children.len == rootExpectedChildrenSlice);

    const actualChildNode1 = actualRootNode.children[0].ff50NodeT;
    try expectEqualStrings(actualChildNode1.name, child1ExpectedName);
    try expect(actualChildNode1.id == child1ExpectedId);
    try expect(actualChildNode1.children.len == child1ExpectedChildrenSlice);

    const actualChildNode2 = actualChildNode1.children[0].ff56NodeT;
    try expectEqualStrings(actualChildNode2.name, child2ExpectedName);
    try expectEqualStrings(actualChildNode2.dType, child2ExpectedType);
    try expect(actualChildNode2.value._bool == child2ExpectedValue);

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actualRootNode, .{}, string.writer());
}

test "sort with closing ff70" {
    // Arrange
    var dTypeMap = std.AutoHashMap(n.dataType, []const u8).init(allocator);
    try initDtypeMap(&dTypeMap);

    var testInput = [_]n.node{
        n.node{ .ff50node = n.ff50node{
            .name = "Parent1",
            .id = 12345,
            .children = 1,
        } },
        n.node{ .ff50node = n.ff50node{
            .name = "Parent2",
            .id = 99999,
            .children = 1,
        } },
        n.node{ .ff56node = n.ff56node{
            .name = "Child",
            .dType = n.dataType._bool,
            .value = n.dataUnion{ ._bool = true },
        } },
        n.node{ .ff70node = n.ff70node{
            .name = "Close",
        } },
    };

    const rootExpectedName = "Parent1";
    const rootExpectedId: u32 = 12345;
    const rootExpectedChildrenSlice = 1;

    const child1ExpectedName = "Parent2";
    const child1ExpectedId: u32 = 99999;
    const child1ExpectedChildrenSlice = 1;

    const child2ExpectedName = "Child";
    const child2ExpectedType = "bool";
    const child2ExpectedValue = true;

    // Act
    var actualRootNode = (try sort(testInput[0..])).ff50NodeT;

    // Assert
    try expectEqualStrings(actualRootNode.name, rootExpectedName);
    try expect(actualRootNode.id == rootExpectedId);
    try expect(actualRootNode.children.len == rootExpectedChildrenSlice);

    const actualChildNode1 = actualRootNode.children[0].ff50NodeT;
    try expectEqualStrings(actualChildNode1.name, child1ExpectedName);
    try expect(actualChildNode1.id == child1ExpectedId);
    try expect(actualChildNode1.children.len == child1ExpectedChildrenSlice);

    const actualChildNode2 = actualChildNode1.children[0].ff56NodeT;
    try expectEqualStrings(actualChildNode2.name, child2ExpectedName);
    try expectEqualStrings(actualChildNode2.dType, child2ExpectedType);
    try expect(actualChildNode2.value._bool == child2ExpectedValue);

    // test JSON Stringify
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(actualRootNode, .{}, string.writer());
}
