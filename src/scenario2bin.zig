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
    source: n.textNode,
    stringMap: strMapType,
    lineMap: lineMapType,
    parentStack: ?std.ArrayList(*n.textNode),
    result: std.ArrayList(u8),

    fn init(src: n.textNode) status {
        return status{
            .current = 0,
            .source = src,
            .stringMap = strMapType{ .map = std.StringHashMap(u16).init(allocator), .currentPos = 0 },
            .lineMap = lineMapType{
                .map = std.StringHashMap(u8).init(allocator),
                .posMap = std.AutoHashMap(u8, []const u8).init(allocator),
                .currentPos = 0,
            },
            .parentStack = null,
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

    fn getCurrentParent(self: *status) *n.textNode {
        return self.parentStack.items[self.parentStack.len - 1];
    }
};

pub fn parse(inputString: []const u8) ![]const u8 {
    var stream = json.TokenStream.init(inputString);
    var rootNode = try json.parse(sm.cRecordSet, &stream, .{ .allocator = allocator });
    // var parserStatus = status.init(rootNode);
    // try addPrelude(&parserStatus);
    // try walkNodes(&parserStatus, rootNode);
    // return parserStatus.result.items;
}

fn addPrelude(s: *status) !void {
    try s.result.appendSlice(serz);
    try s.result.appendSlice(unknown);
}

fn walkNodes(s: *status, parentNode: n.textNode) !void {
    try s.result.appendSlice(try convertTnode(s, parentNode));
    for (parentNode.ff50NodeT.children) |child| {
        switch (child) {
            .ff50NodeT => try walkNodes(s, child),
            else => |node| try s.result.appendSlice(try convertTnode(s, node)),
        }
    }
    const closingNode = n.textNode{ .ff70NodeT = n.ff70NodeT{ .name = parentNode.ff50NodeT.name } };
    try s.result.appendSlice(try convertTnode(s, closingNode));
}

fn convertTnode(s: *status, node: n.textNode) ![]const u8 {
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
    const correctedType = try correctType(data, expectedType);
    switch (correctedType) {
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

fn getDataUnionType(val: anytype) n.dataUnion {
    return switch (@TypeOf(val)) {
        []const u8 => n.dataUnion{ ._cDeltaString = val },
        bool => n.dataUnion{ ._bool = val },
        u8 => n.dataUnion{ ._sUInt8 = val },
        i16 => n.dataUnion{ ._sInt16 = val },
        i32 => n.dataUnion{ ._sInt32 = val },
        u32 => n.dataUnion{ ._sUInt32 = val },
        u64 => n.dataUnion{ ._sUInt64 = val },
        f32 => n.dataUnion{ ._sFloat32 = val },
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
    };
}

fn make_ff50nodeT(name: []const u8, id: u32, children: u32) n.textNode {
    return n.textNode{ .ff50nodeT = n.ff50nodeT{ .name = name, .id = id, .children = children } };
}

fn append_ff50nodeT(name: []const u8, id: u32, children: u32) !void {
    try s.result.append(try convertTnode(s, make_ff50nodeT(name, id, children)));
}

fn make_ff56nodeT(modelType: anytype, comptime name: []const u8) n.textNode {
    const fieldVal = @field(modelType, name);
    const valueTypeStr = getDataUnionStr(fieldVal);
    const dataUnionVal = getDataUnionType(fieldVal);
    return n.textNode{ .ff56nodeT = n.ff56nodeT{ .name = name, .dType = valueTypeStr, .value = dataUnionVal } };
}

fn append_ff56nodeT(modelType: anytype, comptime name: []const u8) !void {
    try s.result.append(try convertTnode(s, make_ff56nodeT(modelType, name)));
}

fn append_eNode(value: anytype, typeStr: []const u8) !void {
    const tempNode = n.textNode{ .ff56nodeT = n.ff56nodeT{ .name = "e", .dType = typrStr, .value = getDataUnionType(value) } };
    try s.result.append(try convertTnode(s, tempNode));
}

fn make_ff70nodeT(name: []const u8) n.textNode {
    return n.textNode{ .ff70NodeT = n.ff70NodeT{ .name = name } };
}

fn append_ff70nodeT(name: []const u8) !void {
    try s.result.append(try convertTnode(s, make_ff70nodeT(name)));
}

//////////////////////////// NEW ////////////////////////////////////
fn parse_sTimeOfDay(s: *status, nde: sm.sTimeOfDay) !void {
    try append_ff50nodeT("sTimeOfDay", 0, 3);
    try append_ff56nodeT(nde, "_iHour");
    try append_ff56nodeT(nde, "_iMinute");
    try append_ff56nodeT(nde, "_iSeconds");
    try append_ff70nodeT("sTimeOfDay");
}

fn parse_parseLocalisation_cUserLocalisedString(s: *status, nde: sm.Localisation_cUserLocalisedString) !void {
    try append_ff50nodeT("Localisation_cUserLocalisedString", 0, 10);
    try append_ff56nodeT(nde, "English");
    try append_ff56nodeT(nde, "French");
    try append_ff56nodeT(nde, "Italian");
    try append_ff56nodeT(nde, "German");
    try append_ff56nodeT(nde, "Spanish");
    try append_ff56nodeT(nde, "Dutch");
    try append_ff56nodeT(nde, "Polish");
    try append_ff56nodeT(nde, "Russian");

    // TODO: Other Logic
    try append_ff50nodeT("Other", 0, 0);
    try append_ff70nodeT("Other",0, 0);

    try append_ff56nodeT(nde, "Key");
    try append_ff70nodeT("Localisation_cUserLocalisedString");
}

fn parse_cGUID(s: *status, nde: sm.cGUID) !void {
    try append_ff50nodeT("cGUID", 0, 0);
    try append_ff50nodeT("UUID", 0, 0);
    // TODO: fix
    try append_eNode("sUint64", nde.UUID[0]);
    try append_eNode("sUint64", nde.UUID[1]);
    try append_ff70nodeT("UUID");
    try append_ff56nodeT("DevString");
    try append_ff70nodeT("cGUID");
}

fn parse_DriverInstruction(s: *status, nde: sm.DriverInstruction) !void {
    switch (nde) {
        .cTriggerInstruction => parse_cTriggerInstruction,
        .cStopAtDestination => parse_cStopAtDestination,
        .cConsistOperation => parse_cConsistOperation,
        .cPickupPassengers => parse_cPickupPassengers,
    }
}

fn parse_cDriverInstructionTarget(s: *status, nde: sm.cDriverInstructionTarget) void {
    // TODO: Can be NULL
    try append_ff50nodeT("cDriverInstructionTarget", nde.Id, 28);
    try append_ff56nodeT("DisplayName");
    try append_ff56nodeT("Timetabled");
    try append_ff56nodeT("Performance");
    try append_ff56nodeT("MinSpeed");
    try append_ff56nodeT("DurationSecs");
    try append_ff56nodeT("EntityName");
    try append_ff56nodeT("TrainOrder");
    try append_ff56nodeT("Operation");

    try append_ff50nodeT("Deadline", 0, 1);
    try parse_sTimeOfDay(s, sm.sTimeOfDay);
    try append_ff70nodeT("Deadline");

    try append_ff56nodeT("PickingUp");
    try append_ff56nodeT("Duration");
    try append_ff56nodeT("HandleOffPath");
    try append_ff56nodeT("EarliestDepartureTime");
    try append_ff56nodeT("DurationSet");
    try append_ff56nodeT("ReversingAllowed");
    try append_ff56nodeT("Waypoint");
    try append_ff56nodeT("Hidden");
    try append_ff56nodeT("ProgressCode");
    try append_ff56nodeT("ArrivalTime");
    try append_ff56nodeT("DepartureTime");
    try append_ff56nodeT("TickedTime");
    try append_ff56nodeT("DueTime");

    try append_ff50nodeT("RailVehicleNumber", 0, 1);
    for (nde.RailVehicleNumber) |num| {
        try append_eNode(num, "cDeltaString");
    }
    try append_ff70nodeT("RailVehicleNumber");

    try append_ff56nodeT("TimingTestTime");

    try append_ff50nodeT("GroupName", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.GroupName);
    try append_ff70nodeT("GroupName");

    try append_ff56nodeT("ShowRVNumbersWithGroup");
    try append_ff56nodeT("ScenarioChainTarget");

    try append_ff50Node("ScenarioChainGUID", 0, 1);
    try parse_cGUID(s, nde.ScenarioChainGUID);
    try append_ff70Node("ScenarioChainGUID");
}

fn parse_cPickupPassengers(s: *status, nde: sm.cPickupPassengers) !void {
    try append_ff50nodeT("cPickupPassengers", nde.Id, 24);
    try append_ff56nodeT("ActivationLevel");
    try append_ff56nodeT("SuccessTextToBeSavedMessage");
    try append_ff56nodeT("FailureTextToBeSavedMessage");
    try append_ff56nodeT("DisplayTextToBeSavedMessage");

    try append_ff50nodeT("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try append_ff70nodeT("TriggeredText");

    try append_ff50nodeT("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try append_ff70nodeT("UntriggeredText");

    try append_ff50nodeT("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try append_ff70nodeT("DisplayText");

    try append_ff56nodeT("TriggerTrainStop");
    try append_ff56nodeT("TriggerWheelSlip");
    try append_ff56nodeT("WheelSlipDuration");

    try append_ff50nodeT("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggeredSound);
    try append_ff70nodeT("TriggerSound");
    
    try append_ff50nodeT("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggeredAnimation);
    try append_ff70nodeT("TriggerAnimation");

    try append_ff56nodeT("SecondsDelay");
    try append_ff56nodeT("Active");

    try append_ff50nodeT("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try append_ff70nodeT("ArriveTime");

    try append_ff50nodeT("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try append_ff70nodeT("DepartTime");

    try append_ff56nodeT("Condition");
    try append_ff56nodeT("SuccessEvent");
    try append_ff56nodeT("FailureEvent");
    try append_ff56nodeT("Started");
    try append_ff56nodeT("Satisfied");
    try append_ff50nodeT("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try append_ff70nodeT("DeltaTarget");
    try append_ff56nodeT("TravelForwards");
    try append_ff56nodeT("UnloadPassengers");
}

fn parse_cConsistOperation(s: *status, nde: sm.cConsistOperation) !void {
    try append_ff50nodeT("cConsistOperations", nde.Id, 27);
    try append_ff56nodeT("ActivationLevel");
    try append_ff56nodeT("SuccessTextToBeSavedMessage");
    try append_ff56nodeT("FailureTextToBeSavedMessage");
    try append_ff56nodeT("DisplayTextToBeSavedMessage");

    try append_ff50nodeT("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try append_ff70nodeT("TriggeredText");

    try append_ff50nodeT("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try append_ff70nodeT("UntriggeredText");

    try append_ff50nodeT("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try append_ff70nodeT("DisplayText");

    try append_ff56nodeT("TriggerTrainStop");
    try append_ff56nodeT("TriggerWheelSlip");
    try append_ff56nodeT("WheelSlipDuration");

    try append_ff50nodeT("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggeredSound);
    try append_ff70nodeT("TriggerSound");
    
    try append_ff50nodeT("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggeredAnimation);
    try append_ff70nodeT("TriggerAnimation");

    try append_ff56nodeT("SecondsDelay");
    try append_ff56nodeT("Active");

    try append_ff50nodeT("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try append_ff70nodeT("ArriveTime");

    try append_ff50nodeT("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try append_ff70nodeT("DepartTime");

    try append_ff56nodeT("Condition");
    try append_ff56nodeT("SuccessEvent");
    try append_ff56nodeT("FailureEvent");
    try append_ff56nodeT("Started");
    try append_ff56nodeT("Satisfied");

    try append_ff50nodeT("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try append_ff70nodeT("DeltaTarget");

    try append_ff56nodeT("OperationOrder");
    try append_ff56nodeT("FirstUpdateDone");
    try append_ff56nodeT("LastCompletedTargetIndex");
    try append_ff56nodeT("CurrentTargetIndex");
    try append_ff56nodeT("TargetCompletedTime");
}

fn parse_cStopAtDestination(s: *status, nde: sm.cStopAtDestination) !void {
    try append_ff50nodeT("cStopAtDestination", nde.Id, 23);
    try append_ff56nodeT("ActivationLevel");
    try append_ff56nodeT("SuccessTextToBeSavedMessage");
    try append_ff56nodeT("FailureTextToBeSavedMessage");
    try append_ff56nodeT("DisplayTextToBeSavedMessage");

    try append_ff50nodeT("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try append_ff70nodeT("TriggeredText");

    try append_ff50nodeT("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try append_ff70nodeT("UntriggeredText");

    try append_ff50nodeT("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try append_ff70nodeT("DisplayText");

    try append_ff56nodeT("TriggerTrainStop");
    try append_ff56nodeT("TriggerWheelSlip");
    try append_ff56nodeT("WheelSlipDuration");

    try append_ff50nodeT("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggeredSound);
    try append_ff70nodeT("TriggerSound");
    
    try append_ff50nodeT("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggeredAnimation);
    try append_ff70nodeT("TriggerAnimation");

    try append_ff56nodeT("SecondsDelay");
    try append_ff56nodeT("Active");

    try append_ff50nodeT("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try append_ff70nodeT("ArriveTime");

    try append_ff50nodeT("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try append_ff70nodeT("DepartTime");

    try append_ff56nodeT("Condition");
    try append_ff56nodeT("SuccessEvent");
    try append_ff56nodeT("FailureEvent");
    try append_ff56nodeT("Started");
    try append_ff56nodeT("Satisfied");

    try append_ff50nodeT("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try append_ff70nodeT("DeltaTarget");

    try append_ff56nodeT("TravelForwards");
}

fn parse_cTriggerInstruction(s: *status, sm.cTriggerInstruction) !void {
    try append_ff50nodeT("cStopAtDestination", nde.Id, 23);
    try append_ff56nodeT("ActivationLevel");
    try append_ff56nodeT("SuccessTextToBeSavedMessage");
    try append_ff56nodeT("FailureTextToBeSavedMessage");
    try append_ff56nodeT("DisplayTextToBeSavedMessage");

    try append_ff50nodeT("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try append_ff70nodeT("TriggeredText");

    try append_ff50nodeT("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try append_ff70nodeT("UntriggeredText");

    try append_ff50nodeT("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try append_ff70nodeT("DisplayText");

    try append_ff56nodeT("TriggerTrainStop");
    try append_ff56nodeT("TriggerWheelSlip");
    try append_ff56nodeT("WheelSlipDuration");

    try append_ff50nodeT("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggeredSound);
    try append_ff70nodeT("TriggerSound");
    
    try append_ff50nodeT("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggeredAnimation);
    try append_ff70nodeT("TriggerAnimation");

    try append_ff56nodeT("SecondsDelay");
    try append_ff56nodeT("Active");

    try append_ff50nodeT("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try append_ff70nodeT("ArriveTime");

    try append_ff50nodeT("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try append_ff70nodeT("DepartTime");

    try append_ff56nodeT("Condition");
    try append_ff56nodeT("SuccessEvent");
    try append_ff56nodeT("FailureEvent");
    try append_ff56nodeT("Started");
    try append_ff56nodeT("Satisfied");

    try append_ff50nodeT("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try append_ff70nodeT("DeltaTarget");

    try append_ff56nodeT("StartTime");
}

fn parse_cDriverInstructionContainer(s: *status, nde: sm.cDriverInstructionContainer) !sm.cDriverInstructionContainer {
    try append_ff50nodeT("cDriverInstructionContainer", nde.Id, 1);
    try parse_DriverInstruction(s, nde.DriverInstruction);
    try append_ff70nodeT("cDriverInstructionContainer")
}

fn parse_cDriver(s: *status, nde: sm.cDriver) !void {
    // TODO: Could be null
    try append_ff50nodeT("cDriver", nde.Id, 18);

    try append_ff50nodeT("FinalDestination", nde.Id, 18);
    try parse_cDriverInstructionTarget(s, sm.FinalDestination);
    try append_ff70nodeT("FinalDestination");

    try append_ff56nodeT("PlayerDriver");

    try append_ff50nodeT("ServiceName", nde.Id, 18);
    try parse_parseLocalisation_cUserLocalisedString(s, sm.ServiceName);
    try append_ff70nodeT("ServiceName");

    try append_ff50nodeT("InitialRV", nde.Id, 18);
    for (nde.InitialRV) |val| {
        append_eNode(val, "cDeltaString");
    }
    try append_ff70nodeT("InitialRV");

    try append_ff56nodeT("StartTime");
    try append_ff56nodeT("StartSpeed");
    try append_ff56nodeT("EndSpeed");
    try append_ff56nodeT("ServiceClass");
    try append_ff56nodeT("ExpectedPerformance");
    try append_ff56nodeT("PlayerControlled");
    try append_ff56nodeT("PriorPathingStatus");
    try append_ff56nodeT("PathingStatus");
    try append_ff56nodeT("RepathIn");
    try append_ff56nodeT("ForcedRepath");
    try append_ff56nodeT("OffPath");
    try append_ff56nodeT("StartTriggerDistanceFromPlayerSquared");

    try append_ff50nodeT("DriverInstructionContainer", nde.Id, 18);
    try parse_cDriverInstructionContainer(s, sm.cDriverInstructionContainer);
    try append_ff70nodeT("DriverInstructionContainer");

    try append_ff56nodeT("UnloadedAtStart");

    try append_ff70nodeT("cDriver");
}

fn parse_cRouteCoordinate(s: *status, nde: sm.cRouteCoordinate) !void {
    try append_ff50nodeT("cRouteCoordinate", 0, 1);
    try append_ff56nodeT("Distance");
    try append_ff70nodeT("cRouteCoordinate");
}

fn parse_cTileCoordinate(s: *status, nde: sm.cTileCoordinate) !void {
    try append_ff50nodeT("cTileCoordinate", 0, 1);
    try append_ff56nodeT("Distance");
    try append_ff70nodeT("cTileCoordinate");
}

fn parse_cFarCoordinate(s: *status, nde: sm.cFarCoordinate) !void {
    try append_ff50nodeT("cFarCoordinate", 0, 1);
    try parse_cRouteCoordinate(s, nde.RouteCoordinate);
    try parse_cTileCoordinate(s, nde.TileCoordinate);
    try append_ff70nodeT("cFarCoordinate");
}

fn parse_cFarVector2(s: *status, nde: sm.cFarVector2) !void {
    try append_ff50nodeT("cFarCoordinate", nde.Id, 2);

    try append_ff50nodeT("X", 0, 1);
    try parse_cFarCoordinate(s, nde.X);
    try append_ff70nodeT("X");

    try append_ff50nodeT("Y", 0, 1);
    try parse_cFarCoordinate(s, nde.Y);
    try append_ff70nodeT("Y");

    try append_ff70nodeT("cFarCoordinate");
}

fn parse_Network_cDirection(s: *status) sm.Network_cDirection {
    try append_ff50nodeT("Network::cDirection", 0, 1);
    try append_ff56nodeT("_dir");
    try append_ff70nodeT("Network::cDirection");
}

fn parse_Network_cTrackFollower(s: *status, nde: sm.Network_cTrackFollower) !void {
    try append_ff50nodeT("Network::cTrackFollower", nde.Id, 5);

    try append_ff56nodeT("Height");
    try append_ff56nodeT("_type");
    try append_ff56nodeT("Position");

    try append_ff50nodeT("Direction", 0, 1);
    try parse_Network_cDirection(s, nde.Direction);
    try append_ff70nodeT("Direction");

    try append_ff50nodeT("RibbonID", 0, 1);
    try parse_cGUID(s, nde.RibbonId);
    try append_ff70nodeT("RibbonID");

    try append_ff70nodeT("Network::cTrackFollower");
}

fn parse_vehicle(s: *status, nde: sm.Vehicle) !void {
    switch (nde) {
        .PassWagon => parse_PassengerWagon(s, nde),
        .CargoWagon => parse_CargoWagon(s, nde),
        .Engine => parse_Engine(s, nde),
    }
}

fn parse_PassWagon(s: *status, nde: sm.cEngine) !void {
}

fn parse_CargoWagon(s: *status, nde: sm.cEngine) !void {
}
fn parse_Engine(s: *status, nde: sm.cEngine) !void {
}

fn parse_cWagon(s: *status, nde: sm.cWagon) !void {
}

fn parse_cCargoComponent(s: *status, nde: sm.cCargoComponent) !void {
}

fn parse_cControlContainer(s: *status, nde: m.cControlContainer) !void {
}

fn parse_cAnimObjectRender(s: *status, nde: m.cAnimObjectRender) !void {
}

fn parse_iBlueprintLibrary_cBlueprintSetId(s: *status, nde: m.iBlueprintLibrary_cBlueprintSetId) !void {
}

fn parse_iBlueprintLibrary_cAbsoluteBlueprintID(s: *status, nde: m.iBlueprintLibrary_cAbsoluteBlueprintID) !void {
}

fn parse_cFarMatrix(s: *status, nde: m.cFarMatrix) !void {
}

fn parse_cPosOri(s: *status, nde: m.cPosOri) !void {
}

fn parse_cEntityContainer(s: *status, nde: sm.cEntityContainer) !void {
}

fn parse_Component(s: *status, nde: sm.Component) !void {
}

fn parse_cEngineSimContainer(s: *status, nde: 32) !void {
}

fn parse_cOwnedEntity(s: *status, nde: sm.cOwnedEntity) !void {
}

fn parse_cConsist(s: *status, nde: sm.cConsist) !void {
}

fn parse_Record(s: *status, nde: sm.Record) !void {
}

fn parse_cRecordSet(s: *status, nde: sm.cRecordSet) !void {
}
