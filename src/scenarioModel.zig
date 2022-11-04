const cRecordSet = struct {
    id: u32,
    Record: Record,
};

const Record = struct {
    cConsists: []cConsist,
};

const cConsist = struct {
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

const cOwnedEntity = struct {
    Component: Component,
    BlueprintID: iBlueprintLibrary_cAbsoluteBlueprintID,
    ReskinBlueprintID: iBlueprintLibrary_cAbsoluteBlueprintID,
    Name: []const u8,
    EntityID: cGUID,
};

const Component = struct {
    cWagon: cWagon,
    cAnimObjectRender: cAnimObjectRender,
    cPosOri: cPosOri,
    cControlContainer: cControlContainer,
    cCargoComponent: cCargoComponent,
    cEntityContainer: cEntityContainer,
    cScriptComponent: cScriptComponent,
};

const cWagon = struct {
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

const Network_cTrackFollower = struct {
    id: u32,
    Height: f32,
    _type: []const u8,
    Position: f32,
    Direction: Network_cDirection,
    RibbonId: cGUID,
};

const Network_cDirection = struct {
    _dir: []const u8,
};

const cGUID = struct {
    UUID: []u64,
    DevString: []const u8,
};

const cHcRVector4 = struct {
    Element: []f32,
};

const iBlueprintLibrary_cAbsoluteBlueprintID = struct {
    BlueprintSetId: iBlueprintLibrary_cBlueprintSetId,
    BlueprintID: []const u8,
};

const iBlueprintLibrary_cBlueprintSetId = struct {
    Provider: []const u8,
    Product: []const u8,
};

const cAnimObjectRender = struct {
    id: u32,
    DetailLevel: i32,
    Global: bool,
    Saved: bool,
    Palette0Index: u8,
    Palette1Index: u8,
    Palette2Index: u8,
};

const cPosOri = struct {
    id: u32,
    scale: [4]f32,
    RFarMatrix: cFarMatrix,
};

const cControlContainer = struct {
    id: u32,
    Time: f32,
    FrameTime: f32,
    CabEndsWithKey: []const u8,
};

const cCargoComponent = struct {
    id: u32,
    IsPreLoaded: []const u8,
    InitialLevel: f32,
};

const cEntityContainer = struct {
    id: u32,
    StaticChildrenMatrix: [16]f32,
};

const cScriptComponent = struct {
    DebugDisplay: bool,
    StateName: []const u8,
};

const cFarMatrix = struct {
    id: u32,
    Height: f32,
    RXAxis: [4]f32,
    RYAxis: [4]f32,
    RZAxis: [4]f32,
    RFarPosition: cFarVector2,
};

const cFarVector2 = struct {
    X: cFarCoordinate,
    Z: cFarCoordinate,
};

const cFarCoordinate = struct {
    RouteCoordinate: cRouteCoordinate,
    TileCoordinate: cTileCoordinate,
};

const cRouteCoordinate = struct {
    Distance: i32,
};

const cTileCoordinate = struct {
    Distance: f32,
};

const cDriver = struct {
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

const cDriverInstructionTarget = struct {
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

const Localisation_cUserLocalisedString = struct {
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

const cDriverInstructionContainer = struct {
    id: u32,
    DriverInstruction: DriverInstruction,
};

const DriverInstruction = struct {
    cTriggerInstruction: cT
