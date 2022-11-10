const std = @import("std");
const n = @import("node.zig");
const sm = @import("scenarioModel.zig");
const json = @import("custom_json.zig");
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
    stringMap: strMapType,
    lineMap: lineMapType,
    result: std.ArrayList(u8),
    dataTypeMap: dataTypeMap,

    fn init() !status {
        var dTypeMap = dataTypeMap.init(allocator);
        try initDtypeMap(&dTypeMap);
        return status{
            .current = 0,
            .stringMap = strMapType{ .map = std.StringHashMap(u16).init(allocator), .currentPos = 0 },
            .lineMap = lineMapType{
                .map = std.StringHashMap(u8).init(allocator),
                .posMap = std.AutoHashMap(u8, []const u8).init(allocator),
                .currentPos = 0,
            },
            .result = std.ArrayList(u8).init(allocator),
            .dataTypeMap = dTypeMap,
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

    fn checkLineMap(self: *status, node: n.node) !?u8 {
        var nodeAsStr = std.ArrayList(u8).init(allocator);
        switch (node) {
            .ff41node => |nde| {
                try nodeAsStr.appendSlice(ff41);
                try nodeAsStr.appendSlice(nde.name);
                try nodeAsStr.appendSlice(self.dataTypeMap.get(nde.dType).?);
            },
            .ff50node => |nde| {
                try nodeAsStr.appendSlice(ff50);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff52node => |nde| {
                try nodeAsStr.appendSlice(ff52);
                try nodeAsStr.appendSlice(nde.name);
            },
            .ff56node => |nde| {
                try nodeAsStr.appendSlice(ff56);
                try nodeAsStr.appendSlice(nde.name);
                try nodeAsStr.appendSlice(self.dataTypeMap.get(nde.dType).?);
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

    fn append_ff41Node(self: *status, data: anytype, name: []const u8) !void {
        try self.result.appendSlice(try convertNode(self, try make_ff41Node(data, name)));
    }

    fn append_ff4eNode(self: *status) !void {
        try self.result.appendSlice(try convertNode(self, make_ff4eNode()));
    }

    fn append_ff50Node(self: *status, name: []const u8, id: u32, children: usize) !void {
        const childrenCast = @intCast(u32, children);
        try self.result.appendSlice(try convertNode(self, make_ff50Node(name, id, childrenCast)));
    }

    fn append_ff56Node(self: *status, data: anytype, name: []const u8) !void {
        try self.result.appendSlice(try convertNode(self, make_ff56Node(data, name)));
    }

    fn append_eNode56(self: *status, value: anytype, typeStr: []const u8) !void {
        const tempNode = n.node{ .ff56node = n.ff56node{ .name = "e", .dType = n.dataTypeMap.get(typeStr).?, .value = boxDataUnionType(value) } };
        try self.result.appendSlice(try convertNode(self, tempNode));
    }

    //     fn append_eNode41(self: *status, value: anytype, typeStr: []const u8) !void {
    //         var valuesList = std.ArrayList(n.dataUnion).init(allocator);
    //         for (value) |val| {
    //             try valuesList.append(boxDataUnionType(val));
    //         }
    //         const tempNode = n.node{ .ff41node = n.ff41node{ .name = "e", .numElements = @intCast(u8, valuesList.items.len), .dType = n.dataTypeMap.get(typeStr).?, .values = valuesList } };
    //         try self.result.appendSlice(try convertNode(self, tempNode));
    //     }

    fn append_ff70Node(self: *status, name: []const u8) !void {
        try self.result.appendSlice(try convertNode(self, make_ff70Node(name)));
    }
};

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

pub fn parse(inputString: []const u8) ![]const u8 {
    var stream = json.TokenStream.init(inputString);
    var rootNode = try json.parse(sm.cRecordSet, &stream, .{ .allocator = allocator });
    var parserStatus = try status.init();
    try addPrelude(&parserStatus);
    try parse_cRecordSet(&parserStatus, rootNode);
    //try walkNodes(&parserStatus);
    return parserStatus.result.items;
}

fn addPrelude(s: *status) !void {
    try s.result.appendSlice(serz);
    try s.result.appendSlice(unknown);
}

// fn walkNodes(s: *status, parentNode: n.textNode) !void {
//     try s.result.appendSlice(try convertTnode(s, parentNode));
//     for (parentNode.ff50NodeT.children) |child| {
//         switch (child) {
//             .ff50NodeT => try walkNodes(s, child),
//             else => |node| try s.result.appendSlice(try convertTnode(s, node)),
//         }
//     }
//     const closingNode = n.textNode{ .ff70NodeT = n.ff70NodeT{ .name = parentNode.ff50NodeT.name } };
//     try s.result.appendSlice(try convertTnode(s, closingNode));
// }

fn convertNode(s: *status, node: n.node) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    var isSavedLine = false;

    const savedLine = try s.checkLineMap(node);
    if (savedLine != null) {
        try s.result.append(savedLine.?);
        isSavedLine = true;
    }

    switch (node) {
        .ff56node => |ff56node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff56);
                try result.appendSlice(try s.checkStringMap(ff56node.name, stringContext.NAME));
                try result.appendSlice(try s.checkStringMap(s.dataTypeMap.get(ff56node.dType).?, stringContext.VALUE));
            }
            try result.appendSlice(try convertDataUnion(s, ff56node.value));
        },
        .ff52node => |ff52node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff52);
                try result.appendSlice(try s.checkStringMap(ff52node.name, stringContext.NAME));
            }
            try result.appendSlice(&std.mem.toBytes(ff52node.value));
        },
        .ff41node => |ff41node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff41);
                try result.appendSlice(try s.checkStringMap(ff41node.name, stringContext.NAME));
                try result.appendSlice(try s.checkStringMap(s.dataTypeMap.get(ff41node.dType).?, stringContext.DTYPE));
            }
            try result.append(ff41node.numElements);
            for (ff41node.values.items) |val| {
                try result.appendSlice(try convertDataUnion(s, val));
            }
        },
        .ff4enode => {
            if (isSavedLine == false) {
                try result.appendSlice(ff4e);
            }
        },
        .ff50node => |ff50node| {
            const numChildren = ff50node.children;
            if (isSavedLine == false) {
                try result.appendSlice(ff50);
                try result.appendSlice(try s.checkStringMap(ff50node.name, stringContext.NAME));
            }
            try result.appendSlice(&std.mem.toBytes(ff50node.id));
            try result.appendSlice(&std.mem.toBytes(numChildren));
        },
        .ff70node => |ff70node| {
            if (isSavedLine == false) {
                try result.appendSlice(ff70);
                try result.appendSlice(try s.checkStringMap(ff70node.name, stringContext.NAME));
            }
        },
    }
    return result.items;
}

fn convertDataUnion(s: *status, data: n.dataUnion) ![]const u8 {
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
            try returnSlice.appendSlice(try s.checkStringMap(sVal, stringContext.VALUE));
        },
    }
    return returnSlice.items;
}

fn boxDataUnionType(val: anytype) n.dataUnion {
    return switch (@TypeOf(val)) {
        []const u8 => n.dataUnion{ ._cDeltaString = val },
        bool => n.dataUnion{ ._bool = val },
        u8 => n.dataUnion{ ._sUInt8 = val },
        i16 => n.dataUnion{ ._sInt16 = val },
        i32 => n.dataUnion{ ._sInt32 = val },
        u32 => n.dataUnion{ ._sUInt32 = val },
        u64 => n.dataUnion{ ._sUInt64 = val },
        f32 => n.dataUnion{ ._sFloat32 = val },
        else => unreachable,
    };
}

fn getDataUnionType(val: anytype) n.dataType {
    return switch (@TypeOf(val)) {
        []const u8 => n.dataType._cDeltaString,
        bool => n.dataType._bool,
        u8 => n.dataType._sUInt8,
        i16 => n.dataType._sInt16,
        i32 => n.dataType._sInt32,
        u32 => n.dataType._sUInt32,
        u64 => n.dataType._sUInt64,
        f32 => n.dataType._sFloat32,
        else => unreachable,
    };
}

fn getDataUnionStr(val: anytype) []const u8 {
    return switch (@TypeOf(val)) {
        []const u8 => "cDeltaString",
        bool => "bool",
        u8 => "sUInt8",
        i16 => "sInt16",
        i32 => "sInt32",
        u32 => "sUInt32",
        u64 => "sUInt64",
        f32 => "sFloat32",
        else => unreachable,
    };
}

fn make_ff41Node(values: anytype, name: []const u8) !n.node {
    const dataUnionType = getDataUnionType(values[0]);
    var valuesArray = std.ArrayList(n.dataUnion).init(allocator);
    for (values) |val| {
        try valuesArray.append(boxDataUnionType(val));
    }

    return n.node{ .ff41node = n.ff41node{ .name = name, .numElements = @intCast(u8, values.len), .dType = dataUnionType, .values = valuesArray } };
}

fn make_ff4eNode() n.node {
    return n.node{ .ff4enode = n.ff4enode{} };
}

fn make_ff50Node(name: []const u8, id: u32, children: u32) n.node {
    return n.node{ .ff50node = n.ff50node{ .name = name, .id = id, .children = children } };
}

fn make_ff56Node(value: anytype, name: []const u8) n.node {
    const dataUnionType = getDataUnionType(value);
    const dataUnionVal = boxDataUnionType(value);
    return n.node{ .ff56node = n.ff56node{ .name = name, .dType = dataUnionType, .value = dataUnionVal } };
}

fn make_ff70Node(name: []const u8) n.node {
    return n.node{ .ff70node = n.ff70node{ .name = name } };
}

//////////////////////////// NEW ////////////////////////////////////
fn parse_sTimeOfDay(s: *status, nde: sm.sTimeOfDay) !void {
    try s.append_ff50Node("sTimeOfDay", 0, 3);
    try s.append_ff56Node(nde._iHour, "_iHour");
    try s.append_ff56Node(nde._iMinute, "_iMinute");
    try s.append_ff56Node(nde._iSeconds, "_iSeconds");
    try s.append_ff70Node("sTimeOfDay");
}

fn parse_parseLocalisation_cUserLocalisedString(s: *status, nde: sm.Localisation_cUserLocalisedString) !void {
    try s.append_ff50Node("Localisation::cUserLocalisedString", 0, 10);
    try s.append_ff56Node(nde.English, "English");
    try s.append_ff56Node(nde.French, "French");
    try s.append_ff56Node(nde.Italian, "Italian");
    try s.append_ff56Node(nde.German, "German");
    try s.append_ff56Node(nde.Spanish, "Spanish");
    try s.append_ff56Node(nde.Dutch, "Dutch");
    try s.append_ff56Node(nde.Polish, "Polish");
    try s.append_ff56Node(nde.Russian, "Russian");

    // TODO: Other Logic
    try s.append_ff50Node("Other", 0, 0);
    try s.append_ff70Node("Other");

    try s.append_ff56Node(nde.Key, "Key");
    try s.append_ff70Node("Localisation::cUserLocalisedString");
}

fn parse_cGUID(s: *status, nde: sm.cGUID) !void {
    try s.append_ff50Node("cGUID", 0, 2);
    try s.append_ff50Node("UUID", 0, 2);
    try s.append_eNode56(nde.UUID[0], "sUInt64");
    try s.append_eNode56(nde.UUID[1], "sUInt64");
    try s.append_ff70Node("UUID");
    try s.append_ff56Node(nde.DevString, "DevString");
    try s.append_ff70Node("cGUID");
}

fn parse_DriverInstruction(s: *status, nde: sm.DriverInstruction) !void {
    try switch (nde) {
        .cTriggerInstruction => |instruction| parse_cTriggerInstruction(s, instruction),
        .cStopAtDestination => |instruction| parse_cStopAtDestination(s, instruction),
        .cConsistOperation => |instruction| parse_cConsistOperation(s, instruction),
        .cPickupPassengers => |instruction| parse_cPickupPassengers(s, instruction),
    };
}

fn parse_cDriverInstructionTarget(s: *status, nde: ?sm.cDriverInstructionTarget) !void {
    if (nde == null) {
        return;
    }
    try s.append_ff50Node("cDriverInstructionTarget", nde.?.Id, 28);
    try s.append_ff56Node(nde.?.DisplayName, "DisplayName");
    try s.append_ff56Node(nde.?.Timetabled, "Timetabled");
    try s.append_ff56Node(nde.?.Performance, "Performance");
    try s.append_ff56Node(nde.?.MinSpeed, "MinSpeed");
    try s.append_ff56Node(nde.?.DurationSecs, "DurationSecs");
    try s.append_ff56Node(nde.?.EntityName, "EntityName");
    try s.append_ff56Node(nde.?.TrainOrder, "TrainOrder");
    try s.append_ff56Node(nde.?.Operation, "Operation");

    try s.append_ff50Node("Deadline", 0, 1);
    try parse_sTimeOfDay(s, nde.?.Deadline);
    try s.append_ff70Node("Deadline");

    try s.append_ff56Node(nde.?.PickingUp, "PickingUp");
    try s.append_ff56Node(nde.?.Duration, "Duration");
    try s.append_ff56Node(nde.?.HandleOffPath, "HandleOffPath");
    try s.append_ff56Node(nde.?.EarliestDepartureTime, "EarliestDepartureTime");
    try s.append_ff56Node(nde.?.DurationSet, "DurationSet");
    try s.append_ff56Node(nde.?.ReversingAllowed, "ReversingAllowed");
    try s.append_ff56Node(nde.?.Waypoint, "Waypoint");
    try s.append_ff56Node(nde.?.Hidden, "Hidden");
    try s.append_ff56Node(nde.?.ProgressCode, "ProgressCode");
    try s.append_ff56Node(nde.?.ArrivalTime, "ArrivalTime");
    try s.append_ff56Node(nde.?.DepartureTime, "DepartureTime");
    try s.append_ff56Node(nde.?.TickedTime, "TickedTime");
    try s.append_ff56Node(nde.?.DueTime, "DueTime");

    try s.append_ff50Node("RailVehicleNumber", 0, nde.?.RailVehicleNumber.len);
    for (nde.?.RailVehicleNumber) |num| {
        std.debug.print("{s}\n", .{num});
        try s.append_eNode56(num, "cDeltaString");
    }
    try s.append_ff70Node("RailVehicleNumber");

    try s.append_ff56Node(nde.?.TimingTestTime, "TimingTestTime");

    try s.append_ff50Node("GroupName", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.?.GroupName);
    try s.append_ff70Node("GroupName");

    try s.append_ff56Node(nde.?.ShowRVNumbersWithGroup, "ShowRVNumbersWithGroup");
    try s.append_ff56Node(nde.?.ScenarioChainTarget, "ScenarioChainTarget");

    try s.append_ff50Node("ScenarioChainGUID", 0, 1);
    try parse_cGUID(s, nde.?.ScenarioChainGUID);
    try s.append_ff70Node("ScenarioChainGUID");

    try s.append_ff70Node("cDriverInstructionTarget");
}

fn parse_cPickupPassengers(s: *status, nde: sm.cPickupPassengers) !void {
    try s.append_ff50Node("cPickupPassengers", nde.Id, 24);
    try s.append_ff56Node(nde.ActivationLevel, "ActivationLevel");
    try s.append_ff56Node(nde.SuccessTextToBeSavedMessage, "SuccessTextToBeSavedMessage");
    try s.append_ff56Node(nde.FailureTextToBeSavedMessage, "FailureTextToBeSavedMessage");
    try s.append_ff56Node(nde.DisplayTextToBeSavedMessage, "DisplayTextToBeSavedMessage");

    try s.append_ff50Node("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try s.append_ff70Node("TriggeredText");

    try s.append_ff50Node("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try s.append_ff70Node("UntriggeredText");

    try s.append_ff50Node("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try s.append_ff70Node("DisplayText");

    try s.append_ff56Node(nde.TriggerTrainStop, "TriggerTrainStop");
    try s.append_ff56Node(nde.TriggerWheelSlip, "TriggerWheelSlip");
    try s.append_ff56Node(nde.WheelSlipDuration, "WheelSlipDuration");

    try s.append_ff50Node("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggerSound);
    try s.append_ff70Node("TriggerSound");

    try s.append_ff50Node("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggerAnimation);
    try s.append_ff70Node("TriggerAnimation");

    try s.append_ff56Node(nde.SecondsDelay, "SecondsDelay");
    try s.append_ff56Node(nde.Active, "Active");

    try s.append_ff50Node("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try s.append_ff70Node("ArriveTime");

    try s.append_ff50Node("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try s.append_ff70Node("DepartTime");

    try s.append_ff56Node(nde.Condition, "Condition");
    try s.append_ff56Node(nde.SuccessEvent, "SuccessEvent");
    try s.append_ff56Node(nde.FailureEvent, "FailureEvent");
    try s.append_ff56Node(nde.Started, "Started");
    try s.append_ff56Node(nde.Satisfied, "Satisfied");

    try s.append_ff50Node("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try s.append_ff70Node("DeltaTarget");

    try s.append_ff56Node(nde.TravelForwards, "TravelForwards");
    try s.append_ff56Node(nde.UnloadPassengers, "UnloadPassengers");

    try s.append_ff70Node("cPickupPassengers");
}

fn parse_cConsistOperation(s: *status, nde: sm.cConsistOperation) !void {
    try s.append_ff50Node("cConsistOperations", nde.Id, 27);
    try s.append_ff56Node(nde.ActivationLevel, "ActivationLevel");
    try s.append_ff56Node(nde.SuccessTextToBeSavedMessage, "SuccessTextToBeSavedMessage");
    try s.append_ff56Node(nde.FailureTextToBeSavedMessage, "FailureTextToBeSavedMessage");
    try s.append_ff56Node(nde.DisplayTextToBeSavedMessage, "DisplayTextToBeSavedMessage");

    try s.append_ff50Node("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try s.append_ff70Node("TriggeredText");

    try s.append_ff50Node("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try s.append_ff70Node("UntriggeredText");

    try s.append_ff50Node("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try s.append_ff70Node("DisplayText");

    try s.append_ff56Node(nde.TriggerTrainStop, "TriggerTrainStop");
    try s.append_ff56Node(nde.TriggerWheelSlip, "TriggerWheelSlip");
    try s.append_ff56Node(nde.WheelSlipDuration, "WheelSlipDuration");

    try s.append_ff50Node("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggerSound);
    try s.append_ff70Node("TriggerSound");

    try s.append_ff50Node("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggerAnimation);
    try s.append_ff70Node("TriggerAnimation");

    try s.append_ff56Node(nde.SecondsDelay, "SecondsDelay");
    try s.append_ff56Node(nde.Active, "Active");

    try s.append_ff50Node("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try s.append_ff70Node("ArriveTime");

    try s.append_ff50Node("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try s.append_ff70Node("DepartTime");

    try s.append_ff56Node(nde.Condition, "Condition");
    try s.append_ff56Node(nde.SuccessEvent, "SuccessEvent");
    try s.append_ff56Node(nde.FailureEvent, "FailureEvent");
    try s.append_ff56Node(nde.Started, "Started");
    try s.append_ff56Node(nde.Satisfied, "Satisfied");

    try s.append_ff50Node("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try s.append_ff70Node("DeltaTarget");

    try s.append_ff56Node(nde.OperationOrder, "OperationOrder");
    try s.append_ff56Node(nde.FirstUpdateDone, "FirstUpdateDone");
    try s.append_ff56Node(nde.LastCompletedTargetIndex, "LastCompletedTargetIndex");
    try s.append_ff56Node(nde.CurrentTargetIndex, "CurrentTargetIndex");
    try s.append_ff56Node(nde.TargetCompletedTime, "TargetCompletedTime");

    try s.append_ff70Node("cConsistOperations");
}

fn parse_cStopAtDestination(s: *status, nde: sm.cStopAtDestination) !void {
    try s.append_ff50Node("cStopAtDestinations", nde.Id, 23);
    try s.append_ff56Node(nde.ActivationLevel, "ActivationLevel");
    try s.append_ff56Node(nde.SuccessTextToBeSavedMessage, "SuccessTextToBeSavedMessage");
    try s.append_ff56Node(nde.FailureTextToBeSavedMessage, "FailureTextToBeSavedMessage");
    try s.append_ff56Node(nde.DisplayTextToBeSavedMessage, "DisplayTextToBeSavedMessage");

    try s.append_ff50Node("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try s.append_ff70Node("TriggeredText");

    try s.append_ff50Node("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try s.append_ff70Node("UntriggeredText");

    try s.append_ff50Node("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try s.append_ff70Node("DisplayText");

    try s.append_ff56Node(nde.TriggerTrainStop, "TriggerTrainStop");
    try s.append_ff56Node(nde.TriggerWheelSlip, "TriggerWheelSlip");
    try s.append_ff56Node(nde.WheelSlipDuration, "WheelSlipDuration");

    try s.append_ff50Node("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggerSound);
    try s.append_ff70Node("TriggerSound");

    try s.append_ff50Node("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggerAnimation);
    try s.append_ff70Node("TriggerAnimation");

    try s.append_ff56Node(nde.SecondsDelay, "SecondsDelay");
    try s.append_ff56Node(nde.Active, "Active");

    try s.append_ff50Node("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try s.append_ff70Node("ArriveTime");

    try s.append_ff50Node("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try s.append_ff70Node("DepartTime");

    try s.append_ff56Node(nde.Condition, "Condition");
    try s.append_ff56Node(nde.SuccessEvent, "SuccessEvent");
    try s.append_ff56Node(nde.FailureEvent, "FailureEvent");
    try s.append_ff56Node(nde.Started, "Started");
    try s.append_ff56Node(nde.Satisfied, "Satisfied");

    try s.append_ff50Node("DeltaTarget", 0, nde.DeltaTarget.?.len);
    for (nde.DeltaTarget.?) |instruction| {
        try parse_cDriverInstructionTarget(s, instruction);
    }
    try s.append_ff70Node("DeltaTarget");

    try s.append_ff56Node(nde.TravelForwards, "TravelForwards");

    try s.append_ff70Node("cStopAtDestinations");
}

fn parse_cTriggerInstruction(s: *status, nde: sm.cTriggerInstruction) !void {
    try s.append_ff50Node("cTriggerInstruction", nde.Id, 23);
    try s.append_ff56Node(nde.ActivationLevel, "ActivationLevel");
    try s.append_ff56Node(nde.SuccessTextToBeSavedMessage, "SuccessTextToBeSavedMessage");
    try s.append_ff56Node(nde.FailureTextToBeSavedMessage, "FailureTextToBeSavedMessage");
    try s.append_ff56Node(nde.DisplayTextToBeSavedMessage, "DisplayTextToBeSavedMessage");

    try s.append_ff50Node("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try s.append_ff70Node("TriggeredText");

    try s.append_ff50Node("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try s.append_ff70Node("UntriggeredText");

    try s.append_ff50Node("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try s.append_ff70Node("DisplayText");

    try s.append_ff56Node(nde.TriggerTrainStop, "TriggerTrainStop");
    try s.append_ff56Node(nde.TriggerWheelSlip, "TriggerWheelSlip");
    try s.append_ff56Node(nde.WheelSlipDuration, "WheelSlipDuration");

    try s.append_ff50Node("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggerSound);
    try s.append_ff70Node("TriggerSound");

    try s.append_ff50Node("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggerAnimation);
    try s.append_ff70Node("TriggerAnimation");

    try s.append_ff56Node(nde.SecondsDelay, "SecondsDelay");
    try s.append_ff56Node(nde.Active, "Active");

    try s.append_ff50Node("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try s.append_ff70Node("ArriveTime");

    try s.append_ff50Node("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try s.append_ff70Node("DepartTime");

    try s.append_ff56Node(nde.Condition, "Condition");
    try s.append_ff56Node(nde.SuccessEvent, "SuccessEvent");
    try s.append_ff56Node(nde.FailureEvent, "FailureEvent");
    try s.append_ff56Node(nde.Started, "Started");
    try s.append_ff56Node(nde.Satisfied, "Satisfied");

    try s.append_ff50Node("DeltaTarget", 0, if (nde.DeltaTarget != null) 1 else 0);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try s.append_ff70Node("DeltaTarget");

    try s.append_ff56Node(nde.StartTime, "StartTime");

    try s.append_ff70Node("cTriggerInstruction");
}

fn parse_cDriverInstructionContainer(s: *status, nde: sm.cDriverInstructionContainer) !void {
    try s.append_ff50Node("cDriverInstructionContainer", nde.Id, 1);
    try s.append_ff50Node("DriverInstruction", 0, nde.DriverInstruction.len);
    for (nde.DriverInstruction) |instruction| {
        try parse_DriverInstruction(s, instruction);
    }
    try s.append_ff70Node("DriverInstruction");
    try s.append_ff70Node("cDriverInstructionContainer");
}

fn parse_cDriver(s: *status, nde: ?sm.cDriver) !void {
    if (nde == null) {
        return;
    }

    try s.append_ff50Node("cDriver", nde.?.Id, 18);

    try s.append_ff50Node("FinalDestination", 0, 1);
    if (nde.?.FinalDestination == null) {
        try s.append_ff4eNode();
    } else {
        try parse_cDriverInstructionTarget(s, nde.?.FinalDestination);
    }
    try s.append_ff70Node("FinalDestination");

    try s.append_ff56Node(nde.?.PlayerDriver, "PlayerDriver");

    try s.append_ff50Node("ServiceName", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.?.ServiceName);
    try s.append_ff70Node("ServiceName");

    try s.append_ff50Node("InitialRV", 0, nde.?.InitialRV.len);
    for (nde.?.InitialRV) |val| {
        try s.append_eNode56(val, "cDeltaString");
    }
    try s.append_ff70Node("InitialRV");

    try s.append_ff56Node(nde.?.StartTime, "StartTime");
    try s.append_ff56Node(nde.?.StartSpeed, "StartSpeed");
    try s.append_ff56Node(nde.?.EndSpeed, "EndSpeed");
    try s.append_ff56Node(nde.?.ServiceClass, "ServiceClass");
    try s.append_ff56Node(nde.?.ExpectedPerformance, "ExpectedPerformance");
    try s.append_ff56Node(nde.?.PlayerControlled, "PlayerControlled");
    try s.append_ff56Node(nde.?.PriorPathingStatus, "PriorPathingStatus");
    try s.append_ff56Node(nde.?.PathingStatus, "PathingStatus");
    try s.append_ff56Node(nde.?.RepathIn, "RepathIn");
    try s.append_ff56Node(nde.?.ForcedRepath, "ForcedRepath");
    try s.append_ff56Node(nde.?.OffPath, "OffPath");
    try s.append_ff56Node(nde.?.StartTriggerDistanceFromPlayerSquared, "StartTriggerDistanceFromPlayerSquared");

    try s.append_ff50Node("DriverInstructionContainer", 0, 1);
    try parse_cDriverInstructionContainer(s, nde.?.DriverInstructionContainer);
    try s.append_ff70Node("DriverInstructionContainer");

    try s.append_ff56Node(nde.?.UnloadedAtStart, "UnloadedAtStart");

    try s.append_ff70Node("cDriver");
}

fn parse_cRouteCoordinate(s: *status, nde: sm.cRouteCoordinate) !void {
    try s.append_ff50Node("RouteCoordinate", 0, 1);
    try s.append_ff50Node("cRouteCoordinate", 0, 1);
    try s.append_ff56Node(nde.Distance, "Distance");
    try s.append_ff70Node("cRouteCoordinate");
    try s.append_ff70Node("RouteCoordinate");
}

fn parse_cTileCoordinate(s: *status, nde: sm.cTileCoordinate) !void {
    try s.append_ff50Node("TileCoordinate", 0, 1);
    try s.append_ff50Node("cTileCoordinate", 0, 1);
    try s.append_ff56Node(nde.Distance, "Distance");
    try s.append_ff70Node("cTileCoordinate");
    try s.append_ff70Node("TileCoordinate");
}

fn parse_cFarCoordinate(s: *status, nde: sm.cFarCoordinate) !void {
    try s.append_ff50Node("cFarCoordinate", 0, 2);
    try parse_cRouteCoordinate(s, nde.RouteCoordinate);
    try parse_cTileCoordinate(s, nde.TileCoordinate);
    try s.append_ff70Node("cFarCoordinate");
}

fn parse_cFarVector2(s: *status, nde: sm.cFarVector2) !void {
    try s.append_ff50Node("cFarVector2", nde.Id, 2);

    try s.append_ff50Node("X", 0, 1);
    try parse_cFarCoordinate(s, nde.X);
    try s.append_ff70Node("X");

    try s.append_ff50Node("Z", 0, 1);
    try parse_cFarCoordinate(s, nde.Z);
    try s.append_ff70Node("Z");

    try s.append_ff70Node("cFarVector2");
}

fn parse_Network_cDirection(s: *status, nde: sm.Network_cDirection) !void {
    try s.append_ff50Node("Network::cDirection", 0, 1);
    try s.append_ff56Node(nde._dir, "_dir");
    try s.append_ff70Node("Network::cDirection");
}

fn parse_Network_cTrackFollower(s: *status, nde: sm.Network_cTrackFollower) !void {
    try s.append_ff50Node("Network::cTrackFollower", nde.Id, 5);

    try s.append_ff56Node(nde.Height, "Height");
    try s.append_ff56Node(nde._type, "_type");
    try s.append_ff56Node(nde.Position, "Position");

    try s.append_ff50Node("Direction", 0, 1);
    try parse_Network_cDirection(s, nde.Direction);
    try s.append_ff70Node("Direction");

    try s.append_ff50Node("RibbonID", 0, 1);
    try parse_cGUID(s, nde.RibbonId);
    try s.append_ff70Node("RibbonID");

    try s.append_ff70Node("Network::cTrackFollower");
}

fn parse_PassWagon(s: *status, nde: sm.PassWagon) !void {
    try s.append_ff50Node("Component", nde.Id, 6);

    try parse_cWagon(s, nde.cWagon);
    try parse_cAnimObjectRender(s, nde.cAnimObjectRender);
    try parse_cPosOri(s, nde.cPosOri);
    try parse_cControlContainer(s, nde.cControlContainer);
    try parse_cEntityContainer(s, nde.cEntityContainer);
    try parse_cScriptComponent(s, nde.cScriptComponent);

    try s.append_ff70Node("Component");
}

fn parse_cScriptComponent(s: *status, nde: sm.cScriptComponent) !void {
    try s.append_ff50Node("cScriptComponent", nde.Id, 2);

    try s.append_ff56Node(nde.DebugDisplay, "DebugDisplay");
    try s.append_ff56Node(nde.StateName, "StateName");

    try s.append_ff70Node("cScriptComponent");
}

fn parse_CargoWagon(s: *status, nde: sm.CargoWagon) !void {
    try s.append_ff50Node("Component", nde.Id, 7);

    try parse_cWagon(s, nde.cWagon);
    try parse_cAnimObjectRender(s, nde.cAnimObjectRender);
    try parse_cPosOri(s, nde.cPosOri);
    try parse_cControlContainer(s, nde.cControlContainer);
    try parse_cCargoComponent(s, nde.cCargoComponent);
    try parse_cEntityContainer(s, nde.cEntityContainer);
    try parse_cScriptComponent(s, nde.cScriptComponent);

    try s.append_ff70Node("Component");
}
fn parse_Engine(s: *status, nde: sm.Engine) !void {
    try s.append_ff50Node("Component", nde.Id, 8);

    try parse_cEngine(s, nde.cEngine);
    try parse_cAnimObjectRender(s, nde.cAnimObjectRender);
    try parse_cPosOri(s, nde.cPosOri);
    try parse_cEngineSimContainer(s, nde.cEngineSimContainer);
    try parse_cControlContainer(s, nde.cControlContainer);
    try parse_cEntityContainer(s, nde.cEntityContainer);
    try parse_cScriptComponent(s, nde.cScriptComponent);
    try parse_cCargoComponent(s, nde.cCargoComponent);

    try s.append_ff70Node("Component");
}

fn parse_cWagon(s: *status, nde: sm.cWagon) !void {
    try s.append_ff50Node("cWagon", nde.Id, 11);
    try s.append_ff56Node(nde.PantographInfo, "PantographInfo");
    try s.append_ff56Node(nde.PantographIsDirectional, "PantographIsDirectional");
    try s.append_ff56Node(nde.LastPantographControlValue, "LastPantographControlValue");
    try s.append_ff56Node(nde.Flipped, "Flipped");
    try s.append_ff56Node(nde.UniqueNumber, "UniqueNumber");
    try s.append_ff56Node(nde.GUID, "GUID");

    try s.append_ff50Node("Followers", 0, nde.Followers.len);
    for (nde.Followers) |follower| {
        try parse_Network_cTrackFollower(s, follower);
    }
    try s.append_ff70Node("Followers");

    try s.append_ff56Node(nde.TotalMass, "TotalMass");
    try s.append_ff56Node(nde.Speed, "Speed");

    try s.append_ff50Node("Velocity", 0, 1);
    try parse_cHcRVector4(s, nde.Velocity);
    try s.append_ff70Node("Velocity");

    try s.append_ff56Node(nde.InTunnel, "InTunnel");

    try s.append_ff70Node("cWagon");
}

fn parse_cEngine(s: *status, nde: sm.cEngine) !void {
    try s.append_ff50Node("cEngine", nde.Id, 15);
    try s.append_ff56Node(nde.PantographInfo, "PantographInfo");
    try s.append_ff56Node(nde.PantographIsDirectional, "PantographIsDirectional");
    try s.append_ff56Node(nde.LastPantographControlValue, "LastPantographControlValue");
    try s.append_ff56Node(nde.Flipped, "Flipped");
    try s.append_ff56Node(nde.UniqueNumber, "UniqueNumber");
    try s.append_ff56Node(nde.GUID, "GUID");

    try s.append_ff50Node("Followers", 0, nde.Followers.len);
    for (nde.Followers) |follower| {
        try parse_Network_cTrackFollower(s, follower);
    }
    try s.append_ff70Node("Followers");

    try s.append_ff56Node(nde.TotalMass, "TotalMass");
    try s.append_ff56Node(nde.Speed, "Speed");

    try s.append_ff50Node("Velocity", 0, 1);
    try parse_cHcRVector4(s, nde.Velocity);
    try s.append_ff70Node("Velocity");

    try s.append_ff56Node(nde.InTunnel, "InTunnel");
    try s.append_ff56Node(nde.DisabledEngine, "DisabledEngine");
    try s.append_ff56Node(nde.AWSTimer, "AWSTimer");
    try s.append_ff56Node(nde.AWSExpired, "AWSExpired");
    try s.append_ff56Node(nde.TPWSDistance, "TPWSDistance");

    try s.append_ff70Node("cEngine");
}

fn parse_cHcRVector4(s: *status, nde: ?sm.cHcRVector4) !void {
    if (nde == null) return;

    try s.append_ff50Node("cHcRVector4", 0, 1);
    try s.append_ff50Node("Element", 0, nde.?.Element.len);

    for (nde.?.Element) |elem| {
        try s.append_eNode56(elem, "sFloat32");
    }

    try s.append_ff70Node("Element");
    try s.append_ff70Node("cHcRVector4");
}

fn parse_cCargoComponent(s: *status, nde: sm.cCargoComponent) !void {
    try s.append_ff50Node("cCargoComponent", nde.Id, 2);
    try s.append_ff56Node(nde.IsPreLoaded, "IsPreLoaded");

    try s.append_ff50Node("InitialLevel", 0, nde.InitialLevel.len);
    for (nde.InitialLevel) |Val| {
        try s.append_eNode56(Val, "sFloat32");
    }
    try s.append_ff70Node("InitialLevel");

    try s.append_ff70Node("cCargoComponent");
}

fn parse_cControlContainer(s: *status, nde: sm.cControlContainer) !void {
    try s.append_ff50Node("cControlContainer", nde.Id, 3);

    try s.append_ff56Node(nde.Time, "Time");
    try s.append_ff56Node(nde.FrameTime, "FrameTime");
    try s.append_ff56Node(nde.CabEndWithKey, "CabEndWithKey");

    try s.append_ff70Node("cControlContainer");
}

fn parse_cAnimObjectRender(s: *status, nde: sm.cAnimObjectRender) !void {
    try s.append_ff50Node("cAnimObjectRender", nde.Id, 6);

    try s.append_ff56Node(nde.DetailLevel, "DetailLevel");
    try s.append_ff56Node(nde.Global, "Global");
    try s.append_ff56Node(nde.Saved, "Saved");
    try s.append_ff56Node(nde.Palette0Index, "Palette0Index");
    try s.append_ff56Node(nde.Palette1Index, "Palette1Index");
    try s.append_ff56Node(nde.Palette2Index, "Palette2Index");

    try s.append_ff70Node("cAnimObjectRender");
}

fn parse_iBlueprintLibrary_cBlueprintSetId(s: *status, nde: sm.iBlueprintLibrary_cBlueprintSetId) !void {
    try s.append_ff50Node("iBlueprintLibrary::cBlueprintSetID", 0, 2);

    try s.append_ff56Node(nde.Provider, "Provider");
    try s.append_ff56Node(nde.Product, "Product");

    try s.append_ff70Node("iBlueprintLibrary::cBlueprintSetID");
}

fn parse_iBlueprintLibrary_cAbsoluteBlueprintID(s: *status, nde: sm.iBlueprintLibrary_cAbsoluteBlueprintID) !void {
    try s.append_ff50Node("iBlueprintLibrary::cAbsoluteBlueprintID", 0, 2);

    try s.append_ff50Node("BlueprintSetID", 0, 1);
    try parse_iBlueprintLibrary_cBlueprintSetId(s, nde.BlueprintSetId);
    try s.append_ff70Node("BlueprintSetID");

    try s.append_ff56Node(nde.BlueprintID, "BlueprintID");

    try s.append_ff70Node("iBlueprintLibrary::cAbsoluteBlueprintID");
}

fn parse_cFarMatrix(s: *status, nde: sm.cFarMatrix) !void {
    try s.append_ff50Node("cFarMatrix", nde.Id, 5);
    try s.append_ff56Node(nde.Height, "Height");
    try s.append_ff41Node(nde.RXAxis, "RXAxis");
    try s.append_ff41Node(nde.RYAxis, "RYAxis");
    try s.append_ff41Node(nde.RZAxis, "RZAxis");

    try s.append_ff50Node("RFarPosition", 0, 1);
    try parse_cFarVector2(s, nde.RFarPosition);
    try s.append_ff70Node("RFarPosition");

    try s.append_ff70Node("cFarMatrix");
}

fn parse_cPosOri(s: *status, nde: sm.cPosOri) !void {
    try s.append_ff50Node("cPosOri", nde.Id, 2);

    try s.append_ff41Node(nde.Scale, "Scale");

    try s.append_ff50Node("RFarMatrix", 0, 1);
    try parse_cFarMatrix(s, nde.RFarMatrix);
    try s.append_ff70Node("RFarMatrix");

    try s.append_ff70Node("cPosOri");
}

fn parse_cEntityContainer(s: *status, nde: sm.cEntityContainer) !void {
    try s.append_ff50Node("cEntityContainer", nde.Id, 1);

    try s.append_ff50Node("StaticChildrenMatrix", 0, nde.StaticChildrenMatrix.len);
    for (nde.StaticChildrenMatrix) |row| {
        try s.append_ff41Node(row, "e");
    }
    try s.append_ff70Node("StaticChildrenMatrix");

    try s.append_ff70Node("cEntityContainer");
}

fn parse_Component(s: *status, nde: sm.Component) !void {
    try switch (nde) {
        .PassWagon => |wagon| parse_PassWagon(s, wagon),
        .CargoWagon => |wagon| parse_CargoWagon(s, wagon),
        .Engine => |engine| parse_Engine(s, engine),
    };
}

fn parse_cEngineSimContainer(s: *status, nde: u32) !void {
    // TODO: This might not be empty?
    try s.append_ff50Node("cEngineSimContainer", nde, 0);
    try s.append_ff70Node("cEngineSimContainer");
}

fn parse_cOwnedEntity(s: *status, nde: sm.cOwnedEntity) !void {
    try s.append_ff50Node("cOwnedEntity", nde.Id, 5);

    try parse_Component(s, nde.Component);

    try s.append_ff50Node("BlueprintID", 0, 1);
    try parse_iBlueprintLibrary_cAbsoluteBlueprintID(s, nde.BlueprintID);
    try s.append_ff70Node("BlueprintID");

    try s.append_ff50Node("ReskinBlueprintID", 0, 1);
    try parse_iBlueprintLibrary_cAbsoluteBlueprintID(s, nde.ReskinBlueprintID);
    try s.append_ff70Node("ReskinBlueprintID");

    try s.append_ff56Node(nde.Name, "Name");

    try s.append_ff50Node("EntityID", 0, 1);
    try parse_cGUID(s, nde.EntityID);
    try s.append_ff70Node("EntityID");

    try s.append_ff70Node("cOwnedEntity");
}

fn parse_cConsist(s: *status, nde: sm.cConsist) !void {
    try s.append_ff50Node("cConsist", nde.Id, 12);

    try s.append_ff50Node("RailVehicles", 0, nde.RailVehicles.len);
    for (nde.RailVehicles) |vehicle| {
        try parse_cOwnedEntity(s, vehicle);
    }
    try s.append_ff70Node("RailVehicles");

    try s.append_ff50Node("FrontFollower", 0, 1);
    try parse_Network_cTrackFollower(s, nde.FrontFollower);
    try s.append_ff70Node("FrontFollower");

    try s.append_ff50Node("RearFollower", 0, 1);
    try parse_Network_cTrackFollower(s, nde.RearFollower);
    try s.append_ff70Node("RearFollower");

    try s.append_ff50Node("Driver", 0, 1);
    if (nde.Driver == null) {
        try s.append_ff4eNode();
    } else {
        try parse_cDriver(s, nde.Driver);
    }
    try s.append_ff70Node("Driver");

    try s.append_ff56Node(nde.InPortalName, "InPortalName");
    try s.append_ff56Node(nde.DriverEngineIndex, "DriverEngineIndex");

    try s.append_ff50Node("PlatformRibbonGUID", 0, 1);
    try parse_cGUID(s, nde.PlatformRibbonGUID);
    try s.append_ff70Node("PlatformRibbonGUID");

    try s.append_ff56Node(nde.PlatformTimeRemaining, "PlatformTimeRemaining");
    try s.append_ff56Node(nde.MaxPermissableSpeed, "MaxPermissableSpeed");

    try s.append_ff50Node("CurrentDirection", 0, 1);
    try parse_Network_cDirection(s, nde.CurrentDirection);
    try s.append_ff70Node("CurrentDirection");

    try s.append_ff56Node(nde.IgnorePhysicsFrames, "IgnorePhysicsFrames");
    try s.append_ff56Node(nde.IgnoreProximity, "IgnoreProximity");

    try s.append_ff70Node("cConsist");
}

fn parse_Record(s: *status, nde: sm.Record) !void {
    try s.append_ff50Node("Record", 0, nde.cConsists.len);

    for (nde.cConsists) |consist| {
        try parse_cConsist(s, consist);
    }
    try s.append_ff70Node("Record");
}

fn parse_cRecordSet(s: *status, nde: sm.cRecordSet) !void {
    try s.append_ff50Node("cRecordSet", nde.Id, 1);

    try parse_Record(s, nde.Record);

    try s.append_ff70Node("cRecordSet");
}
