pub const cRecordSet = struct {
    id: u32,
    Record: Record,
};

pub const Record = struct {
    cConsists: []cConsist,
};

pub const cConsist = struct {
    RailVehicles: []cOwnedEntity,
    FrontFollower: Network_cTrackFollower,
    RearFollower: Network_cTrackFollower,
    Driver: ?cDriver,
    InPortalName: []const u8,
    DriverEngineIndex: i32,
    PlatformRibbonGUID: cGUID,
    PlatformTimeRemaining: f32,
    MaxPermissableSpeed: f32,
    CurrentDirection: Network_cDirection,
    IgnorePhysicsFrames: i32,
    IgnoreProximity: bool,
};

pub const cOwnedEntity = struct {
    Component: Component,
    BlueprintID: iBlueprintLibrary_cAbsoluteBlueprintID,
    ReskinBlueprintID: iBlueprintLibrary_cAbsoluteBlueprintID,
    Name: []const u8,
    EntityID: cGUID,
};

pub const Component = struct {
    cWagon: cWagon,
    cAnimObjectRender: cAnimObjectRender,
    cPosOri: cPosOri,
    cControlContainer: cControlContainer,
    cCargoComponent: cCargoComponent,
    cEntityContainer: cEntityContainer,
    cScriptComponent: cScriptComponent,
};

pub const cWagon = struct {
    id: u32,
    PantographInfo: []const u8,
    PantographIsDirectional: bool,
    LastPantographControlValue: f32,
    Flipped: bool,
    UniqueNumber: []const u8,
    GUID: []const u8,
    Followers: []Network_cTrackFollower,
    TotalMass: f32,
    Speed: f32,
    Velocity: cHcRVector4,
    InTunnel: bool,
};

pub const Network_cTrackFollower = struct {
    id: u32,
    Height: f32,
    _type: []const u8,
    Position: f32,
    Direction: Network_cDirection,
    RibbonId: cGUID,
};

pub const Network_cDirection = struct {
    _dir: []const u8,
};

pub const cGUID = struct {
    UUID: []u64,
    DevString: []const u8,
};

pub const cHcRVector4 = struct {
    Element: []f32,
};

pub const iBlueprintLibrary_cAbsoluteBlueprintID = struct {
    BlueprintSetId: iBlueprintLibrary_cBlueprintSetId,
    BlueprintID: []const u8,
};

pub const iBlueprintLibrary_cBlueprintSetId = struct {
    Provider: []const u8,
    Product: []const u8,
};

pub const cAnimObjectRender = struct {
    id: u32,
    DetailLevel: i32,
    Global: bool,
    Saved: bool,
    Palette0Index: u8,
    Palette1Index: u8,
    Palette2Index: u8,
};

pub const cPosOri = struct {
    id: u32,
    scale: [4]f32,
    RFarMatrix: cFarMatrix,
};

pub const cControlContainer = struct {
    id: u32,
    Time: f32,
    FrameTime: f32,
    CabEndsWithKey: []const u8,
};

pub const cCargoComponent = struct {
    id: u32,
    IsPreLoaded: []const u8,
    InitialLevel: f32,
};

pub const cEntityContainer = struct {
    id: u32,
    StaticChildrenMatrix: [16]f32,
};

pub const cScriptComponent = struct {
    DebugDisplay: bool,
    StateName: []const u8,
};

pub const cFarMatrix = struct {
    id: u32,
    Height: f32,
    RXAxis: [4]f32,
    RYAxis: [4]f32,
    RZAxis: [4]f32,
    RFarPosition: cFarVector2,
};

pub const cFarVector2 = struct {
    X: cFarCoordinate,
    Z: cFarCoordinate,
};

pub const cFarCoordinate = struct {
    RouteCoordinate: cRouteCoordinate,
    TileCoordinate: cTileCoordinate,
};

pub const cRouteCoordinate = struct {
    Distance: i32,
};

pub const cTileCoordinate = struct {
    Distance: f32,
};

pub const cDriver = struct {
    id: u32,
    FinalDestination: cDriverInstructionTarget,
    PlayerDriver: bool,
    ServiceName: Localisation_cUserLocalisedString,
    InitialRV: [3][]const u8,
    StartTime: f32,
    StartSpeed: f32,
    EndSpeed: f32,
    ServiceClass: i32,
    ExpectedPerformance: f32,
    PlayerControlled: bool,
    PriorPathingStatus: []const u8,
    PathingStatus: []const u8,
    RepathIn: f32,
    ForcedRepath: bool,
    OffPath: bool,
    StartTriggerDistanceFromPlayerSquared: f32,
    DriverInstructionContainer: cDriverInstructionContainer,
    UnloadedAtStart: bool,
};

pub const cDriverInstructionTarget = struct {
    id: u32,
    DisplayName: []const u8,
    Timetabled: bool,
    Performance: i32,
    MinSpeed: i32,
    DurationSecs: f32,
    EntityName: []const u8,
    TrainOrder: bool,
    Operation: []const u8,
    Deadline: sTimeOfDay,
    PickingUp: bool,
    Duration: u32,
    HandleOffPath: bool,
    EarliestDepartureTime: f32,
    DurationSet: bool,
    ReversingAllowed: bool,
    Waypoint: bool,
    Hidden: bool,
    ProgressCode: []const u8,
    ArrivalTime: f32,
    DepartureTime: f32,
    TickedTime: f32,
    DueTime: f32,
    RailVehicleNumber: undefined,
    TimingTestTime: f32,
    GroupName: Localisation_cUserLocalisedString,
    ShowRVNumbersWithGroup: bool,
    ScenarioChainTarget: bool,
    ScenarioChainGUID: cGUID,
};

pub const Localisation_cUserLocalisedString = struct {
    English: []const u8,
    French: []const u8,
    Italian: []const u8,
    German: []const u8,
    Spanish: []const u8,
    Dutch: []const u8,
    Polish: []const u8,
    Russian: []const u8,
    Other: undefined,
    Key: []const u8,
};

pub const sTimeOfDay = struct {
    _iHour: i32,
    _iMinute: i32,
    _iSeconds: i32,
};

pub const cDriverInstructionContainer = struct {
    id: u32,
    DriverInstruction: DriverInstruction,
};

pub const DriverInstruction = union {
    cTriggerInstruction: cTriggerInstruction,
    cStopAtDestination: cStopAtDestination,
    cConsistOperation: cConsistOperation,
};

pub const cTriggerInstruction = struct {
    id: u32,
    ActivationLevel: i16,
    SuccessTextToBeSavedMessage: bool,
    FailureTextToBeSavedMessage: bool,
    DisplayTextToBeSavedMessage: bool,
    TriggeredText: Localisation_cUserLocalisedString,
    UntriggeredText: Localisation_cUserLocalisedString,
    DisplayText: Localisation_cUserLocalisedString,
    TriggerTrainStop: bool,
    TriggerWheelSlip: bool,
    WheelSlipDuration: i16,
    TriggerSound: cGUID,
    TriggerAnimation: cGUID,
    SecondsDelay: i16,
    Active: bool,
    ArriveTime: sTimeOfDay,
    DepartTime: sTimeOfDay,
    Condition: []const u8,
    SuccessEvent: []const u8,
    FailureEvent: []const u8,
    Started: bool,
    Satisfied: bool,
    DeltaTarget: undefined,
    StartTime: f32,
};

pub const cStopAtDestination = struct {
    ActivationLevel: i16,
    SuccessTextToBeSavedMessage: bool,
    FailureTextToBeSavedMessage: bool,
    DisplayTextToBeSavedMessage: bool,
    TriggeredText: Localisation_cUserLocalisedString,
    UntriggeredText: Localisation_cUserLocalisedString,
    DisplayText: Localisation_cUserLocalisedString,
    TriggerTrainStop: bool,
    TriggerWheelSlip: bool,
    WheelSlipDuration: i16,
    TriggerSound: cGUID,
    TriggerAnimation: cGUID,
    SecondsDelay: i16,
    Active: bool,
    ArriveTime: sTimeOfDay,
    DepartTime: sTimeOfDay,
    Condition: []const u8,
    SuccessEvent: []const u8,
    FailureEvent: []const u8,
    Started: bool,
    Satisfied: bool,
    DeltaTarget: cDriverInstructionTarget,
    TravelForwards: bool,
};

pub const cConsistOperation = struct {
    ActivationLevel: i16,
    SuccessTextToBeSavedMessage: bool,
    FailureTextToBeSavedMessage: bool,
    DisplayTextToBeSavedMessage: bool,
    TriggeredText: Localisation_cUserLocalisedString,
    UntriggeredText: Localisation_cUserLocalisedString,
    DisplayText: Localisation_cUserLocalisedString,
    TriggerTrainStop: bool,
    TriggerWheelSlip: bool,
    WheelSlipDuration: i16,
    TriggerSound: cGUID,
    TriggerAnimation: cGUID,
    SecondsDelay: i16,
    Active: bool,
    ArriveTime: sTimeOfDay,
    DepartTime: sTimeOfDay,
    Condition: []const u8,
    SuccessEvent: []const u8,
    FailureEvent: []const u8,
    Started: bool,
    Satisfied: bool,
    DeltaTarget: cDriverInstructionTarget,
    OperationOrder: bool,
    FirstUpdateDone: bool,
    LastCompletedTargetIndex: i32,
    CurrentTargetIndex: u32,
    TargetCompletedTime: f32,
};
