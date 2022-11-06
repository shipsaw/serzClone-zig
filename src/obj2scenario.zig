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
    var s = status.init(nodes);
    const scenarioModelObj = try parse_cRecordSet(&s);
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
    s.current += 2;
    defer s.current += 1;

    var uuid: [2]u64 = undefined;
    uuid[0] = parseNode(s)._sUInt64;
    uuid[1] = parseNode(s)._sUInt64;
    s.current += 1;

    const devString = parseNode(s)._cDeltaString;

    return sm.cGUID{
        .UUID = uuid,
        .DevString = devString,
    };
}

fn parse_DriverInstruction(s: *status) ![]sm.DriverInstruction {
    const numberInstructions = s.nodeList[s.current].ff50node.children;
    s.current += 1;
    defer s.current += 1;

    var i: u32 = 0;
    var instructionArray = std.ArrayList(sm.DriverInstruction).init(allocator);

    while (i < numberInstructions) : (i += 1) {
        const currentName = s.nodeList[s.current].ff50node.name;
        if (std.mem.eql(u8, "cTriggerInstruction", currentName)) {
            const boxedInstruction = sm.DriverInstruction{ .cTriggerInstruction = (try parse_cTriggerInstruction(s)) };
            try instructionArray.append(boxedInstruction);
        } else if (std.mem.eql(u8, "cPickupPassengers", currentName)) {
            const boxedInstruction = sm.DriverInstruction{ .cPickupPassengers = (try parse_cPickupPassengers(s)) };
            try instructionArray.append(boxedInstruction);
        } else if (std.mem.eql(u8, "cStopAtDestination", currentName)) {
            const boxedInstruction = sm.DriverInstruction{ .cStopAtDestination = (try parse_cStopAtDestination(s)) };
            try instructionArray.append(boxedInstruction);
        } else if (std.mem.eql(u8, "cConsistOperaion", currentName)) {
            const boxedInstruction = sm.DriverInstruction{ .cConsistOperation = (try parse_cConsistOperation(s)) };
            try instructionArray.append(boxedInstruction);
        } else unreachable;
    }
    return instructionArray.items;
}

fn parse_cDriverInstructionTarget(s: *status) !?sm.cDriverInstructionTarget {
    if (@TypeOf(s.nodeList[s.current + 1]) == n.ff4enode) {
        return null;
    }

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

    const pickingUp = parseNode(s)._bool;
    const duration = parseNode(s)._sUInt32;
    const handleOffPath = parseNode(s)._bool;
    const earliestDepartureTime = parseNode(s)._sFloat32;
    const durationSet = parseNode(s)._bool;
    const reversingAllowed = parseNode(s)._bool;
    const waypoint = parseNode(s)._bool;
    const hidden = parseNode(s)._bool;
    const progressCode = parseNode(s)._cDeltaString;
    const arrivalTime = parseNode(s)._sFloat32;
    const departureTime = parseNode(s)._sFloat32;
    const tickedTime = parseNode(s)._sFloat32;
    const dueTime = parseNode(s)._sFloat32;

    var railVehicleNumbersList = std.ArrayList([]const u8).init(allocator);
    const railVehicleNumbersListLen = s.nodeList[s.current].ff50node.children;
    var i: u32 = 0;
    while (i < railVehicleNumbersListLen) : (i += 1) {
        try railVehicleNumbersList.append(s.nodeList[s.current + 14 + i].ff56node.value._cDeltaString);
    }
    s.current += 1 + railVehicleNumbersListLen;

    const timingTestTime = parseNode(s)._sFloat32;
    const groupName = try parse_parseLocalisation_cUserLocalisedString(s);
    const showRVNumbersWithGroup = parseNode(s)._bool;
    const scenarioChainTarget = parseNode(s)._bool;
    const scenarioChainGUID = parse_cGUID(s);

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

fn parse_cPickupPassengers(s: *status) !sm.cPickupPassengers {
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = try parse_parseLocalisation_cUserLocalisedString(s);
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
    const deltaTarget = try parse_cDriverInstructionTarget(s);
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

fn parse_cConsistOperation(s: *status) !sm.cConsistOperation {
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = try parse_parseLocalisation_cUserLocalisedString(s);
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
    const deltaTarget = try parse_cDriverInstructionTarget(s);
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

fn parse_cStopAtDestination(s: *status) !sm.cStopAtDestination {
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = try parse_parseLocalisation_cUserLocalisedString(s);
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
    const deltaTarget = try parse_cDriverInstructionTarget(s);
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

fn parse_cTriggerInstruction(s: *status) !sm.cTriggerInstruction {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const activationLevel = parseNode(s)._sInt16;
    const successTextToBeSavedMessage = parseNode(s)._bool;
    const failureTextToBeSavedMessage = parseNode(s)._bool;
    const displayTextToBeSavedMessage = parseNode(s)._bool;
    const triggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const untriggeredText = try parse_parseLocalisation_cUserLocalisedString(s);
    const displayText = try parse_parseLocalisation_cUserLocalisedString(s);
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
    const deltaTarget = try parse_cDriverInstructionTarget(s);
    const startTime = parseNode(s)._sFloat32;

    return sm.cTriggerInstruction{
        .Id = id,
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

fn parse_cDriverInstructionContainer(s: *status) !sm.cDriverInstructionContainer {
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const driverInstruction = parse_DriverInstruction(s);
    return sm.cDriverInstructionContainer{
        .id = idVal,
        .DriverInstruction = try driverInstruction,
    };
}

fn parse_cDriver(s: *status) !sm.cDriver {
    const idVal = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const finalDestination = try parse_cDriverInstructionTarget(s);
    const playerDriver = parseNode(s)._bool;
    const serviceName = try parse_parseLocalisation_cUserLocalisedString(s);

    var initialRVList = std.ArrayList([]const u8).init(allocator);
    const initialRVListLength = s.nodeList[s.current].ff50node.children;

    s.current += 1;
    var i: u32 = 0;
    while (i < initialRVListLength) : (i += 1) {
        try initialRVList.append(s.nodeList[s.current].ff56node.value._cDeltaString);
        s.current += 1;
    }

    const initialRV = initialRVList.items;
    const startTime = parseNode(s)._sFloat32;
    const startSpeed = parseNode(s)._sFloat32;
    const endSpeed = parseNode(s)._sFloat32;
    const serviceClass = parseNode(s)._sInt32;
    const expectedPerformance = parseNode(s)._sFloat32;
    const playerControlled = parseNode(s)._bool;
    const priorPathingStatus = parseNode(s)._cDeltaString;
    const pathingStatus = parseNode(s)._cDeltaString;
    const repathIn = parseNode(s)._sFloat32;
    const forcedRepath = parseNode(s)._bool;
    const offPath = parseNode(s)._bool;
    const startTriggerDistanceFromPlayerSquared = parseNode(s)._sFloat32;
    const driverInstructionContainer = try parse_cDriverInstructionContainer(s);
    const unloadedAtStart = parseNode(s)._bool;

    return sm.cDriver{
        .id = idVal,
        .FinalDestination = finalDestination,
        .PlayerDriver = playerDriver,
        .ServiceName = serviceName,
        .InitialRV = initialRV,
        .StartTime = startTime,
        .StartSpeed = startSpeed,
        .EndSpeed = endSpeed,
        .ServiceClass = serviceClass,
        .ExpectedPerformance = expectedPerformance,
        .PlayerControlled = playerControlled,
        .PriorPathingStatus = priorPathingStatus,
        .PathingStatus = pathingStatus,
        .RepathIn = repathIn,
        .ForcedRepath = forcedRepath,
        .OffPath = offPath,
        .StartTriggerDistanceFromPlayerSquared = startTriggerDistanceFromPlayerSquared,
        .DriverInstructionContainer = driverInstructionContainer,
        .UnloadedAtStart = unloadedAtStart,
    };
}

fn parse_cRouteCoordinate(s: *status) sm.cRouteCoordinate {
    s.current += 1;
    defer s.current += 1;
    const distance = parseNode(s)._sInt32;
    return sm.cRouteCoordinate{
        .Distance = distance,
    };
}

fn parse_cTileCoordinate(s: *status) sm.cTileCoordinate {
    s.current += 1;
    defer s.current += 1;
    const distance = parseNode(s)._sFloat32;
    return sm.cTileCoordinate{
        .Distance = distance,
    };
}

fn parse_cFarCoordinate(s: *status) sm.cFarCoordinate {
    s.current += 1;
    defer s.current += 1;
    const routeCoordinate = parse_cRouteCoordinate(s);
    const tileCoordinate = parse_cTileCoordinate(s);
    return sm.cFarCoordinate{
        .RouteCoordinate = routeCoordinate,
        .TileCoordinate = tileCoordinate,
    };
}

fn parse_cFarVector2(s: *status) sm.cFarVector2 {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;
    const x = parse_cFarCoordinate(s);
    const z = parse_cFarCoordinate(s);
    return sm.cFarVector2{
        .Id = id,
        .X = x,
        .Z = z,
    };
}

fn parse_Network_cDirection(s: *status) sm.Network_cDirection {
    s.current += 1;
    defer s.current += 1;
    const dir = parseNode(s)._cDeltaString;
    return sm.Network_cDirection{
        ._dir = dir,
    };
}

fn parse_Network_cTrackFollower(s: *status) sm.Network_cTrackFollower {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const height = parseNode(s)._sFloat32;
    const tpe = parseNode(s)._cDeltaString;
    const position = parseNode(s)._sFloat32;
    const direction = parse_Network_cDirection(s);
    const ribbonId = parse_cGUID(s);
    return sm.Network_cTrackFollower{
        .Id = id,
        .Height = height,
        ._type = tpe,
        .Position = position,
        .Direction = direction,
        .RibbonId = ribbonId,
    };
}

fn parse_cWagon(s: *status) !sm.cWagon {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;

    const pantographInfo = parseNode(s)._cDeltaString;
    const pantographIsDirectional = parseNode(s)._bool;
    const lastPantographControlValue = parseNode(s)._sFloat32;
    const flipped = parseNode(s)._bool;
    const uniqueNumber = parseNode(s)._cDeltaString;
    const gUID = parseNode(s)._cDeltaString;

    var followerList = std.ArrayList(sm.Network_cTrackFollower).init(allocator);
    const followerListLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;
    var i: u32 = 0;
    while (i < followerListLen) : (i += 1) {
        try followerList.append(parse_Network_cTrackFollower(s));
    }
    s.current += 1;

    const followers = followerList.items;
    const totalMass = parseNode(s)._sFloat32;
    const speed = parseNode(s)._sFloat32;
    const velocity = try parse_cHcRVector4(s);
    const inTunnel = parseNode(s)._bool;

    return sm.cWagon{
        .Id = id,
        .PantographInfo = pantographInfo,
        .PantographIsDirectional = pantographIsDirectional,
        .LastPantographControlValue = lastPantographControlValue,
        .Flipped = flipped,
        .UniqueNumber = uniqueNumber,
        .GUID = gUID,
        .Followers = followers,
        .TotalMass = totalMass,
        .Speed = speed,
        .Velocity = velocity,
        .InTunnel = inTunnel,
    };
}

fn parse_cHcRVector4(s: *status) !sm.cHcRVector4 {
    s.current += 2;
    defer s.current += 2;

    var vectorList = std.ArrayList(f32).init(allocator);
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        try vectorList.append(parseNode(s)._sFloat32);
    }

    return sm.cHcRVector4{
        .Element = vectorList.items,
    };
}

fn parse_cScriptComponent(s: *status) sm.cScriptComponent {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const debugDisplay = parseNode(s)._bool;
    const stateName = parseNode(s)._cDeltaString;

    return sm.cScriptComponent{
        .Id = id,
        .DebugDisplay = debugDisplay,
        .StateName = stateName,
    };
}

fn parse_cCargoComponent(s: *status) sm.cCargoComponent {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const isPreloaded = parseNode(s)._cDeltaString;
    const initialLevel = parseNode(s)._sFloat32;

    return sm.cCargoComponent{
        .Id = id,
        .IsPreLoaded = isPreloaded,
        .InitialLevel = initialLevel,
    };
}

fn parse_cControlContainer(s: *status) sm.cControlContainer {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const time = parseNode(s)._sFloat32;
    const frameTime = parseNode(s)._sFloat32;
    const cabEndsWithKey = parseNode(s)._cDeltaString;

    return sm.cControlContainer{
        .Id = id,
        .Time = time,
        .FrameTime = frameTime,
        .CabEndsWithKey = cabEndsWithKey,
    };
}

fn parse_cAnimObjectRender(s: *status) sm.cAnimObjectRender {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const detailLevel = parseNode(s)._sInt32;
    const global = parseNode(s)._bool;
    const saved = parseNode(s)._bool;
    const palette0Index = parseNode(s)._sUInt8;
    const palette1Index = parseNode(s)._sUInt8;
    const palette2Index = parseNode(s)._sUInt8;

    return sm.cAnimObjectRender{
        .Id = id,
        .DetailLevel = detailLevel,
        .Global = global,
        .Saved = saved,
        .Palette0Index = palette0Index,
        .Palette1Index = palette1Index,
        .Palette2Index = palette2Index,
    };
}

fn parse_iBlueprintLibrary_cBlueprintSetId(s: *status) sm.iBlueprintLibrary_cBlueprintSetId {
    s.current += 1;
    defer s.current += 1;

    const provider = parseNode(s)._cDeltaString;
    const product = parseNode(s)._cDeltaString;

    return sm.iBlueprintLibrary_cBlueprintSetId{
        .Provider = provider,
        .Product = product,
    };
}

fn parse_iBlueprintLibrary_cAbsoluteBlueprintID(s: *status) sm.iBlueprintLibrary_cAbsoluteBlueprintID {
    s.current += 1;
    defer s.current += 1;

    const blueprintSetId = parse_iBlueprintLibrary_cBlueprintSetId(s);
    const blueprintID = parseNode(s)._cDeltaString;

    return sm.iBlueprintLibrary_cAbsoluteBlueprintID{
        .BlueprintSetId = blueprintSetId,
        .BlueprintID = blueprintID,
    };
}

fn parse_cFarMatrix(s: *status) sm.cFarMatrix {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const height = parseNode(s)._sFloat32;

    var rxAxis: [4]f32 = undefined;
    for (s.nodeList[s.current].ff41node.values.items) |val, i| {
        rxAxis[i] = val._sFloat32;
    }
    s.current += 1;

    var ryAxis: [4]f32 = undefined;
    for (s.nodeList[s.current].ff41node.values.items) |val, i| {
        ryAxis[i] = val._sFloat32;
    }
    s.current += 1;

    var rzAxis: [4]f32 = undefined;
    for (s.nodeList[s.current].ff41node.values.items) |val, i| {
        rzAxis[i] = val._sFloat32;
    }
    s.current += 1;

    const rFarPosition = parse_cFarVector2(s);

    return sm.cFarMatrix{
        .Id = id,
        .Height = height,
        .RXAxis = rxAxis,
        .RYAxis = ryAxis,
        .RZAxis = rzAxis,
        .RFarPosition = rFarPosition,
    };
}

fn parse_cPosOri(s: *status) sm.cPosOri {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    var scale: [4]f32 = undefined;
    for (s.nodeList[s.current].ff41node.values.items) |val, i| {
        scale[i] = val._sFloat32;
    }
    s.current += 1;

    const rFarMatrix = parse_cFarMatrix(s);

    return sm.cPosOri{
        .Id = id,
        .Scale = scale,
        .RFarMatrix = rFarMatrix,
    };
}

fn parse_cEntityContainer(s: *status) !sm.cEntityContainer {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 2;

    var staticChildrenMatrix = std.ArrayList([16]f32).init(allocator);
    const staticChildrenMatrixLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < staticChildrenMatrixLen) : (i += 1) {
        try staticChildrenMatrix.append([_]f32{0} ** 16);
        var j: u32 = 0;
        while (j < 16) : (j += 1) {
            staticChildrenMatrix.items[i][j] = s.nodeList[s.current].ff41node.values.items[j]._sFloat32;
        }
        s.current += 1;
    }

    return sm.cEntityContainer{
        .Id = id,
        .StaticChildrenMatrix = staticChildrenMatrix.items,
    };
}

fn parse_Component(s: *status) !sm.Component {
    s.current += 1;
    defer s.current += 1;

    const wagon = try parse_cWagon(s);
    const animObjectRender = parse_cAnimObjectRender(s);
    const posOri = parse_cPosOri(s);
    const controlContainer = parse_cControlContainer(s);
    const cargoComponent = parse_cCargoComponent(s);
    const entityContainer = try parse_cEntityContainer(s);
    const scriptComponent = parse_cScriptComponent(s);

    return sm.Component{
        .cWagon = wagon,
        .cAnimObjectRender = animObjectRender,
        .cPosOri = posOri,
        .cControlContainer = controlContainer,
        .cCargoComponent = cargoComponent,
        .cEntityContainer = entityContainer,
        .cScriptComponent = scriptComponent,
    };
}

fn parse_cOwnedEntity(s: *status) !sm.cOwnedEntity {
    s.current += 1;
    defer s.current += 1;

    const component = try parse_Component(s);
    const blueprintID = parse_iBlueprintLibrary_cAbsoluteBlueprintID(s);
    const reskinBlueprintID = parse_iBlueprintLibrary_cAbsoluteBlueprintID(s);
    const name = parseNode(s)._cDeltaString;
    const entityID = parse_cGUID(s);

    return sm.cOwnedEntity{
        .Component = component,
        .BlueprintID = blueprintID,
        .ReskinBlueprintID = reskinBlueprintID,
        .Name = name,
        .EntityID = entityID,
    };
}

fn parse_cConsist(s: *status) !sm.cConsist {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    var railVehiclesArray = std.ArrayList(sm.cOwnedEntity).init(allocator);
    const railVehiclesArrayLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < railVehiclesArrayLen) : (i += 1) {
        try railVehiclesArray.append(try parse_cOwnedEntity(s));
    }
    const railVehicles = railVehiclesArray.items;
    s.current += 1;

    const frontFollower = parse_Network_cTrackFollower(s);
    const rearFollower = parse_Network_cTrackFollower(s);
    const driver = try parse_cDriver(s);
    const inPortalName = parseNode(s)._cDeltaString;
    const driverEngineIndex = parseNode(s)._sInt32;
    const platformRibbonGUID = parse_cGUID(s);
    const platformTimeRemaining = parseNode(s)._sFloat32;
    const maxPermissableSpeed = parseNode(s)._sFloat32;
    const currentDirection = parse_Network_cDirection(s);
    const ignorePhysicsFrames = parseNode(s)._sInt32;
    const ignoreProximity = parseNode(s)._bool;

    return sm.cConsist{
        .Id = id,
        .RailVehicles = railVehicles,
        .FrontFollower = frontFollower,
        .RearFollower = rearFollower,
        .Driver = driver,
        .InPortalName = inPortalName,
        .DriverEngineIndex = driverEngineIndex,
        .PlatformRibbonGUID = platformRibbonGUID,
        .PlatformTimeRemaining = platformTimeRemaining,
        .MaxPermissableSpeed = maxPermissableSpeed,
        .CurrentDirection = currentDirection,
        .IgnorePhysicsFrames = ignorePhysicsFrames,
        .IgnoreProximity = ignoreProximity,
    };
}

fn parse_Record(s: *status) !sm.Record {
    var consistsArray = std.ArrayList(sm.cConsist).init(allocator);
    const consistsArrayLen = s.nodeList[s.current].ff50node.children;
    s.current += 1;

    var i: u32 = 0;
    while (i < consistsArrayLen) : (i += 1) {
        try consistsArray.append(try parse_cConsist(s));
    }
    const consists = consistsArray.items;
    s.current += 1;

    return sm.Record{
        .cConsists = consists,
    };
}

fn parse_cRecordSet(s: *status) !sm.cRecordSet {
    const id = s.nodeList[s.current].ff50node.id;
    s.current += 1;
    defer s.current += 1;

    const record = try parse_Record(s);
    return sm.cRecordSet{
        .Id = id,
        .Record = record,
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
