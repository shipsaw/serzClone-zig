const std = @import("std");
// const keywords = std.StringHashMap(dataType).init(allocator);

pub const dataType = enum {
    _bool,
    _sUInt8,
    _sInt32,
    _sUInt64,
    _sFloat32,
    _cDeltaString,
};

pub const dataUnion = union(dataType) {
    _bool: bool,
    _sUInt8: u8,
    _sInt32: i32,
    _sUInt64: u64,
    _sFloat32: f32,
    _cDeltaString: []const u8,
};

pub const ff41token = struct {
    name: []const u8,
    numElements: u8,
    dType: dataType,
    values: std.ArrayList(dataUnion),
};

pub const ff4etoken = struct {};

pub const ff50token = struct {
    name: []const u8,
    id: u32,
    children: u32,
};

pub const ff56token = struct {
    name: []const u8,
    dType: dataType,
    value: dataUnion,
};

pub const ff70token = struct {
    name: []const u8,
};

pub const token = union(enum) {
    ff41token: ff41token,
    ff4etoken: ff4etoken,
    ff50token: ff50token,
    ff56token: ff56token,
    ff70token: ff70token,
};
