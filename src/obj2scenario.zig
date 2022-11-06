const std = @import("std");
const parser = @import("bin2obj.zig");
const json = @import("custom_json.zig");
const n = @import("node.zig");
const sm = @import("scenarioModel.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = arena.allocator();
const size_limit = std.math.maxInt(u32);

const NODE_TYPE = enum {
    FF50,
    FF56,
};

const status = struct {
    nodeList: []const n.node,
    current: usize,

    pub fn init(nodes: []const n.node) status {
        return status{
            .nodeList = nodes,
            .current = 0,
        };
    }
};

pub fn parse(nodes: []const n.node) ![]const u8 {
    const scenarioModelObj = try buildModel(nodes);
    var string = std.ArrayList(u8).init(allocator);
    try json.stringify(scenarioModelObj, .{}, string.writer());
    return string.items;
}

fn buildModel(nodes: []const n.node) sm.cRecordSet {
    _ = nodes;
    return undefined;
}

fn parseNode(s: *status) n.dataUnion {
    defer s.current += 1;
    return s.nodeList[s.current].ff56node.value;
}

fn parse_sTimeOfDay(s: *status) sm.sTimeOfDay {
    s.current += 1;
    defer s.current += 1;

    const hour = parseNode(s)._sInt32;
    const minute = parseNode(s)._sInt32;
    const second = parseNode(s)._sInt32;

    return sm.sTimeOfDay{
        ._iHour = hour,
        ._iMinute = minute,
        ._iSeconds = second,
    };
}

fn parse_parseLocalisation_cUserLocalisedString(s: *status) !sm.Localisation_cUserLocalisedString {
    s.current += 1;
    defer s.current += 1;

    const english = parseNode(s)._cDeltaString;
    const french = parseNode(s)._cDeltaString;
    const italian = parseNode(s)._cDeltaString;
    const german = parseNode(s)._cDeltaString;
    const spanish = parseNode(s)._cDeltaString;
    const dutch = parseNode(s)._cDeltaString;
    const polish = parseNode(s)._cDeltaString;
    const russian = parseNode(s)._cDeltaString;

    var otherList = std.ArrayList(sm.Localization_otherLanguage).init(allocator);
    const otherListLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < otherListLen) : (i += 1) {
        const tempNode = sm.Localization_otherLanguage{
            .LangName = s.nodeList[s.current + i].ff56node.name,
            .Value = s.nodeList[s.current + i].ff56node.value._cDeltaString,
        };
        try otherList.append(tempNode);
    }
    s.current += otherListLen;
    const key = parseNode(s)._cDeltaString;

    return sm.Localisation_cUserLocalisedString{
        .English = english,
        .French = french,
        .Italian = italian,
        .German = german,
        .Spanish = spanish,
        .Dutch = dutch,
        .Polish = polish,
        .Russian = russian,
        .Other = otherList.items,
        .Key = key,
    };
}

fn parse_cGUID(s: *status) sm.cGUID {
    const uuid = s.nodeList[s.current + 1].ff56node.value._sUInt64;
    const devString = s.nodeList[s.current + 2].ff56node.value._cDeltaString;
    s.current += 3;

    return sm.cGUID{
        .UUID = uuid,
        .DevString = devString,
    };
}

fn parse_DriverInstruction(s: *status) sm.DriverInstruction {
    const numberInstructions = s.nodeList[s.current].ff50node.children;
    s.current += 1;
    defer s.current += 1;

    var i: u32 = 0;
    while (i < numberInstructions) : (i += 1) {
        switch (s.nodeList[s.current].ff50node.name) {
            "cTriggerInstruction" => parse_cTriggerInstruction(s),
            "cPickupPassengers" => parse_cPickupPassengers(s),
            "cStopAtDestination" => parse_cStopAtDestination(s),
            "cConsistOperation" => parse_cConsistOperation(s),
        }
    }
}

fn parse_cDriverInstructionTarget(s: *status) sm.parse_cDriverInstructionTarget {
    const idVal = s.nodeList[s.current + 0].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const displayName = parseNode(s)._cDeltaString;
    const timeTabled = parseNode(s)._bool;
    const performance = parseNode(s)._sInt32;
    const minSpeed = parseNode(s)._sInt32;
    const durationSecs = parseNode(s)._sFloat32;
    const entityName = parseNode(s)._cDeltaString;
    const trainOrder = parseNode(s)._bool;
    const operation = parseNode(s)._cDeltaString;
    const deadline = parse_sTimeOfDay(s);

    const pickingUp = parseNode(s)._cDeltaString;
    const duration = parseNode(s)._cDeltaString;
    const handleOffPath = parseNode(s)._cDeltaString;
    const earliestDepartureTime = parseNode(s)._cDeltaString;
    const durationSet = parseNode(s)._cDeltaString;
    const reversingAllowed = parseNode(s)._cDeltaString;
    const waypoint = parseNode(s)._cDeltaString;
    const hidden = parseNode(s)._cDeltaString;
    const progressCode = parseNode(s)._cDeltaString;
    const arrivalTime = parseNode(s)._cDeltaString;
    const departureTime = parseNode(s)._cDeltaString;
    const tickedTime = parseNode(s)._cDeltaString;
    const dueTime = parseNode(s)._cDeltaString;

    var railVehicleNumbersList = std.ArrayList([]const u8).init(allocator);
    const railVehicleNumbersListLen = s.nodeList[s.current].ff50node.children;
    var i: u32 = 0;
    while (i < railVehicleNumbersListLen) : (i += 1) {
        try railVehicleNumbersList.append(s.nodeList[s.current + 14 + i].ff56node._cDeltaString);
    }
    s.current += 1 + railVehicleNumbersListLen;

    const timingTestTime = parseNode(s)._cDeltaString;
    const groupName = parse_parseLocalisation_cUserLocalisedString;
    const showRVNumbersWithGroup = parseNode(s)._cDeltaString;
    const scenarioChainTarget = parseNode(s)._cDeltaString;
    const scenarioChainGUID = parseNode(s)._cDeltaString;

    return sm.cDriverInstructionTarget{
        .id = idVal,
        .DisplayName = displayName,
        .Timetabled = timeTabled,
        .Performance = performance,
        .MinSpeed = minSpeed,
        .DurationSecs = durationSecs,
        .EntityName = entityName,
        .TrainOrder = trainOrder,
        .Operation = operation,
        .Deadline = deadline,
        .PickingUp = pickingUp,
        .Duration = duration,
        .HandleOffPath = handleOffPath,
        .EarliestDepartureTime = earliestDepartureTime,
        .DurationSet = durationSet,
        .ReversingAllowed = reversingAllowed,
        .Waypoint = waypoint,
        .Hidden = hidden,
        .ProgressCode = progressCode,
        .ArrivalTime = arrivalTime,
        .DepartureTime = departureTime,
        .TickedTime = tickedTime,
        .DueTime = dueTime,
        .RailVehicleNumber = railVehicleNumbersList.items,
        .TimingTestTime = timingTestTime,
        .GroupName = groupName,
        .ShowRVNumbersWithGroup = showRVNumbersWithGroup,
        .ScenarioChainTarget = scenarioChainTarget,
        .ScenarioChainGUID = scenarioChainGUID,
    };
}

fn parse_cPickupPassengers(s: *status) sm.cPickupPassengers {
    const idVal = s.nodeList[s.current].id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = parse_parseLocalisation_cUserLocalisedString(s);
    const triggerTrainStop = parseNode(s)._bool;
    const triggerWheelSlip = parseNode(s)._bool;
    const wheelSlipDuration = parseNode(s)._sInt16;
    const triggerSound = parse_cGUID(s);
    const triggerAnimation = parse_cGUID(s);
    const secondsDelay = parseNode(s)._sInt16;
    const active = parseNode(s)._bool;
    const arriveTime = parse_sTimeOfDay(s);
    const departTime = parse_sTimeOfDay(s);
    const condition = parseNode(s)._cDeltaString;
    const successEvent = parseNode(s)._cDeltaString;
    const failureEvent = parseNode(s)._cDeltaString;
    const started = parseNode(s)._bool;
    const satisfied = parseNode(s)._bool;
    const deltaTarget = parse_cDriverInstructionTarget(s);
    const travelForwards = parseNode(s)._bool;
    const unloadPassengers = parseNode(s)._bool;

    return sm.cPickupPassengers{
        .id = idVal,
        .ActivationLevel = activationLevel,
        .SuccessTextToBeSavedMessage = successTextToBeSavedMessage,
        .FailureTextToBeSavedMessage = failureTextToBeSavedMessage,
        .DisplayTextToBeSavedMessage = displayTextToBeSavedMessage,
        .TriggeredText = triggeredText,
        .UntriggeredText = untriggeredText,
        .DisplayText = displayText,
        .TriggerTrainStop = triggerTrainStop,
        .TriggerWheelSlip = triggerWheelSlip,
        .WheelSlipDuration = wheelSlipDuration,
        .TriggerSound = triggerSound,
        .TriggerAnimation = triggerAnimation,
        .SecondsDelay = secondsDelay,
        .Active = active,
        .ArriveTime = arriveTime,
        .DepartTime = departTime,
        .Condition = condition,
        .SuccessEvent = successEvent,
        .FailureEvent = failureEvent,
        .Started = started,
        .Satisfied = satisfied,
        .DeltaTarget = deltaTarget,
        .TravelForwards = travelForwards,
        .UnloadPassengers = unloadPassengers,
    };
}

fn parse_cConsistOperation(s: *status) sm.cConsistOperation {
    const idVal = s.nodeList[s.current].id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = parse_parseLocalisation_cUserLocalisedString(s);
    const triggerTrainStop = parseNode(s)._bool;
    const triggerWheelSlip = parseNode(s)._bool;
    const wheelSlipDuration = parseNode(s)._sInt16;
    const triggerSound = parse_cGUID(s);
    const triggerAnimation = parse_cGUID(s);
    const secondsDelay = parseNode(s)._sInt16;
    const active = parseNode(s)._bool;
    const arriveTime = parse_sTimeOfDay(s);
    const departTime = parse_sTimeOfDay(s);
    const condition = parseNode(s)._cDeltaString;
    const successEvent = parseNode(s)._cDeltaString;
    const failureEvent = parseNode(s)._cDeltaString;
    const started = parseNode(s)._bool;
    const satisfied = parseNode(s)._bool;
    const deltaTarget = parse_cDriverInstructionTarget(s);
    const operationOrder = parseNode(s)._bool;
    const firstUpdateDone = parseNode(s)._bool;
    const lastCompletedTargetIndex = parseNode(s)._sInt32;
    const currentTargetIndex = parseNode(s)._sUInt32;
    const targetCompletedTime = parseNode(s)._sFloat32;

    return sm.cConsistOperation{
        .id = idVal,
        .ActivationLevel = activationLevel,
        .SuccessTextToBeSavedMessage = successTextToBeSavedMessage,
        .FailureTextToBeSavedMessage = failureTextToBeSavedMessage,
        .DisplayTextToBeSavedMessage = displayTextToBeSavedMessage,
        .TriggeredText = triggeredText,
        .UntriggeredText = untriggeredText,
        .DisplayText = displayText,
        .TriggerTrainStop = triggerTrainStop,
        .TriggerWheelSlip = triggerWheelSlip,
        .WheelSlipDuration = wheelSlipDuration,
        .TriggerSound = triggerSound,
        .TriggerAnimation = triggerAnimation,
        .SecondsDelay = secondsDelay,
        .Active = active,
        .ArriveTime = arriveTime,
        .DepartTime = departTime,
        .Condition = condition,
        .SuccessEvent = successEvent,
        .FailureEvent = failureEvent,
        .Started = started,
        .Satisfied = satisfied,
        .DeltaTarget = deltaTarget,
        .OperationOrder = operationOrder,
        .FirstUpdateDone = firstUpdateDone,
        .LastCompletedTargetIndex = lastCompletedTargetIndex,
        .CurrentTargetIndex = currentTargetIndex,
        .TargetCompletedTime = targetCompletedTime,
    };
}

fn parse_cStopAtDestination(s: *status) sm.cStopAtDestination {
    const idVal = s.nodeList[s.current].id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = parse_parseLocalisation_cUserLocalisedString(s);
    const triggerTrainStop = parseNode(s)._bool;
    const triggerWheelSlip = parseNode(s)._bool;
    const wheelSlipDuration = parseNode(s)._sInt16;
    const triggerSound = parse_cGUID(s);
    const triggerAnimation = parse_cGUID(s);
    const secondsDelay = parseNode(s)._sInt16;
    const active = parseNode(s)._bool;
    const arriveTime = parse_sTimeOfDay(s);
    const departTime = parse_sTimeOfDay(s);
    const condition = parseNode(s)._cDeltaString;
    const successEvent = parseNode(s)._cDeltaString;
    const failureEvent = parseNode(s)._cDeltaString;
    const started = parseNode(s)._bool;
    const satisfied = parseNode(s)._bool;
    const deltaTarget = parse_cDriverInstructionTarget(s);
    const travelForwards = parseNode(s)._bool;

    return sm.cStopAtDestination{
        .id = idVal,
        .ActivationLevel = activationLevel,
        .SuccessTextToBeSavedMessage = successTextToBeSavedMessage,
        .FailureTextToBeSavedMessage = failureTextToBeSavedMessage,
        .DisplayTextToBeSavedMessage = displayTextToBeSavedMessage,
        .TriggeredText = triggeredText,
        .UntriggeredText = untriggeredText,
        .DisplayText = displayText,
        .TriggerTrainStop = triggerTrainStop,
        .TriggerWheelSlip = triggerWheelSlip,
        .WheelSlipDuration = wheelSlipDuration,
        .TriggerSound = triggerSound,
        .TriggerAnimation = triggerAnimation,
        .SecondsDelay = secondsDelay,
        .Active = active,
        .ArriveTime = arriveTime,
        .DepartTime = departTime,
        .Condition = condition,
        .SuccessEvent = successEvent,
        .FailureEvent = failureEvent,
        .Started = started,
        .Satisfied = satisfied,
        .DeltaTarget = deltaTarget,
        .TravelForwards = travelForwards,
    };
}

fn parse_cTriggerInstruction(s: *status) sm.cTriggerInstruction {
    const idVal = s.nodeList[s.current].id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = parse_parseLocalisation_cUserLocalisedString(s);
    const triggerTrainStop = parseNode(s)._bool;
    const triggerWheelSlip = parseNode(s)._bool;
    const wheelSlipDuration = parseNode(s)._sInt16;
    const triggerSound = parse_cGUID(s);
    const triggerAnimation = parse_cGUID(s);
    const secondsDelay = parseNode(s)._sInt16;
    const active = parseNode(s)._bool;
    const arriveTime = parse_sTimeOfDay(s);
    const departTime = parse_sTimeOfDay(s);
    const condition = parseNode(s)._cDeltaString;
    const successEvent = parseNode(s)._cDeltaString;
    const failureEvent = parseNode(s)._cDeltaString;
    const started = parseNode(s)._bool;
    const satisfied = parseNode(s)._bool;
    const deltaTarget = parse_cDriverInstructionTarget(s);
    const startTime = parseNode(s)._sFloat32;

    return sm.cTriggerInstruction{
        .id = idVal,
        .ActivationLevel = activationLevel,
        .SuccessTextToBeSavedMessage = successTextToBeSavedMessage,
        .FailureTextToBeSavedMessage = failureTextToBeSavedMessage,
        .DisplayTextToBeSavedMessage = displayTextToBeSavedMessage,
        .TriggeredText = triggeredText,
        .UntriggeredText = untriggeredText,
        .DisplayText = displayText,
        .TriggerTrainStop = triggerTrainStop,
        .TriggerWheelSlip = triggerWheelSlip,
        .WheelSlipDuration = wheelSlipDuration,
        .TriggerSound = triggerSound,
        .TriggerAnimation = triggerAnimation,
        .SecondsDelay = secondsDelay,
        .Active = active,
        .ArriveTime = arriveTime,
        .DepartTime = departTime,
        .Condition = condition,
        .SuccessEvent = successEvent,
        .FailureEvent = failureEvent,
        .Started = started,
        .Satisfied = satisfied,
        .DeltaTarget = deltaTarget,
        .StartTime = startTime,
    };
}

fn parse_cDriverInstructionContainer(s: *status) sm.cDriverInstructionContainer {
    const idVal = s.nodeList[s.current].id;
    s.current += 1;
    defer s.current += 1;

    const driverInstruction = parse_DriverInstruction(s);
    return sm.cDriverInstructionContainer{
        .id = idVal,
        .DriverInstruction = driverInstruction,
    };
}

////////////////////////////////////////////////////////////
/////////////////// Test Area //////////////////////////////
////////////////////////////////////////////////////////////

test "Parse Time of Day" {
    // Arrange
    const parentNode = n.node{ .ff50node = n.ff50node{
        .name = "sTimeOfDay",
        .id = 0,
        .children = 3,
    } };
    const hourNode = n.node{ .ff56node = n.ff56node{
        .name = "_iHour",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 1 },
    } };
    const minuteNode = n.node{ .ff56node = n.ff56node{
        .name = "_iMinute",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 3 },
    } };
    const secondNode = n.node{ .ff56node = n.ff56node{
        .name = "_iSeconds",
        .dType = n.dataType._sInt32,
        .value = n.dataUnion{ ._sInt32 = 5 },
    } };
    const nodeList = &[_]n.node{ parentNode, hourNode, minuteNode, secondNode };
    var s = status.init(nodeList);

    // Act
    const result = parse_sTimeOfDay(&s);

    // Assert
    try expectEqual(result._iHour, 1);
    try expectEqual(result._iMinute, 3);
    try expectEqual(result._iSeconds, 5);
    try expectEqual(s.current, 5);
}

test "Parse Localization_cUserLocalizedString" {
    // Arrange
    const parentNode = n.node{ .ff50node = n.ff50node{
        .name = "cUserLocalizedString",
        .id = 0,
        .children = 10,
    } };
    const english = n.node{ .ff56node = n.ff56node{
        .name = "English",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "English String" },
    } };
    const french = n.node{ .ff56node = n.ff56node{
        .name = "French",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const italian = n.node{ .ff56node = n.ff56node{
        .name = "Italian",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const german = n.node{ .ff56node = n.ff56node{
        .name = "German",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const spanish = n.node{ .ff56node = n.ff56node{
        .name = "Spanish",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const dutch = n.node{ .ff56node = n.ff56node{
        .name = "Dutch",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const polish = n.node{ .ff56node = n.ff56node{
        .name = "Polish",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const russian = n.node{ .ff56node = n.ff56node{
        .name = "Russian",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "" },
    } };
    const other = n.node{ .ff50node = n.ff50node{
        .name = "Other",
        .id = 0,
        .children = 1,
    } };
    const chinese = n.node{ .ff56node = n.ff56node{
        .name = "Chinese",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "How" },
    } };
    const key = n.node{ .ff56node = n.ff56node{
        .name = "English",
        .dType = n.dataType._cDeltaString,
        .value = n.dataUnion{ ._cDeltaString = "KEY VAL" },
    } };
    const nodeList = &[_]n.node{ parentNode, english, french, italian, german, spanish, dutch, polish, russian, other, chinese, key };
    var s = status.init(nodeList);

    // Act
    const result = try parse_parseLocalisation_cUserLocalisedString(&s);

    // Assert
    try expectEqualStrings(result.English, "English String");
    try expectEqualStrings(result.Italian, "");
    try expectEqualStrings(result.Key, "KEY VAL");
    try expectEqualStrings(result.Other[0].Value, "How");
    try expectEqual(s.current, 13);
}
