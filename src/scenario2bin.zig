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

    fn append_ff50nodeT(self: *status, name: []const u8, id: u32, children: u32) !void {
        try self.result.append(try convertTnode(self, make_ff50nodeT(name, id, children)));
    }

    fn append_ff56nodeT(self: *status, data: anytype, name: []const u8) !void {
        try self.result.append(try convertTnode(self, make_ff56nodeT(data, name)));
    }

    fn append_eNode56(self: *status, value: anytype, typeStr: []const u8) !void {
        const tempNode = n.textNode{ .ff56nodeT = n.ff56nodeT{ .name = "e", .dType = typeStr, .value = getDataUnionType(value) } };
        try self.result.append(try convertTnode(self, tempNode));
    }

    fn append_eNode41(self: *status, value: anytype, typeStr: []const u8) !void {
        var valuesList = std.ArrayList(n.dataUnion).init(allocator);
        for (value) |val| {
            try valuesList.append(getDataUnionType(val));
        }
        const tempNode = n.textNode{ .ff41nodeT = n.ff41nodeT{ .name = "e", .dType = typeStr, .values = valuesList.items } };
        try self.result.append(try convertTnode(self, tempNode));
    }

    fn append_ff70nodeT(self: *status, name: []const u8) !void {
        try self.result.append(try convertTnode(self, make_ff70nodeT(name)));
    }
};

pub fn parse(inputString: []const u8) ![]const u8 {
    var stream = json.TokenStream.init(inputString);
    var rootNode = try json.parse(sm.cRecordSet, &stream, .{ .allocator = allocator });
    std.debug.print("{any}", rootNode);
    // var parserStatus = status.init(rootNode);
    // try addPrelude(&parserStatus);
    // try walkNodes(&parserStatus, rootNode);
    // return parserStatus.result.items;
    return "";
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

fn make_ff56nodeT(value: anytype, name: []const u8) n.textNode {
    const valueTypeStr = getDataUnionStr(value);
    const dataUnionVal = getDataUnionType(value);
    return n.textNode{ .ff56nodeT = n.ff56nodeT{ .name = name, .dType = valueTypeStr, .value = dataUnionVal } };
}

fn make_ff70nodeT(name: []const u8) n.textNode {
    return n.textNode{ .ff70NodeT = n.ff70NodeT{ .name = name } };
}

//////////////////////////// NEW ////////////////////////////////////
fn parse_sTimeOfDay(s: *status, nde: sm.sTimeOfDay) !void {
    try s.append_ff50nodeT("sTimeOfDay", 0, 3);
    try s.append_ff56nodeT(nde, "_iHour");
    try s.append_ff56nodeT(nde, "_iMinute");
    try s.append_ff56nodeT(nde, "_iSeconds");
    try s.append_ff70nodeT("sTimeOfDay");
}

fn parse_parseLocalisation_cUserLocalisedString(s: *status, nde: sm.Localisation_cUserLocalisedString) !void {
    try s.append_ff50nodeT("Localisation_cUserLocalisedString", 0, 10);
    try s.append_ff56nodeT(nde, "English");
    try s.append_ff56nodeT(nde, "French");
    try s.append_ff56nodeT(nde, "Italian");
    try s.append_ff56nodeT(nde, "German");
    try s.append_ff56nodeT(nde, "Spanish");
    try s.append_ff56nodeT(nde, "Dutch");
    try s.append_ff56nodeT(nde, "Polish");
    try s.append_ff56nodeT(nde, "Russian");

    // TODO: Other Logic
    try s.append_ff50nodeT("Other", 0, 0);
    try s.append_ff70nodeT("Other", 0, 0);

    try s.append_ff56nodeT(nde, "Key");
    try s.append_ff70nodeT("Localisation_cUserLocalisedString");
}

fn parse_cGUID(s: *status, nde: sm.cGUID) !void {
    try s.append_ff50nodeT("cGUID", 0, 0);
    try s.append_ff50nodeT("UUID", 0, 0);
    try s.s.append_eNode56("sUint64", nde.UUID[0]);
    try s.s.append_eNode56("sUint64", nde.UUID[1]);
    try s.append_ff70nodeT("UUID");
    try s.append_ff56nodeT(nde, "DevString");
    try s.append_ff70nodeT("cGUID");
}

fn parse_DriverInstruction(s: *status, nde: sm.DriverInstruction) !void {
    switch (nde) {
        .cTriggerInstruction => parse_cTriggerInstruction(s, nde),
        .cStopAtDestination => parse_cStopAtDestination(s, nde),
        .cConsistOperation => parse_cConsistOperation(s, nde),
        .cPickupPassengers => parse_cPickupPassengers(s, nde),
    }
}

fn parse_cDriverInstructionTarget(s: *status, nde: sm.cDriverInstructionTarget) !void {
    if (nde == null) {
        return;
    }
    try s.append_ff50nodeT("cDriverInstructionTarget", nde.Id, 28);
    try s.append_ff56nodeT(nde.DisplayName, "DisplayName");
    try s.append_ff56nodeT(nde.Timetabled, "Timetabled");
    try s.append_ff56nodeT(nde.Performance, "Performance");
    try s.append_ff56nodeT(nde.MinSpeed, "MinSpeed");
    try s.append_ff56nodeT(nde.DurationSecs, "DurationSecs");
    try s.append_ff56nodeT(nde.EntityName, "EntityName");
    try s.append_ff56nodeT(nde.TrainOrder, "TrainOrder");
    try s.append_ff56nodeT(nde.Operation, "Operation");

    try s.append_ff50nodeT("Deadline", 0, 1);
    try parse_sTimeOfDay(s, sm.sTimeOfDay);
    try s.append_ff70nodeT("Deadline");

    try s.append_ff56nodeT(nde.PickingUp, "PickingUp");
    try s.append_ff56nodeT(nde.Duration, "Duration");
    try s.append_ff56nodeT(nde.HandleOffPath, "HandleOffPath");
    try s.append_ff56nodeT(nde.EarliestDepartureTime, "EarliestDepartureTime");
    try s.append_ff56nodeT(nde.DurationSet, "DurationSet");
    try s.append_ff56nodeT(nde.ReversingAllowed, "ReversingAllowed");
    try s.append_ff56nodeT(nde.Waypoint, "Waypoint");
    try s.append_ff56nodeT(nde.Hidden, "Hidden");
    try s.append_ff56nodeT(nde.ProgressCode, "ProgressCode");
    try s.append_ff56nodeT(nde.ArrivalTime, "ArrivalTime");
    try s.append_ff56nodeT(nde.DepartureTime, "DepartureTime");
    try s.append_ff56nodeT(nde.TickedTime, "TickedTime");
    try s.append_ff56nodeT(nde.DueTime, "DueTime");

    try s.append_ff50nodeT("RailVehicleNumber", 0, 1);
    for (nde.RailVehicleNumber) |num| {
        try s.append_eNode56(num, "cDeltaString");
    }
    try s.append_ff70nodeT("RailVehicleNumber");

    try s.append_ff56nodeT(nde.TimingTestTime, "TimingTestTime");

    try s.append_ff50nodeT("GroupName", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.GroupName);
    try s.append_ff70nodeT("GroupName");

    try s.append_ff56nodeT(nde.ShowRVNumbersWithGroup, "ShowRVNumbersWithGroup");
    try s.append_ff56nodeT(nde.ScenarioChainTarget, "ScenarioChainTarget");

    try s.append_ff50Node("ScenarioChainGUID", 0, 1);
    try parse_cGUID(s, nde.ScenarioChainGUID);
    try s.append_ff70Node("ScenarioChainGUID");
}

fn parse_cPickupPassengers(s: *status, nde: sm.cPickupPassengers) !void {
    try s.append_ff50nodeT("cPickupPassengers", nde.Id, 24);
    try s.append_ff56nodeT(nde.ActivationLevel, "ActivationLevel");
    try s.append_ff56nodeT(nde.SuccessTextToBeSavedMessage, "SuccessTextToBeSavedMessage");
    try s.append_ff56nodeT(nde.FailureTextToBeSavedMessage, "FailureTextToBeSavedMessage");
    try s.append_ff56nodeT(nde.DisplayTextToBeSavedMessage, "DisplayTextToBeSavedMessage");

    try s.append_ff50nodeT("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try s.append_ff70nodeT("TriggeredText");

    try s.append_ff50nodeT("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try s.append_ff70nodeT("UntriggeredText");

    try s.append_ff50nodeT("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try s.append_ff70nodeT("DisplayText");

    try s.append_ff56nodeT(nde.TriggerTrainStop, "TriggerTrainStop");
    try s.append_ff56nodeT(nde.TriggerWheelSlip, "TriggerWheelSlip");
    try s.append_ff56nodeT(nde.WheelSlipDuration, "WheelSlipDuration");

    try s.append_ff50nodeT("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggeredSound);
    try s.append_ff70nodeT("TriggerSound");

    try s.append_ff50nodeT("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggeredAnimation);
    try s.append_ff70nodeT("TriggerAnimation");

    try s.append_ff56nodeT(nde.SecondsDelay, "SecondsDelay");
    try s.append_ff56nodeT(nde.Active, "Active");

    try s.append_ff50nodeT("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try s.append_ff70nodeT("ArriveTime");

    try s.append_ff50nodeT("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try s.append_ff70nodeT("DepartTime");

    try s.append_ff56nodeT(nde.Condition, "Condition");
    try s.append_ff56nodeT(nde.SuccessEvent, "SuccessEvent");
    try s.append_ff56nodeT(nde.FailureEvent, "FailureEvent");
    try s.append_ff56nodeT(nde.Started, "Started");
    try s.append_ff56nodeT(nde.Satisfied, "Satisfied");

    try s.append_ff50nodeT("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try s.append_ff70nodeT("DeltaTarget");

    try s.append_ff56nodeT(nde.TravelForwards, "TravelForwards");
    try s.append_ff56nodeT(nde.UnloadPassengers, "UnloadPassengers");

    try s.append_ff70nodeT("cPickupPassengers");
}

fn parse_cConsistOperation(s: *status, nde: sm.cConsistOperation) !void {
    try s.append_ff50nodeT("cConsistOperations", nde.Id, 27);
    try s.append_ff56nodeT(nde.ActivationLevel, "ActivationLevel");
    try s.append_ff56nodeT(nde.SuccessTextToBeSavedMessage, "SuccessTextToBeSavedMessage");
    try s.append_ff56nodeT(nde.FailureTextToBeSavedMessage, "FailureTextToBeSavedMessage");
    try s.append_ff56nodeT(nde.DisplayTextToBeSavedMessage, "DisplayTextToBeSavedMessage");

    try s.append_ff50nodeT("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try s.append_ff70nodeT("TriggeredText");

    try s.append_ff50nodeT("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try s.append_ff70nodeT("UntriggeredText");

    try s.append_ff50nodeT("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try s.append_ff70nodeT("DisplayText");

    try s.append_ff56nodeT(nde.TriggerTrainStop, "TriggerTrainStop");
    try s.append_ff56nodeT(nde.TriggerWheelSlip, "TriggerWheelSlip");
    try s.append_ff56nodeT(nde.WheelSlipDuration, "WheelSlipDuration");

    try s.append_ff50nodeT("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggeredSound);
    try s.append_ff70nodeT("TriggerSound");

    try s.append_ff50nodeT("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggeredAnimation);
    try s.append_ff70nodeT("TriggerAnimation");

    try s.append_ff56nodeT(nde.SecondsDelay, "SecondsDelay");
    try s.append_ff56nodeT(nde.Active, "Active");

    try s.append_ff50nodeT("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try s.append_ff70nodeT("ArriveTime");

    try s.append_ff50nodeT("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try s.append_ff70nodeT("DepartTime");

    try s.append_ff56nodeT(nde.Condition, "Condition");
    try s.append_ff56nodeT(nde.SuccessEvent, "SuccessEvent");
    try s.append_ff56nodeT(nde.FailureEvent, "FailureEvent");
    try s.append_ff56nodeT(nde.Started, "Started");
    try s.append_ff56nodeT(nde.Satisfied, "Satisfied");

    try s.append_ff50nodeT("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try s.append_ff70nodeT("DeltaTarget");

    try s.append_ff56nodeT(nde.OperationOrder, "OperationOrder");
    try s.append_ff56nodeT(nde.FirstUpdateDone, "FirstUpdateDone");
    try s.append_ff56nodeT(nde.LastCompletedTargetIndex, "LastCompletedTargetIndex");
    try s.append_ff56nodeT(nde.CurrentTargetIndex, "CurrentTargetIndex");
    try s.append_ff56nodeT(nde.TargetCompletedTime, "TargetCompletedTime");

    try s.append_ff70nodeT("cConsistOperations");
}

fn parse_cStopAtDestination(s: *status, nde: sm.cStopAtDestination) !void {
    try s.append_ff50nodeT("cStopAtDestination", nde.Id, 23);
    try s.append_ff56nodeT(nde.ActivationLevel, "ActivationLevel");
    try s.append_ff56nodeT(nde.SuccessTextToBeSavedMessage, "SuccessTextToBeSavedMessage");
    try s.append_ff56nodeT(nde.FailureTextToBeSavedMessage, "FailureTextToBeSavedMessage");
    try s.append_ff56nodeT(nde.DisplayTextToBeSavedMessage, "DisplayTextToBeSavedMessage");

    try s.append_ff50nodeT("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try s.append_ff70nodeT("TriggeredText");

    try s.append_ff50nodeT("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try s.append_ff70nodeT("UntriggeredText");

    try s.append_ff50nodeT("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try s.append_ff70nodeT("DisplayText");

    try s.append_ff56nodeT(nde.TriggerTrainStop, "TriggerTrainStop");
    try s.append_ff56nodeT(nde.TriggerWheelSlip, "TriggerWheelSlip");
    try s.append_ff56nodeT(nde.WheelSlipDuration, "WheelSlipDuration");

    try s.append_ff50nodeT("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggeredSound);
    try s.append_ff70nodeT("TriggerSound");

    try s.append_ff50nodeT("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggeredAnimation);
    try s.append_ff70nodeT("TriggerAnimation");

    try s.append_ff56nodeT(nde.SecondsDelay, "SecondsDelay");
    try s.append_ff56nodeT(nde.Active, "Active");

    try s.append_ff50nodeT("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try s.append_ff70nodeT("ArriveTime");

    try s.append_ff50nodeT("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try s.append_ff70nodeT("DepartTime");

    try s.append_ff56nodeT(nde.Condition, "Condition");
    try s.append_ff56nodeT(nde.SuccessEvent, "SuccessEvent");
    try s.append_ff56nodeT(nde.FailureEvent, "FailureEvent");
    try s.append_ff56nodeT(nde.Started, "Started");
    try s.append_ff56nodeT(nde.Satisfied, "Satisfied");

    try s.append_ff50nodeT("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try s.append_ff70nodeT("DeltaTarget");

    try s.append_ff56nodeT(nde.TravelForwards, "TravelForwards");

    try s.append_ff70nodeT("cStopAtDestination");
}

fn parse_cTriggerInstruction(s: *status, nde: sm.cTriggerInstruction) !void {
    try s.append_ff50nodeT("cStopAtDestination", nde.Id, 23);
    try s.append_ff56nodeT(nde.ActivationLevel, "ActivationLevel");
    try s.append_ff56nodeT(nde.SuccessTextToBeSavedMessage, "SuccessTextToBeSavedMessage");
    try s.append_ff56nodeT(nde.FailureTextToBeSavedMessage, "FailureTextToBeSavedMessage");
    try s.append_ff56nodeT(nde.DisplayTextToBeSavedMessage, "DisplayTextToBeSavedMessage");

    try s.append_ff50nodeT("TriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.TriggeredText);
    try s.append_ff70nodeT("TriggeredText");

    try s.append_ff50nodeT("UntriggeredText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.UntriggeredText);
    try s.append_ff70nodeT("UntriggeredText");

    try s.append_ff50nodeT("DisplayText", 0, 1);
    try parse_parseLocalisation_cUserLocalisedString(s, nde.DisplayText);
    try s.append_ff70nodeT("DisplayText");

    try s.append_ff56nodeT(nde.TriggerTrainStop, "TriggerTrainStop");
    try s.append_ff56nodeT(nde.TriggerWheelSlip, "TriggerWheelSlip");
    try s.append_ff56nodeT(nde.WheelSlipDuration, "WheelSlipDuration");

    try s.append_ff50nodeT("TriggerSound", 0, 1);
    try parse_cGUID(s, nde.TriggeredSound);
    try s.append_ff70nodeT("TriggerSound");

    try s.append_ff50nodeT("TriggerAnimation", 0, 1);
    try parse_cGUID(s, nde.TriggeredAnimation);
    try s.append_ff70nodeT("TriggerAnimation");

    try s.append_ff56nodeT(nde.SecondsDelay, "SecondsDelay");
    try s.append_ff56nodeT(nde.Active, "Active");

    try s.append_ff50nodeT("ArriveTime", 0, 1);
    try parse_sTimeOfDay(s, nde.ArriveTime);
    try s.append_ff70nodeT("ArriveTime");

    try s.append_ff50nodeT("DepartTime", 0, 1);
    try parse_sTimeOfDay(s, nde.DepartTime);
    try s.append_ff70nodeT("DepartTime");

    try s.append_ff56nodeT(nde.Condition, "Condition");
    try s.append_ff56nodeT(nde.SuccessEvent, "SuccessEvent");
    try s.append_ff56nodeT(nde.FailureEvent, "FailureEvent");
    try s.append_ff56nodeT(nde.Started, "Started");
    try s.append_ff56nodeT(nde.Satisfied, "Satisfied");

    try s.append_ff50nodeT("DeltaTarget", 0, 1);
    try parse_cDriverInstructionTarget(s, nde.DeltaTarget);
    try s.append_ff70nodeT("DeltaTarget");

    try s.append_ff56nodeT(nde.StartTime, "StartTime");

    try s.append_ff70nodeT("cTriggerInstruction");
}

fn parse_cDriverInstructionContainer(s: *status, nde: sm.cDriverInstructionContainer) !sm.cDriverInstructionContainer {
    try s.append_ff50nodeT("cDriverInstructionContainer", nde.Id, 1);
    try parse_DriverInstruction(s, nde.DriverInstruction);
    try s.append_ff70nodeT("cDriverInstructionContainer");
}

fn parse_cDriver(s: *status, nde: sm.cDriver) !void {
    if (nde == null) {
        return;
    }

    try s.append_ff50nodeT("cDriver", nde.Id, 18);

    try s.append_ff50nodeT("FinalDestination", nde.Id, 18);
    try parse_cDriverInstructionTarget(s, sm.FinalDestination);
    try s.append_ff70nodeT("FinalDestination");

    try s.append_ff56nodeT(nde.PlayerDriver, "PlayerDriver");

    try s.append_ff50nodeT("ServiceName", nde.Id, 18);
    try parse_parseLocalisation_cUserLocalisedString(s, sm.ServiceName);
    try s.append_ff70nodeT("ServiceName");

    try s.append_ff50nodeT("InitialRV", nde.Id, 18);
    for (nde.InitialRV) |val| {
        s.append_eNode56(val, "cDeltaString");
    }
    try s.append_ff70nodeT("InitialRV");

    try s.append_ff56nodeT(nde.StartTime, "StartTime");
    try s.append_ff56nodeT(nde.StartSpeed, "StartSpeed");
    try s.append_ff56nodeT(nde.EndSpeed, "EndSpeed");
    try s.append_ff56nodeT(nde.ServiceClass, "ServiceClass");
    try s.append_ff56nodeT(nde.ExpectedPerformance, "ExpectedPerformance");
    try s.append_ff56nodeT(nde.PlayerControlled, "PlayerControlled");
    try s.append_ff56nodeT(nde.PriorPathingStatus, "PriorPathingStatus");
    try s.append_ff56nodeT(nde.PathingStatus, "PathingStatus");
    try s.append_ff56nodeT(nde.RepathIn, "RepathIn");
    try s.append_ff56nodeT(nde.ForcedRepath, "ForcedRepath");
    try s.append_ff56nodeT(nde.OffPath, "OffPath");
    try s.append_ff56nodeT(nde.StartTriggerDistanceFromPlayerSquared, "StartTriggerDistanceFromPlayerSquared");

    try s.append_ff50nodeT("DriverInstructionContainer", nde.Id, 18);
    try parse_cDriverInstructionContainer(s, sm.cDriverInstructionContainer);
    try s.append_ff70nodeT("DriverInstructionContainer");

    try s.append_ff56nodeT(nde.UnloadedAtStart, "UnloadedAtStart");

    try s.append_ff70nodeT("cDriver");
}

fn parse_cRouteCoordinate(s: *status, nde: sm.cRouteCoordinate) !void {
    try s.append_ff50nodeT("cRouteCoordinate", 0, 1);
    try s.append_ff56nodeT(nde.Distance, "Distance");
    try s.append_ff70nodeT("cRouteCoordinate");
}

fn parse_cTileCoordinate(s: *status, nde: sm.cTileCoordinate) !void {
    try s.append_ff50nodeT("cTileCoordinate", 0, 1);
    try s.append_ff56nodeT(nde.Distance, "Distance");
    try s.append_ff70nodeT("cTileCoordinate");
}

fn parse_cFarCoordinate(s: *status, nde: sm.cFarCoordinate) !void {
    try s.append_ff50nodeT("cFarCoordinate", 0, 1);
    try parse_cRouteCoordinate(s, nde.RouteCoordinate);
    try parse_cTileCoordinate(s, nde.TileCoordinate);
    try s.append_ff70nodeT("cFarCoordinate");
}

fn parse_cFarVector2(s: *status, nde: sm.cFarVector2) !void {
    try s.append_ff50nodeT("cFarCoordinate", nde.Id, 2);

    try s.append_ff50nodeT("X", 0, 1);
    try parse_cFarCoordinate(s, nde.X);
    try s.append_ff70nodeT("X");

    try s.append_ff50nodeT("Y", 0, 1);
    try parse_cFarCoordinate(s, nde.Y);
    try s.append_ff70nodeT("Y");

    try s.append_ff70nodeT("cFarCoordinate");
}

fn parse_Network_cDirection(s: *status, nde: sm.Network_cDirection) !void {
    try s.append_ff50nodeT("Network::cDirection", 0, 1);
    try s.append_ff56nodeT(nde._dir, "_dir");
    try s.append_ff70nodeT("Network::cDirection");
}

fn parse_Network_cTrackFollower(s: *status, nde: sm.Network_cTrackFollower) !void {
    try s.append_ff50nodeT("Network::cTrackFollower", nde.Id, 5);

    try s.append_ff56nodeT(nde.Height, "Height");
    try s.append_ff56nodeT(nde._type, "_type");
    try s.append_ff56nodeT(nde.Position, "Position");

    try s.append_ff50nodeT("Direction", 0, 1);
    try parse_Network_cDirection(s, nde.Direction);
    try s.append_ff70nodeT("Direction");

    try s.append_ff50nodeT("RibbonID", 0, 1);
    try parse_cGUID(s, nde.RibbonId);
    try s.append_ff70nodeT("RibbonID");

    try s.append_ff70nodeT("Network::cTrackFollower");
}

fn parse_PassWagon(s: *status, nde: sm.PassWagon) !void {
    try s.append_ff50nodeT("Component", nde.Id, 6);

    try parse_cWagon(s, nde.cWagon);
    try parse_cAnimObjectRender(s, nde.cAnimObjectRender);
    try parse_cPosOri(s, nde.cPosOri);
    try parse_cControlContainer(s, nde.cControlContainer);
    try parse_cEntityContainer(s, nde.cEntityContainer);
    try parse_cScriptComponent(s, nde.cScriptComponent);

    try s.append_ff70nodeT("Component");
}

fn parse_cScriptComponent(s: *status, nde: sm.cScriptComponent) !void {
    try s.append_ff50nodeT("cScriptComponent", nde.Id, 2);

    try s.append_ff56nodeT(nde.DebugDisplay, "DebugDisplay");
    try s.append_ff56nodeT(nde.StateName, "StateName");

    try s.append_ff70nodeT("cScriptComponent");
}

fn parse_CargoWagon(s: *status, nde: sm.CargoWagon) !void {
    try s.append_ff50nodeT("Component", nde.Id, 7);

    try parse_cWagon(s, nde.cWagon);
    try parse_cAnimObjectRender(s, nde.cAnimObjectRender);
    try parse_cPosOri(s, nde.cPosOri);
    try parse_cControlContainer(s, nde.cControlContainer);
    try parse_cCargoComponent(s, nde.cCargoComponent);
    try parse_cEntityContainer(s, nde.cEntityContainer);
    try parse_cScriptComponent(s, nde.cScriptComponent);

    try s.append_ff70nodeT("Component");
}
fn parse_Engine(s: *status, nde: sm.Engine) !void {
    try s.append_ff50nodeT("Component", nde.Id, 7);

    try parse_cEngine(s, nde.cEngine);
    try parse_cAnimObjectRender(s, nde.cAnimObjectRender);
    try parse_cPosOri(s, nde.cPosOri);
    try parse_cEngineSimContainer(s, nde.cEngineSimContainer);
    try parse_cControlContainer(s, nde.cControlContainer);
    try parse_cEntityContainer(s, nde.cEntityContainer);
    try parse_cScriptComponent(s, nde.cScriptComponent);
    try parse_cCargoComponent(s, nde.cCargoComponent);

    try s.append_ff70nodeT("Component");
}

fn parse_cWagon(s: *status, nde: sm.cWagon) !void {
    s.append_ff50nodeT("cWagon", nde.Id, 11);
    try s.append_ff56nodeT(nde.PantographInfo, "PantographInfo");
    try s.append_ff56nodeT(nde.PantographIsDirectional, "PantographIsDirectional");
    try s.append_ff56nodeT(nde.LastPantographControlValue, "LastPantographControlValue");
    try s.append_ff56nodeT(nde.Flipped, "Flipped");
    try s.append_ff56nodeT(nde.UniqueNumber, "UniqueNumber");
    try s.append_ff56nodeT(nde.GUID, "GUID");

    try s.append_ff50nodeT("Followers", 0, nde.Followers.len);
    for (nde.Followers) |follower| {
        parse_Network_cTrackFollower(s, follower);
    }
    try s.append_ff70nodeT("Followers");

    try s.append_ff56nodeT(nde.TotalMass, "TotalMass");
    try s.append_ff56nodeT(nde.Speed, "Speed");

    try s.append_ff50nodeT("Velocity", 0, 1);
    try parse_cHcRVector4(s, nde.Velocity);
    try s.append_ff70nodeT("Velocity");

    try s.append_ff56nodeT(nde.InTunnel, "InTunnel");

    try s.append_ff70nodeT("cWagon");
}

fn parse_cEngine(s: *status, nde: sm.cEngine) !void {
    s.append_ff50nodeT("cEngine", nde.Id, 11);
    try s.append_ff56nodeT(nde.PantographInfo, "PantographInfo");
    try s.append_ff56nodeT(nde.PantographIsDirectional, "PantographIsDirectional");
    try s.append_ff56nodeT(nde.LastPantographControlValue, "LastPantographControlValue");
    try s.append_ff56nodeT(nde.Flipped, "Flipped");
    try s.append_ff56nodeT(nde.UniqueNumber, "UniqueNumber");
    try s.append_ff56nodeT(nde.GUID, "GUID");

    try s.append_ff50nodeT("Followers", 0, nde.Followers.len);
    for (nde.Followers) |follower| {
        parse_Network_cTrackFollower(s, follower);
    }
    try s.append_ff70nodeT("Followers");

    try s.append_ff56nodeT(nde.TotalMass, "TotalMass");
    try s.append_ff56nodeT(nde.Speed, "Speed");

    try s.append_ff50nodeT("Velocity", 0, 1);
    try parse_cHcRVector4(s, nde.Velocity);
    try s.append_ff70nodeT("Velocity");

    try s.append_ff56nodeT(nde.InTunnel, "InTunnel");
    try s.append_ff56nodeT(nde.DisabledEngine, "DisabledEngine");
    try s.append_ff56nodeT(nde.AWSTimer, "AWSTimer");
    try s.append_ff56nodeT(nde.AWSExpired, "AWSExpired");
    try s.append_ff56nodeT(nde.TPWSDistance, "TPWSDistance");

    try s.append_ff70nodeT("cWagon");
}

fn parse_cHcRVector4(s: *status, nde: sm.cHcRVector4) !void {
    try s.append_ff50nodeT("cHcRVector4", nde.Id, 2);
    try s.append_ff50nodeT("Element", nde.Id, 2);

    for (nde.Element.len) |elem| {
        s.append_eNode56(elem, "sFloat32");
    }

    try s.append_ff70nodeT("Element");
    try s.append_ff70nodeT("cHcRVector4");
}

fn parse_cCargoComponent(s: *status, nde: sm.cCargoComponent) !void {
    try s.append_ff50nodeT("cCargoComponent", nde.Id, 2);
    try s.append_ff56nodeT(nde, "IsPreLoaded");

    try s.append_ff50nodeT("InitialLevel", 0, nde.InitialLevel.len);
    for (nde.InitialLevel) |Val| {
        s.append_eNode56(Val, "sFloat32");
    }
    try s.append_ff70nodeT("InitialLevel");

    try s.append_ff70nodeT("Network::cDirection");
}

fn parse_cControlContainer(s: *status, nde: sm.cControlContainer) !void {
    try s.append_ff50nodeT("cControlContainer", nde.Id, 3);

    try s.append_ff56nodeT(nde.Time, "Time");
    try s.append_ff56nodeT(nde.FrameTime, "FrameTime");
    try s.append_ff56nodeT(nde.CabEndWithKey, "CabEndWithKey");

    try s.append_ff70nodeT("cControlContainer");
}

fn parse_cAnimObjectRender(s: *status, nde: sm.cAnimObjectRender) !void {
    try s.append_ff50nodeT("cAnimObjectRender", nde.Id, 6);

    try s.append_ff56nodeT(nde.DetailLevel, "DetailLevel");
    try s.append_ff56nodeT(nde.Global, "Global");
    try s.append_ff56nodeT(nde.Saved, "Saved");
    try s.append_ff56nodeT(nde.Palette0Index, "Palette0Index");
    try s.append_ff56nodeT(nde.Palette1Index, "Palette1Index");
    try s.append_ff56nodeT(nde.Palette2Index, "Palette2Index");

    try s.append_ff70nodeT("cAnimObjectRender");
}

fn parse_iBlueprintLibrary_cBlueprintSetId(s: *status, nde: sm.iBlueprintLibrary_cBlueprintSetId) !void {
    try s.append_ff50nodeT("iBlueprintLibrary_cBlueprintSetId", 0, 2);

    try s.append_ff56nodeT(nde.Provider, "Provider");
    try s.append_ff56nodeT(nde.Product, "Product");

    try s.append_ff70nodeT("iBlueprintLibrary_cBlueprintSetId");
}

fn parse_iBlueprintLibrary_cAbsoluteBlueprintID(s: *status, nde: sm.iBlueprintLibrary_cAbsoluteBlueprintID) !void {
    try s.append_ff50nodeT("iBlueprintLibrary_cAbsoluteBlueprintID", 0, 2);

    try s.append_ff50nodeT("BlueprintSetID", 0, 1);
    try parse_iBlueprintLibrary_cBlueprintSetId(s, nde.BlueprintSetId);
    try s.append_ff70nodeT("BlueprintSetID");

    try s.append_ff56nodeT(nde.BlueprintID, "BlueprintID");

    try s.append_ff70nodeT("iBlueprintLibrary_cAbsoluteBlueprintID");
}

fn parse_cFarMatrix(s: *status, nde: sm.cFarMatrix) !void {
    try s.append_ff50nodeT("cFarMatrix", nde.Id, 5);
    try s.append_ff56nodeT(nde.Height, "Height");
    try s.append_ff56nodeT(nde.RXAxis, "RXAxis");
    try s.append_ff56nodeT(nde.RYAxis, "RYAxis");
    try s.append_ff56nodeT(nde.RZAxis, "RZAxis");

    try s.append_ff50nodeT("RFarPosition", 0, 1);
    try parse_cFarVector2(s, nde.RFarPosition);
    try s.append_ff70nodeT("RFarPosition");

    try s.append_ff70nodeT("cFarMatrix");
}

fn parse_cPosOri(s: *status, nde: sm.cPosOri) !void {
    try s.append_ff50nodeT("cPosOri", nde.Id, 2);

    try s.append_ff56nodeT(nde.Scale, "Scale");

    try s.append_ff50nodeT("RFarMatrix", 0, 1);
    try parse_cFarMatrix(s, nde.RFarMatrix);
    try s.append_ff70nodeT("RFarMatrix");

    try s.append_ff70nodeT("cPosOri");
}

fn parse_cEntityContainer(s: *status, nde: sm.cEntityContainer) !void {
    try s.append_ff50nodeT("cEntityContainer", nde.Id, 1);

    try s.append_ff50nodeT("StaticChildrenMatrix", 0, 1);
    try s.append_eNode41(s, "sFloat32", nde.StaticChildrenMatrix);
    try s.append_ff70nodeT("StaticChildrenMatrix");

    try s.append_ff70nodeT("cEntityContainer");
}

fn parse_Component(s: *status, nde: sm.Component) !void {
    switch (nde) {
        .PassWagon => parse_PassWagon(s, nde),
        .CargoWagon => parse_CargoWagon(s, nde),
        .Engine => parse_Engine(s, nde),
    }
}

fn parse_cEngineSimContainer(s: *status, nde: sm.cEngineSimContainer) !void {
    // TODO: This might not be empty?
    try s.append_ff50nodeT("cEngineSimContainer", nde.Id, 0);
    try s.append_ff70nodeT("cEngineSimContainer");
}

fn parse_cOwnedEntity(s: *status, nde: sm.cOwnedEntity) !void {
    try s.append_ff50nodeT("cOwnedEntity", nde.Id, 5);

    parse_Component(s, nde.Component);

    try s.append_ff50nodeT("BlueprintID", 0, 1);
    try parse_iBlueprintLibrary_cAbsoluteBlueprintID(s, nde.BlueprintID);
    try s.append_ff70nodeT("BlueprintID");

    try s.append_ff50nodeT("ReskinBlueprintID", 0, 1);
    try parse_iBlueprintLibrary_cAbsoluteBlueprintID(s, nde.ReskinBlueprintID);
    try s.append_ff70nodeT("ReskinBlueprintID");

    try s.append_ff56nodeT(nde.Name, "Name");

    try s.append_ff50nodeT("EntityID", 0, 1);
    try parse_cGUID(s, nde.EntityID);
    try s.append_ff70nodeT("EntityID");

    try s.append_ff70nodeT("cOwnedEntity");
}

fn parse_cConsist(s: *status, nde: sm.cConsist) !void {
    try s.append_ff50nodeT("cConsist", nde.Id, 12);

    try s.append_ff50nodeT("RailVehicles", 0, nde.RailVehicles.len);
    for (nde.RailVehicles) |vehicle| {
        parse_cOwnedEntity(s, vehicle);
    }
    try s.append_ff70nodeT("RailVehicles");

    try s.append_ff50nodeT("FrontFollower", 0, 1);
    try parse_Network_cTrackFollower(s, nde.FrontFollower);
    try s.append_ff70nodeT("FrontFollower");

    try s.append_ff50nodeT("RearFollower", 0, 1);
    try parse_Network_cTrackFollower(s, nde.RearFollower);
    try s.append_ff70nodeT("RearFollower");

    try s.append_ff50nodeT("Driver", 0, 1);
    try parse_cDriver(s, nde.Driver);
    try s.append_ff70nodeT("Driver");

    try s.append_ff56nodeT(nde.InPortalName, "InPortalName");
    try s.append_ff56nodeT(nde.DriverEngineIndex, "DriverEngineIndex");

    try s.append_ff50nodeT("PlatformRibbonGUID", 0, 1);
    try parse_cGUID(s, nde.PlatformRibbonGUID);
    try s.append_ff70nodeT("PlatformRibbonGUID");

    try s.append_ff56nodeT(nde.PlatformTimeRemaining, "PlatformTimeRemaining");
    try s.append_ff56nodeT(nde.MaxPermissableSpeed, "MaxPermissableSpeed");

    try s.append_ff50nodeT("CurrentDirection", 0, 1);
    try parse_Network_cDirection(s, nde.CurrentDirection);
    try s.append_ff70nodeT("CurrentDirection");

    try s.append_ff56nodeT(nde.IgnorePhysicsFrames, "IgnorePhysicsFrames");
    try s.append_ff56nodeT(nde.IgnoreProximity, "IgnoreProximity");

    try s.append_ff70nodeT("cConsist");
}

fn parse_Record(s: *status, nde: sm.Record) !void {
    try s.append_ff50nodeT("Record", 0, 1);

    for (nde.cConsists) |consist| {
        parse_cConsist(s, consist);
    }
    try s.append_ff70nodeT("Record");
}

fn parse_cRecordSet(s: *status, nde: sm.cRecordSet) !void {
    try s.append_ff50nodeT("cRecordSet", 0, 1);

    parse_Record(s, nde.cRecordSet);

    try s.append_ff70nodeT("cRecordSet");
}
